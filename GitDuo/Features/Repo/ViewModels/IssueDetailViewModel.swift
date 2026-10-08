import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// Issue 详情页（PRD §4.9）的状态。
///
/// ## 两条数据、两种失败后果（决策 #57）
///
/// | 数据 | 失败 |
/// |---|---|
/// | 详情（标题 / 状态 / 正文） | **整页失败** —— `detail` 变 `.failed`，屏幕上只有一个重试 |
/// | 评论 | **降级** —— `comments` 变 `.failed`，正文与头部照常，评论区自带重试 |
///
/// 这两条**各有各的状态、各有各的出口**，所以本类型里它们是两个字段而不是一个
/// "页面状态"。合成一个的下场是评论拉失败时正文也消失 —— 而那是两件不同的事。
/// （`IssueDetailSnapshot` 的类型说明把这条写成了 `LoadIssueDetail` 的设计依据。）
///
/// ## 草稿（决策 #59）
///
/// 输入框的内容**随输入即落盘**（`draft` 的 `didSet`）。这看起来频繁，但它是那句
/// 逐字承诺「草稿已保留，可重试」（`ConversationCopy.sendFailureNotice`）唯一
/// 站得住的实现方式：
///
/// - 只在"发送失败"那一刻存 ⇒ 用户改了几个字后被杀进程，改的那部分丢了；
/// - 只在"离开页面"存 ⇒ `onDisappear` 在 App 被系统回收时不一定跑得到。
///
/// 而落盘实现就是一次 `UserDefaults` 写（几十字节），比"琢磨什么时候存才不会漏"
/// 便宜得多。
@MainActor
@Observable
final class IssueDetailViewModel {

    let fullName: String
    let number: Int

    /// 详情。失败 ⇒ 整页失败。
    private(set) var detail: LoadState<IssueDetail> = .idle

    /// 评论区。**与 `detail` 独立**（见类型说明）。
    ///
    /// ⚠️ 进页时它一直是 `.idle` 直到详情回来 —— `IssueDetailSnapshot.comments`
    /// 的成功返回里不会是 `.idle` / `.loading`，所以那两档在界面上是同一个意思
    /// （东西还没来 ⇒ 骨架，`LoadState.presentation` 那条规则）。
    private(set) var comments: LoadState<Page<IssueComment>> = .idle

    /// 输入框内容（评论草稿）。
    var draft: String = "" {
        didSet {
            // ⚠️ 恢复草稿时**不能触发保存** —— 那会把 `savedAt` 改写成"刚进页面的时间"，
            //    而那个时间戳的用途正是"这条草稿是什么时候写的"。
            guard !isRestoringDraft, draft != oldValue else { return }
            persistDraft()
        }
    }

    /// 发送在途（按钮转圈 + 防重复提交）。
    private(set) var isSending = false

    /// 发送失败提示条的文案；`nil` = 不显示。
    ///
    /// ⚠️ 它**不自动消失**（原型那 2.6 秒是演示节奏，见 `NoticeBar` 的说明）：
    /// 这句里最要紧的是「可重试」，自动藏起来会把那句引导一起带走。
    /// 清掉的时机只有一个 —— 下一次点发送。
    private(set) var sendNotice: String?

    /// 见 `draft` 的 `didSet`。
    private var isRestoringDraft = false

    private let loader: LoadIssueDetail
    private let sender: PostIssueComment
    private let drafts: any CommentDraftStore
    private let toast: ToastCenter

    init(
        fullName: String,
        number: Int,
        loader: LoadIssueDetail,
        sender: PostIssueComment,
        drafts: any CommentDraftStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.number = number
        self.loader = loader
        self.sender = sender
        self.drafts = drafts
        self.toast = toast
    }

    // MARK: - 取数

    /// 进页。**先读草稿、再取数**。
    ///
    /// 顺序是有意的：草稿读的是本地存储（一次 `await`，快），取数是网络（慢）。
    /// 反过来的话，用户会先看到一个**空**输入框、过一会儿字自己冒出来 ——
    /// 那一瞬他很可能开始打字，然后自己的第一个字符与旧草稿拼在一起。
    func start() async {
        guard !detail.hasFinished else { return }
        await restoreDraft()
        await load()
    }

    func refresh() async {
        await load(pullToRefresh: true)
    }

    /// 评论区自己的重试出口 —— **决策 #57「分别重试」的那一个**。
    ///
    /// ⚠️ 它不重取详情（那份数据就在手边，重取会让整页闪一次骨架屏）。
    /// `LoadIssueDetail.comments` 不抛错：它是"界面上的一块区域的状态"，
    /// 不是会让整页开天窗的错误。
    func retryComments() async {
        comments = await loader.comments(fullName: fullName, number: number)
    }

    private func load(pullToRefresh: Bool = false) async {
        let hadContent = detail.value != nil
        if !hadContent { detail.begin() }

        do {
            let snapshot = try await loader.load(fullName: fullName, number: number)
            detail.succeed(snapshot.detail)
            // ⚠️ 评论**整份替换**（不是追加）：重取回来的就是这一页的全部，
            //    而"新旧合并"要先解决去重，那个问题只有分页加载才需要面对。
            comments = snapshot.comments
        } catch {
            // ⚠️ 已有内容时的下拉刷新**不能把整屏变成失败态**（§8.5）——
            //    给一条 toast，内容留在屏幕上（同 `CommitDetailViewModel`）。
            if hadContent, pullToRefresh {
                toast.show(RefreshCopy.failed)
            } else {
                detail.fail(Self.failure(from: error))
            }
        }
    }

    // MARK: - 派生

    /// 已加载的评论。**顺序即服务端给的顺序**（按时间升序），本层不重排。
    var commentItems: [IssueComment] {
        comments.value?.items ?? []
    }

    /// 头部元信息（`#42 · my-git/gitduo · 由 reviewer-a 创建于 2 小时前`）。
    func metaLabel(now: Date) -> String {
        detail.value?.metaLabel(fullName: fullName, now: now) ?? ""
    }

    // MARK: - 发评论

    /// 点「发送」。
    ///
    /// 三条路径（§4.9）：
    /// - **空内容** ⇒ 提示 `先写点内容再发送`，**不发请求**（判据在
    ///   `PostIssueComment.canSend`，本层不自己 `trim` 一遍）；
    /// - **成功** ⇒ 把服务端回的那条追加到评论区、清草稿、给成功提示；
    /// - **失败** ⇒ 留草稿 + 显示提示条（两件事都不能少，见类型说明）。
    func send() async {
        guard !isSending else { return }

        guard PostIssueComment.canSend(draft) else {
            toast.show(ConversationCopy.emptyCommentToast)
            return
        }

        isSending = true
        defer { isSending = false }

        // 上一次的失败提示在这一刻退场：用户已经又按了一次发送，那条"可重试"不再是最新的事。
        sendNotice = nil

        // ⚠️ 原样发出（不 trim）：前导缩进在 Markdown 里是有意义的。
        let body = draft

        do {
            let comment = try await sender.send(fullName: fullName, number: number, body: body)
            // 先清草稿再追加：清空那一刻 `didSet` 就会把它从存储里删掉（`save` 的语义是"空即删"）。
            await clearDraft()
            await append(comment)
            toast.show(ConversationCopy.commentSentToast)
        } catch {
            // 那句话逐字承诺「草稿已保留，可重试」⇒ 两件事缺一不可。
            await drafts.save(fullName: fullName, number: number, body: body, at: Date())
            sendNotice = ConversationCopy.sendFailureNotice
        }
    }

    /// 把刚发出去的那条挂到评论区末尾。
    ///
    /// ⚠️ 用**服务端回的那条**（`PostIssueComment.send` 的返回值）而不是自己造一条
    /// "刚刚"：自造的那条会与服务端真正落库的时间、以及别人机器上看到的时间都对不上。
    private func append(_ comment: IssueComment) async {
        guard case let .loaded(page) = comments else {
            // 评论根本还没加载出来（失败 / 恰好没取过）时发了一条 ⇒ **重取一次**。
            // ⚠️ 不能把它塞进一个空列表：那会造出"这个 Issue 只有这一条评论"的假象，
            //    而用户是知道上面还有别的讨论的。
            await retryComments()
            return
        }
        comments = .loaded(
            Page(
                items: page.items + [comment],
                nextCursor: page.nextCursor,
                headers: page.headers
            )
        )
    }

    // MARK: - 草稿

    private func restoreDraft() async {
        guard let existing = await drafts.draft(fullName: fullName, number: number) else { return }
        isRestoringDraft = true
        draft = existing.body
        isRestoringDraft = false
    }

    /// 随输入落盘（见类型说明）。
    private func persistDraft() {
        let body = draft
        Task { await drafts.save(fullName: fullName, number: number, body: body, at: Date()) }
    }

    /// 发送成功后清草稿。
    ///
    /// ⚠️ 两件事都做：`draft = ""` 会让 `didSet` 走一遍"空即删"，而这里**再显式**
    /// `discard` 一次。多这一句是因为那句承诺（"发送成功后不能留下已发出的草稿"）
    /// 不值得依赖一个副作用 —— 将来若把 `save` 的"空即删"改成别的语义，
    /// 这里仍然是删干净的。
    private func clearDraft() async {
        draft = ""
        await drafts.discard(fullName: fullName, number: number)
    }

    // MARK: - 私有

    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}
