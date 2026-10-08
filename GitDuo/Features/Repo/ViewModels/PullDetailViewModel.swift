import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// PR 详情页（PRD §4.11、TECH_SPEC §9.9、决策 #57 / #59 / #60）的状态。
///
/// ## 五样数据、五种节奏
///
/// | 数据 | 什么时候取 | 失败之后 |
/// |---|---|---|
/// | **详情**（头部 / 状态 / 增删数） | 进页 | **整页失败** |
/// | **对话**（评论 + 评审合成一条流） | 进页（与详情并发） | **降级** —— 头部照常，那一块自带重试 |
/// | **Commits** | **进这一格才取** | 那一格失败，自带重试 |
/// | **文件** | **进这一格才取** | 同上 |
///
/// 前两样的分工是决策 #57（同 `IssueDetailViewModel`）；后两样是 §9.9 的
/// 「大 PR 不要一开页就拉 100 个文件的 diff」—— 原型也是按分区渲染的
/// （`prSeg(seg)` 只画当前那一档），`PullDetailSnapshot` 的类型说明写了这条。
///
/// ## ⚠️ 为什么 `commits` / `files` 不是"一个分区一个子状态机"
///
/// 两者都只是「一次取一页」：没有翻页入口（规格没给「加载更多提交 / 更多文件」），
/// 也没有本地的增删。`RepoSubListViewModel` 那一套（分页 / 守卫 / 追加去重）
/// 在这里一件都用不上 —— 套上去只多一层要读的代码。
///
/// ## 草稿（决策 #59）
///
/// 与 Issue 详情**同一份存储、同一个键**（`CommentDraftStore` 的说明写明了
/// Issue 与 PR 共用编号空间，本来就不该分两套）。所以行为也逐条相同：
/// 随输入落盘、发送成功清掉、发送失败留草稿 + 提示条。
@MainActor
@Observable
final class PullDetailViewModel {

    let fullName: String
    let number: Int

    /// 只读态（他人仓库）—— **由路由给**（铁律 #7），本层不推断仓库归属。
    ///
    /// ⚠️ 它与"这个 PR 的状态"是两件事，各有各的后果：
    /// 这一条管**操作区有没有按钮**（`PullOperationAvailability`），
    /// 状态那一条管**能不能评论**（`PullDetail.canComment`）。
    /// 合成一个布尔量之后，"他人仓库里一个已合并的 PR"就只能落到其中一种表现上。
    let readOnly: Bool

    // MARK: - 首屏两样

    /// 详情。失败 ⇒ 整页失败。
    private(set) var detail: LoadState<PullDetail> = .idle

    /// 对话。**与 `detail` 独立**（决策 #57）—— 失败时头部与操作区照常显示。
    private(set) var conversation: LoadState<PullConversation> = .idle

    // MARK: - 分区

    /// 当前分区。进页落在**第一格**（`PullSection.initial`，不是写死的 `.conversation`）。
    private(set) var segment: PullSection = .initial

    /// 分区二：Commits。`.idle` = 还没进过这一格。
    private(set) var commits: LoadState<Page<CommitSummary>> = .idle

    /// 分区三：改动文件。`.idle` = 还没进过这一格。
    private(set) var files: LoadState<Page<FileChange>> = .idle

    // MARK: - 评论输入区

    /// 输入框内容（评论草稿）。
    var draft: String = "" {
        didSet {
            // ⚠️ 同 `IssueDetailViewModel`：恢复草稿时**不能触发保存**，
            //    那会把 `savedAt` 改写成"刚进页面的时间"。
            guard !isRestoringDraft, draft != oldValue else { return }
            persistDraft()
        }
    }

    /// 发送在途（按钮转圈 + 防重复提交）。
    private(set) var isSending = false

    /// 发送失败提示条的文案；`nil` = 不显示。
    ///
    /// ⚠️ 它**不自动消失**，清掉的时机只有一个 —— 下一次点发送
    /// （同 `IssueDetailViewModel.sendNotice`）。
    private(set) var sendNotice: String?

    // MARK: - 操作

    /// 合并 / 关闭 / 重新打开在途（操作区按钮转圈 + 防重复提交）。
    private(set) var isWorking = false

    private var isRestoringDraft = false

    private let loader: LoadPullDetail
    private let actions: PullAction
    private let sender: PostIssueComment
    private let drafts: any CommentDraftStore
    private let toast: ToastCenter

    init(
        fullName: String,
        number: Int,
        readOnly: Bool,
        loader: LoadPullDetail,
        actions: PullAction,
        sender: PostIssueComment,
        drafts: any CommentDraftStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.number = number
        self.readOnly = readOnly
        self.loader = loader
        self.actions = actions
        self.sender = sender
        self.drafts = drafts
        self.toast = toast
    }

    // MARK: - 进页 / 刷新

    /// 进页。**先读草稿、再取数**（同 `IssueDetailViewModel.start`：反过来的话
    /// 用户会先看到一个空输入框、过一会儿字自己冒出来，很可能开始打字从而与旧草稿拼在一起）。
    func start() async {
        guard !detail.hasFinished else { return }
        await restoreDraft()
        await load()
    }

    /// 下拉刷新。
    ///
    /// ⚠️ 它比首屏多一件事：**当前那一格如果取过，一并重取**。
    /// 不补这一下的话，用户在「文件」格上拉一把，看到的仍是十分钟前那版 diff ——
    /// 而"刷新过了"这件事本身会让他以为屏幕上就是最新的。
    func refresh() async {
        await load(pullToRefresh: true)
        await reloadActiveSegmentIfLoaded()
    }

    private func load(pullToRefresh: Bool = false) async {
        let hadContent = detail.value != nil
        if !hadContent { detail.begin() }

        do {
            let snapshot = try await loader.load(fullName: fullName, number: number)
            detail.succeed(snapshot.detail)
            // ⚠️ 对话**整份替换**（不是追加）：重取回来的就是这一页的全部。
            conversation = snapshot.conversation
        } catch {
            // ⚠️ 已有内容时的下拉刷新**不能把整屏变成失败态**（§8.5）—— 给一条 toast，
            //    内容留在屏幕上（同 `IssueDetailViewModel`）。
            if hadContent, pullToRefresh {
                toast.show(RefreshCopy.failed)
            } else {
                detail.fail(Self.failure(from: error))
            }
        }
    }

    /// 分区二 / 三的重取，**只补当前这一格**（见 `refresh`）。
    ///
    /// ⚠️ 判据是 `hasFinished`（取过就算，**失败也算**）而不是 `value != nil`：
    /// 上一次失败的那一格也该跟着刷新重取 —— 否则用户拉了半天，
    /// 那一格还是那句"这一块加载失败"。
    private func reloadActiveSegmentIfLoaded() async {
        switch segment {
        case .conversation:
            // 首屏那两样已经在 `load` 里取过了。
            break
        case .commits:
            guard commits.hasFinished else { break }
            commits.begin()
            commits = await loader.commits(fullName: fullName, number: number)
        case .files:
            guard files.hasFinished else { break }
            files.begin()
            files = await loader.files(fullName: fullName, number: number)
        }
    }

    // MARK: - 分区切换

    /// 切到某一格。**第一次进这一格时才取数**。
    func select(segment: PullSection) async {
        self.segment = segment
        await loadSegmentIfNeeded(segment)
    }

    /// 进分区取数（§9.9）。
    ///
    /// ⚠️ 只在 `.idle`（**从没试过**）时取。这样"切回来"不会又发一次请求 ——
    /// 而失败之后也不会自动重发：那一格上有明确的重试按钮
    /// （自动重发的下场是用户在几格之间来回切时看着它反复转圈，
    /// 而每次转圈都是真的在打网络）。
    private func loadSegmentIfNeeded(_ segment: PullSection) async {
        switch segment {
        case .conversation:
            break
        case .commits:
            guard case .idle = commits else { break }
            commits.begin()
            commits = await loader.commits(fullName: fullName, number: number)
        case .files:
            guard case .idle = files else { break }
            files.begin()
            files = await loader.files(fullName: fullName, number: number)
        }
    }

    // MARK: - 三个重试出口

    /// 对话那一块的重试 —— **决策 #57「分别重试」的那一个**。
    ///
    /// ⚠️ 它不重取详情（那份数据就在手边，重取会让整页闪一次骨架屏）。
    func retryConversation() async {
        conversation = await loader.conversation(fullName: fullName, number: number)
    }

    func retryCommits() async {
        commits.begin()
        commits = await loader.commits(fullName: fullName, number: number)
    }

    func retryFiles() async {
        files.begin()
        files = await loader.files(fullName: fullName, number: number)
    }

    // MARK: - 派生

    /// 已加载的时间线（顺序即领域层合出来的顺序，本层不重排）。
    var timelineItems: [PullTimelineItem] {
        conversation.value?.items ?? []
    }

    var commitRows: [CommitSummary] {
        commits.value?.items ?? []
    }

    var fileRows: [FileChange] {
        files.value?.items ?? []
    }

    /// 对话区顶部那条「已由 X 于 {时间} 合并进 main · 讨论已锁定」；未合并 ⇒ `nil`。
    func mergedBanner(now: Date) -> String? {
        detail.value?.mergedBanner(now: now)
    }

    /// 操作区该是四档里的哪一档。
    var operationAvailability: PullOperationAvailability? {
        detail.value?.operationAvailability(readOnly: readOnly)
    }

    /// 讨论还能不能评论（已合并 ⇒ 锁上，与仓库归属无关）。
    ///
    /// ⚠️ 详情没到手时不画输入区（整页是骨架），所以这里用 `?? false`
    /// 而不是"乐观地先给一个能评论"。
    var canComment: Bool {
        detail.value?.canComment ?? false
    }

    // MARK: - 发评论

    /// 点「发送」。三条路径与 Issue 详情逐条相同（§4.11 的口径同 §4.9）。
    func send() async {
        guard !isSending else { return }

        guard PostIssueComment.canSend(draft) else {
            toast.show(ConversationCopy.emptyCommentToast)
            return
        }

        isSending = true
        defer { isSending = false }

        // 上一次的失败提示在这一刻退场（用户已经又按了一次发送）。
        sendNotice = nil

        // ⚠️ 原样发出（不 trim）：前导缩进在 Markdown 里是有意义的。
        let body = draft

        do {
            let comment = try await sender.send(fullName: fullName, number: number, body: body)
            await clearDraft()
            await append(comment)
            toast.show(ConversationCopy.commentSentToast)
        } catch {
            // 那句逐字承诺「草稿已保留，可重试」⇒ 两件事缺一不可。
            await drafts.save(fullName: fullName, number: number, body: body, at: Date())
            sendNotice = ConversationCopy.sendFailureNotice
        }
    }

    /// 把刚发出去的那条挂到时间线末尾。
    ///
    /// ## ⚠️ 它挂的是**一条评论**，而时间线是「评论 + 评审」合成的
    ///
    /// 合并工作是 `LoadPullDetail.conversation` 做的（领域层，有测试钉住顺序与键），
    /// 这里只把它接到末尾**靠的是"新发的评论时间最新"**：
    /// 刚发出去的那一刻晚于这一页里所有已加载的条目。
    ///
    /// ⚠️ 与 Issue 侧不同，这里**不能**在"对话没加载出来"时把它塞进空列表 ——
    /// §9.9 明写时间线是**一条流**，一个只有自己这一句的流会让人以为
    /// 上面那些讨论都不存在了。所以那一档改为重取一次。
    private func append(_ comment: IssueComment) async {
        guard case let .loaded(page) = conversation else {
            await retryConversation()
            return
        }

        // ⚠️ 用**服务端回的那条**（`PostIssueComment.send` 的返回值）而不是自己造一条
        //    "刚刚"：自造那条会与服务端真正落库的时间、以及别人机器上看到的时间都对不上。
        var items = page.items
        items.append(
            PullTimelineItem(
                id: "c-\(comment.id)",
                origin: .comment,
                authorLogin: comment.authorLogin,
                body: comment.body,
                createdAt: comment.createdAt
            )
        )
        conversation = .loaded(
            PullConversation(items: items, hasMore: page.hasMore)
        )
    }

    // MARK: - 三个操作（§4.11 操作区）

    /// 合并（§5.3 的三种方式）。
    ///
    /// ## 三种结局**分开说**（§9.9 的硬要求）
    ///
    /// | 结局 | 落点 |
    /// |---|---|
    /// | 合上了 | `state` 转已合并 + toast `已用 Squash 合并 #57 进 main` |
    /// | 这个 PR 现在不能合（405 / 200 但 `merged == false`） | 单独一句 |
    /// | 有冲突（409） | 单独一句，且**说的是"可以修"** |
    ///
    /// — 折成一句「合并失败」会让"去网页端解掉冲突再回来"这条唯一的出路消失。
    ///
    /// ⚠️ 其余错误（403 / 404 / 断网…）走那句**通用**的操作失败正本
    /// （`ActionCopy.failed`）：§9.9 只给了上面三档的话术，
    /// 编一个"合并失败：你可能是没权限"就是在替服务端下结论。
    func merge(method: PullMergeMethod) async {
        guard !isWorking, let current = detail.value else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let result = try await actions.merge(
                fullName: fullName,
                number: number,
                method: method,
                // ⚠️ "现在"由这里取（不是视图传一个进页时的时间戳）——
                //    合并时间说的必须是**这一次**往返，不是一个可能已经过了十分钟的值。
                now: Date()
            )
            switch result {
            case let .merged(at, _):
                // ⚠️ 走领域层那一条（`markingMerged(at:)`）而不是在这里改两个字段：
                //    它一次要动三处（状态 / 合并时间 / 由前两者派生的能不能评论），
                //    而漏掉任何一处在屏幕上都看不出来。
                detail.succeed(current.markingMerged(at: at))
                toast.show(
                    PullCopy.mergedToast(method: method, number: number, base: current.baseRef)
                )
            case .notMergeable:
                toast.show(PullCopy.mergeNotMergeableToast)
            }
        } catch {
            toast.show(Self.mergeFailure(from: error))
        }
    }

    /// 关闭 PR（§4.11 操作区）。
    func close() async {
        guard let fresh = await updateState(.close) else { return }
        detail.succeed(fresh)
        toast.show(PullCopy.closedToast)
    }

    /// 重新打开 PR（§4.11 操作区）。
    func reopen() async {
        guard let fresh = await updateState(.reopen) else { return }
        detail.succeed(fresh)
        toast.show(PullCopy.reopenedToast)
    }

    /// 关闭 / 重新打开只差一个字符串 ⇒ **一条路径，不写两遍**。
    ///
    /// ## 为什么用服务端**返回的那一份**详情，而不是本地改一个字段
    ///
    /// `PATCH /pulls/{n}` 的响应是**完整的 PR 对象** ⇒ 直接用它。
    /// 本地改一个 `state` 的下场是"界面说已关闭、服务端说还开着"成为可能
    /// （另一个客户端刚重新打开了它），而这种不一致只会在下一次刷新时暴露。
    /// （合并没有这样的响应可用 —— `PUT /merge` 只回 `sha` / `merged` / `message`，
    /// 所以那一条只能走本地更新，见 `markingMerged(at:)`。）
    ///
    /// - Returns: 成功时服务端那一份；失败（含正在途）⇒ `nil`，并且**已经**弹过提示。
    private func updateState(_ which: StateUpdate) async -> PullDetail? {
        guard !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }

        do {
            switch which {
            case .close:
                return try await actions.close(fullName: fullName, number: number)
            case .reopen:
                return try await actions.reopen(fullName: fullName, number: number)
            }
        } catch {
            // ⚠️ 与合并那三档不同：关闭 / 重新打开**没有**规格给的分档话术
            //    （PRD §4.11 只写了"状态置为已关闭 / 开放"）⇒ 用通用正本。
            toast.show(ActionCopy.failed)
            return nil
        }
    }

    private enum StateUpdate {
        case close
        case reopen
    }

    // MARK: - 草稿

    private func restoreDraft() async {
        guard let existing = await drafts.draft(fullName: fullName, number: number) else { return }
        isRestoringDraft = true
        draft = existing.body
        isRestoringDraft = false
    }

    private func persistDraft() {
        let body = draft
        Task { await drafts.save(fullName: fullName, number: number, body: body, at: Date()) }
    }

    /// 发送成功后清草稿。两件事都做 —— 理由同 `IssueDetailViewModel.clearDraft`。
    private func clearDraft() async {
        draft = ""
        await drafts.discard(fullName: fullName, number: number)
    }

    // MARK: - 私有

    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }

    /// 合并失败的**分档**（§9.9 要求三种结局分开说）。
    ///
    /// ⚠️ 409 在这里单独判：`PullAction.merge` 的说明写明"409 照旧抛错"，
    /// 因为冲突**可以修**（去网页端解掉再回来合）—— 这一句与
    /// "这个 PR 现在不能合"是两句不同的话，不能合并。
    private static func mergeFailure(from error: any Error) -> String {
        guard let githubError = error as? GitHubError else { return ActionCopy.failed }
        if case .conflict = githubError { return PullCopy.mergeConflictToast }
        return ActionCopy.failed
    }
}
