import Foundation
import GitHubAPI
import GitDuoCore

/// 一条评审的审批状态（PRD §4.11 的「已批准」胶囊、TECH_SPEC §9.9、决策 #60）。
///
/// ## ⚠️ 它来自 `/pulls/{n}/reviews`，**不是** `/pulls/{n}/comments`
///
/// 决策 #60 是被外部事实推翻文档写法的那一条：`/comments` 是**行内评论**
/// （带 `path` / `line`），**不含**审批状态；`state` 只在 `/reviews` 上
/// （官方枚举 `PullRequestReviewState`）。两处对照表在 `PullReviewDTO`。
///
/// ## 为什么这里可以枚举化，而 `IssueDTO.state` 不行
///
/// 取值集合是官方枚举给的**封闭五档**（不随版本增补 —— 增补会是一次 breaking change），
/// 而 `state` 那个集合 GitHub 还在动。枚举化在这里的价值是"五档各有名字"，
/// 而 `unknown` 兜底保证"某天真多一档"不会变成整页解码失败。
public enum PullReviewState: String, Sendable, Hashable {

    /// 批准。
    case approved = "APPROVED"

    /// 要求修改。
    case changesRequested = "CHANGES_REQUESTED"

    /// 只留了评论。
    case commented = "COMMENTED"

    /// 被驳回（原批准失效）。
    case dismissed = "DISMISSED"

    /// 还没提交。
    case pending = "PENDING"

    /// 认不出来的取值。
    case unknown

    /// 认不出来的取值 ⇒ `.unknown`（同 `FileChange.Status(rawStatus:)` 的兜底思路）。
    public init(rawState: String?) {
        self = PullReviewState(rawValue: rawState ?? "") ?? .unknown
    }

    /// 评论气泡上那枚胶囊的字。
    ///
    /// ## ⚠️ 只有「已批准」有胶囊，另外四档都没有
    ///
    /// PRD §4.11 只写了「可带『已批准』胶囊」，其余四档的呈现口径**没给** ⇒
    /// 保持"不出胶囊"，而不是替界面拍板编四句。
    ///
    /// ⚠️ 与 `PullRequestState.pillTitle`（`Open` / `Merged` / `Closed`，英文）
    /// **有意不同**：那一组是原型 `pillOf()` 里的英文串，而这一句的原型是
    /// `<span class="pill merged">已批准</span>` —— **中文**。两处都照原型，不要统一。
    ///
    /// ⚠️ 原型复用的是 `merged` 那套绿色样式；`StatusPill` 的色调由视图决定，
    /// 本类型只给字。
    public var pillTitle: String? {
        self == .approved ? "已批准" : nil
    }

    /// 这条评审会不会出现在时间线上。
    ///
    /// ⚠️ **`pending` 不出现**：那是"还没提交的评审草稿"，`submitted_at` 为 `null`，
    /// 而 GitHub 只把它给作者自己看。把它画进对话里会让别人看到一段
    /// **从没提交过**的意见 —— 那不只是多一条，是对讨论的失真。
    ///
    /// 判据用 `state`（显式信号）而**不是** `submittedAt == nil`：万一某个已提交的评审
    /// 响应里缺了时间，用后者会把它整条丢掉（丢了没人知道）；
    /// 用前者它仍然显示，只是不显示时间那一截（`PullReviewDTO` 写了这条）。
    public var isPartOfConversation: Bool { self != .pending }
}

/// 一条评审（PRD §4.11 对话分区）。
public struct PullReview: Sendable, Hashable, Identifiable {

    public let id: Int

    /// 评审人。**可以是 `nil`**（账号已删除）。
    public let authorLogin: String?

    public let state: PullReviewState

    /// 评审意见正文。**可以是 `nil`**（只点批准、不写话 —— 那是常态）。
    public let body: String?

    /// 提交时刻。**可以是 `nil`**（`PENDING` 的评审还没提交；见 `isPartOfConversation`）。
    public let submittedAt: Date?

    public init(
        id: Int,
        authorLogin: String? = nil,
        state: PullReviewState,
        body: String? = nil,
        submittedAt: Date? = nil
    ) {
        self.id = id
        self.authorLogin = authorLogin
        self.state = state
        self.body = body
        self.submittedAt = submittedAt
    }
}

/// 对话时间线上的一条 —— **会话评论与评审合成同一条流之后的那一条**。
///
/// ## 为什么必须合并
///
/// §9.9 明写：两者在屏幕上本来就是一条流。原型那一屏里，
/// `pr.u` 的正文下面紧接着 `dev-k` 的评审（`08-pr.js:33-46`），
/// 中间没有任何分组标题。
///
/// ⚠️ **两个来源的 `id` 会撞车**（评论 id 与评审 id 各自编号），
/// 所以键必须带上来源前缀 —— 不带的话 `ForEach` 会**少画一条**，
/// 而屏幕上少一条、没有任何报错。
public struct PullTimelineItem: Sendable, Hashable, Identifiable {

    /// 这条是从哪来的。
    ///
    /// ⚠️ 保留来源不是为了分类显示（两者在屏幕上一模一样），
    /// 而是为了"这条是评审"这件事本身在模型里存在 ——
    /// 将来要给评审加别的呈现时，不必回头去改数据流。
    public enum Origin: Sendable, Hashable {
        case comment
        case review(PullReviewState)
    }

    /// 去重与 `ForEach` 的键：`c-123` / `r-45`。
    public let id: String

    public let origin: Origin

    public let authorLogin: String?

    public let body: String?

    /// 发表 / 提交时刻。
    ///
    /// ⚠️ 评审可以是 `nil`（见 `PullReviewState.isPartOfConversation`）；
    /// 评论不会（`IssueCommentDTO.createdAt` 是必需字段）。
    public let createdAt: Date?

    public init(
        id: String,
        origin: Origin,
        authorLogin: String? = nil,
        body: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.origin = origin
        self.authorLogin = authorLogin
        self.body = body
        self.createdAt = createdAt
    }

    /// 显示名（作者为 `nil` ⇒ `AuthorName.unknown`）。
    public var displayAuthor: String {
        guard let authorLogin, !authorLogin.isEmpty else { return AuthorName.unknown }
        return authorLogin
    }

    /// 正文值不值得画出来（只点批准、不写话的评审没有正文）。
    public var hasBody: Bool {
        !(body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 那枚「已批准」胶囊（只有 `APPROVED` 的评审有）。
    public var approvalPill: String? {
        guard case let .review(state) = origin else { return nil }
        return state.pillTitle
    }
}

/// PR 的对话（会话评论 + 评审，合成一条按时间升序的流）。
public struct PullConversation: Sendable, Hashable {

    public let items: [PullTimelineItem]

    /// 两个来源里**任一**还有下一页。
    ///
    /// ⚠️ 合并两条流之后没有单一游标可用（两条流各自的 `nextCursor` 不是一回事），
    /// 所以这里只留一个布尔值 —— 本片只取第一页，它的用途是
    /// "界面能知道这不是全部"（同 `BranchList.hasMore` 的口径），
    /// **不用它去翻页**。规格没给"加载更多对话"这个入口，已登记为开放项。
    public let hasMore: Bool

    public init(items: [PullTimelineItem], hasMore: Bool) {
        self.items = items
        self.hasMore = hasMore
    }

    public var count: Int { items.count }
}

/// PR 详情（PRD §4.11、TECH_SPEC §9.9）。
public struct PullDetail: Sendable, Hashable, Identifiable {

    public let number: Int

    public let title: String

    /// 三档（开放 / 已合并 / 已关闭）—— 判据只有 `PullRequestState(state:mergedAt:)` 一处。
    public let state: PullRequestState

    /// 源分支（`head.ref`）。
    ///
    /// ⚠️ 来自 **Fork 的 PR**，它只是 fork 里的分支名、**不带 fork 的 owner**
    /// （同 `PullRow.headRef`）。
    public let headRef: String

    /// 目标分支（`base.ref`）。
    public let baseRef: String

    public let authorLogin: String?

    /// 创建时刻 —— PR 正文那个气泡的时间（`PullDetailDTO.createdAt` 写了理由）。
    public let createdAt: Date?

    /// 最后更新时刻 —— 头部那句 `更新于 {时间}`。
    public let updatedAt: Date?

    public let mergedAt: Date?

    /// 正文（Markdown 源文）。原型把它画成**作者发的第一条评论**。
    public let body: String?

    public let additions: Int
    public let deletions: Int

    /// 改动文件**个数**（不是文件列表那一页的条数 —— 见 `PullCopy.filesHint`）。
    public let changedFiles: Int

    public var id: Int { number }

    public init(
        number: Int,
        title: String,
        state: PullRequestState,
        headRef: String,
        baseRef: String,
        authorLogin: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        mergedAt: Date? = nil,
        body: String? = nil,
        additions: Int,
        deletions: Int,
        changedFiles: Int
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.headRef = headRef
        self.baseRef = baseRef
        self.authorLogin = authorLogin
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mergedAt = mergedAt
        self.body = body
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
    }

    /// 分支流向：`feature/repo-hub → main`。
    public var branchFlow: String {
        PullCopy.branchFlow(head: headRef, base: baseRef)
    }

    /// 增删统计：`+842 −156`。
    public var statsLabel: String {
        PullCopy.statsLabel(additions: additions, deletions: deletions)
    }

    /// 第三个分区条的标题：`文件 +842 −156`。
    public var filesSegmentTitle: String {
        PullCopy.filesSegment(stats: statsLabel)
    }

    /// 显示名（作者为 `nil` ⇒ `AuthorName.unknown`）。
    ///
    /// ⚠️ 与 `PullRow` 不同：列表卡片上没有作者，而详情页的三句状态说明里都有
    /// （`{作者} 请求合并到 …`）⇒ 这里必须给一个兜底名字。
    public var displayAuthor: String {
        guard let authorLogin, !authorLogin.isEmpty else { return AuthorName.unknown }
        return authorLogin
    }

    /// 正文值不值得画成一个气泡（同 `IssueDetail.hasBody`）。
    public var hasBody: Bool {
        !(body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 状态说明（PRD §4.11 那三句）。
    public func headNote(now: Date) -> String {
        switch state {
        case .open:
            PullCopy.openNote(author: displayAuthor, base: baseRef)
        case .merged:
            PullCopy.mergedNote(author: displayAuthor, base: baseRef)
        case .closed:
            PullCopy.closedNote
        }
    }

    /// 头部元信息：`#57 · feature/repo-hub → main · 更新于 2 小时前`。
    public func metaLabel(now: Date) -> String {
        PullCopy.metaLabel(
            number: number,
            branchFlow: branchFlow,
            updatedAt: updatedAt.map { RelativeTime.string(from: $0, now: now) }
        )
    }

    /// 已合并时对话分区顶部那条信息条；未合并 ⇒ `nil`（不渲染）。
    public func mergedBanner(now: Date) -> String? {
        guard state == .merged else { return nil }
        // ⚠️ 拿不到合并时间时**整段去掉**那一截，而不是编一个"刚刚"
        //    （`PullCopy.mergedBanner` 会给出不带时间的那一版）。
        return PullCopy.mergedBanner(
            author: displayAuthor,
            mergedAt: mergedAt.map { RelativeTime.string(from: $0, now: now) },
            base: baseRef
        )
    }

    /// 讨论还能不能评论。
    ///
    /// ⚠️ **已合并 ⇒ 锁上**，与"自己的仓库 / 他人仓库"无关（原型 `08-pr.js:58` 的
    /// `const composer = pr.s==='merged' ? '' : …` 没有别的条件）。
    /// PRD §4.11 表格把这条写在"自己的仓库 + 已合并"那一行，但另外两处（他人仓库的
    /// 已合并 PR）没有第二种说法 ⇒ 取"只要合并了就锁"。
    public var canComment: Bool { state != .merged }

    /// 操作区该是四档里的哪一档（判据只有 `PullOperationAvailability.decide` 一处）。
    ///
    /// 写成 `PullDetail` 上的方法而不是让视图自己拼判据：本页同时有
    /// **操作区**与**评论输入区**两处要看状态（`canComment`），
    /// 判据散开之后总有一处会漏掉 `readOnly` 那一档。
    public func operationAvailability(readOnly: Bool) -> PullOperationAvailability {
        PullOperationAvailability.decide(readOnly: readOnly, state: state)
    }
}

/// PR 详情页首屏的两样：详情与对话（决策 #57 的同一套形状 —— 两次请求可分别失败）。
///
/// ⚠️ **Commits 与文件两个分区不在这里**：原型是按分区渲染的
/// （`prSeg(seg)` 只画当前那一档），而 §9.9 明写文件分区的 diff 要"折叠态按需解析"。
/// 三样都塞进首屏等于打开 PR 就先拉 100 个文件的 diff —— 大 PR 直接卡住。
/// 它们走 `LoadPullDetail.commits` / `.files`，进分区时才取。
public struct PullDetailSnapshot: Sendable {

    public let detail: PullDetail

    /// 对话分区状态（评论 + 评审）。同 `IssueDetailSnapshot.comments`：
    /// 失败降级成 `.failed`，不拖垮头部。
    public let conversation: LoadState<PullConversation>

    public init(detail: PullDetail, conversation: LoadState<PullConversation>) {
        self.detail = detail
        self.conversation = conversation
    }
}

/// PR 详情的接缝 —— 由 `GitHubAPI` 的 `GitHubRepoPullsEndpoint` 空扩展体满足。
///
/// ⚠️ **不含评论的读**：那一份在 `IssueCommentReading`（`GitHubRepoIssuesEndpoint`），
/// `LoadPullDetail` 同时依赖两者。这不是"拆得太碎"，而是数据本来就在两个端点类上：
/// PR 的时间线是 issue 评论（决策 #60 的对照表）。
public protocol PullDetailDataSource: Sendable {

    /// `GET /repos/{o}/{r}/pulls/{n}`。⚠️ `additions` / `deletions` / `changed_files`
    /// **只有这条请求会给**（决策 #58）。
    func pullRequest(owner: String, repo: String, number: Int) async throws -> PullDetailDTO

    /// `GET /repos/{o}/{r}/pulls/{n}/reviews` —— **审批状态在这里**（决策 #60）。
    func pullReviews(
        owner: String,
        repo: String,
        number: Int,
        cursor: URL?
    ) async throws -> Page<PullReviewDTO>

    /// `GET /repos/{o}/{r}/pulls/{n}/files`，分区三。
    func pullFiles(
        owner: String,
        repo: String,
        number: Int,
        cursor: URL?
    ) async throws -> Page<PullFileDTO>

    /// `GET /repos/{o}/{r}/pulls/{n}/commits`，分区二。
    func pullCommits(
        owner: String,
        repo: String,
        number: Int,
        cursor: URL?
    ) async throws -> Page<CommitListItemDTO>
}

/// 让真实端点满足上面的接缝。空扩展体能成立，靠的是**方法签名逐字一致**。
extension GitHubRepoPullsEndpoint: PullDetailDataSource {}

/// 取 PR 详情首屏 + 两个懒加载分区（PRD §4.11、TECH_SPEC §9.9）。
public struct LoadPullDetail: Sendable {

    /// 评论 / 评审 / 文件 / Commits 四页的页大小 —— 取端点上限 100。
    ///
    /// ⚠️ 理由同 `LoadIssueDetail.commentPageSize`：这几样都是**这一屏的内容本身**，
    /// 只取 30 条会让"这个 PR 有 87 个文件"在界面上变成"有 30 个"。
    /// （`PullCopy.filesHint` 用的是 `changedFiles`，那个数不受页大小影响 ——
    /// 两者都对，但说的是不同的事。）
    public static let pageSize = 100

    private let detail: any PullDetailDataSource
    private let comments: any IssueCommentReading

    /// ⚠️ **两个依赖**：详情 / 评审 / 文件 / Commits 在 `GitHubRepoPullsEndpoint`，
    /// 而评论在 `GitHubRepoIssuesEndpoint`（决策 #60 的对照表）。
    /// 生产装配时两者来自同一个 `AppEnvironment`，不是两次装配。
    public init(detail: any PullDetailDataSource, comments: any IssueCommentReading) {
        self.detail = detail
        self.comments = comments
    }

    /// 进页取数：**先详情，再并发取评论与评审**。
    ///
    /// ## 为什么这两条是并发
    ///
    /// 与 `LoadIssueDetail`（先详情后评论、串行）的差别是有意的：
    /// 那边第二次请求是"评论"，一条就够；这里是**两条独立的路**
    /// （`/issues/{n}/comments` 与 `/pulls/{n}/reviews`，不同端点、互不依赖），
    /// 串行会让进页的等待变成两倍 —— 而两次往返都是几百毫秒级。
    ///
    /// ⚠️ 两条都用同一个合并点：**任一条失败都不抛**（折进同一档
    /// `.failed`），因为对话是这一页的**内容**，而头部才是"打不开"的那一半。
    /// 合并成一条 `.failed` 而不是两条各自的状态：界面上那是一条流，
    /// 说"评论加载失败但评审还在"对用户没有任何可操作的含义。
    /// 代价是一次失败会连同另一条的成果一起丢掉 —— 重试按钮会把两条一起重取。
    ///
    /// - Throws: 详情请求的错误（含 `RepositoryMappingError.malformedFullName`）。
    /// ⚠️ **对话的失败不会走到这里**。
    public func load(fullName: String, number: Int) async throws -> PullDetailSnapshot {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let dto = try await detail.pullRequest(owner: owner, repo: repo, number: number)
        let model = Self.detail(from: dto)
        let conversation = await fetchConversation(owner: owner, repo: repo, number: number)
        return PullDetailSnapshot(detail: model, conversation: conversation)
    }

    /// 只重取对话 —— 界面上"对话分区重试"的出口（同 `LoadIssueDetail.comments`）。
    ///
    /// ⚠️ 不抛错：它是**区域内状态**，不是一个会让整页开天窗的错误。
    public func conversation(fullName: String, number: Int) async -> LoadState<PullConversation> {
        guard let (owner, repo) = try? RepositoryMapper.splitFullName(fullName) else {
            // ⚠️ 折进"未归类"那一档而不是 `.notFound`：后者会被说成
            //    "这个 PR 不存在或无权访问"，而真实原因是路由给的 `fullName` 形状不对。
            return .failed(.serverError(status: 0))
        }
        return await fetchConversation(owner: owner, repo: repo, number: number)
    }

    /// 分区二：Commits（进分区时才取）。
    ///
    /// ⚠️ 返回 `Page<CommitSummary>` 而不是自造一个列表类型 ——
    /// `Page` 已经带着 `nextCursor` / `hasMore`，而丢掉游标等于
    /// "还有下一页"在代码里没有任何地方知道（`LoadRepoCommits` 就是这么做的）。
    /// 行的映射也**复用** `RepoCommitMapper.summary`：PR 的提交与仓库的提交是同一份形状，
    /// 各写一遍的下场是两处迟早对不上（"同形必分叉"）。
    public func commits(fullName: String, number: Int) async -> LoadState<Page<CommitSummary>> {
        guard let (owner, repo) = try? RepositoryMapper.splitFullName(fullName) else {
            return .failed(.serverError(status: 0))
        }
        do {
            let page = try await detail.pullCommits(
                owner: owner,
                repo: repo,
                number: number,
                cursor: nil
            )
            return .loaded(
                Page(
                    items: page.items.map(RepoCommitMapper.summary),
                    nextCursor: page.nextCursor,
                    headers: page.headers
                )
            )
        } catch {
            return Self.foldCommits(error)
        }
    }

    /// 分区三：改动文件（进分区时才取）。
    ///
    /// ⚠️ **每个文件的 `patch` 是独立的一份 diff、各自从头编号** ——
    /// 不能把它们接成一份连续 diff 去解析（§9.9 与 §11.2，本片的验证靶心）。
    /// 映射复用 `RepoCommitMapper.detail` 那一套里的同一条规则（`FileChange`），
    /// 这里手写一遍是因为那个函数吃的是 `CommitDetailDTO`（整份提交），
    /// 而这里只有 `files[]` 那一部分 —— 字段映射逐字相同（`filename` / `additions` /
    /// `deletions` / `status` / `patch`），`FileChange` 是**同一个类型**。
    public func files(fullName: String, number: Int) async -> LoadState<Page<FileChange>> {
        guard let (owner, repo) = try? RepositoryMapper.splitFullName(fullName) else {
            return .failed(.serverError(status: 0))
        }
        do {
            let page = try await detail.pullFiles(
                owner: owner,
                repo: repo,
                number: number,
                cursor: nil
            )
            return .loaded(
                Page(
                    items: page.items.map(Self.fileChange(from:)),
                    nextCursor: page.nextCursor,
                    headers: page.headers
                )
            )
        } catch {
            return Self.foldFiles(error)
        }
    }

    // MARK: - 私有

    /// 评论与评审**并发取**，再合成一条时间线。
    private func fetchConversation(
        owner: String,
        repo: String,
        number: Int
    ) async -> LoadState<PullConversation> {
        async let commentPage = comments.issueComments(
            owner: owner,
            repo: repo,
            number: number,
            perPage: Self.pageSize,
            cursor: nil
        )
        async let reviewPage = detail.pullReviews(
            owner: owner,
            repo: repo,
            number: number,
            cursor: nil
        )

        do {
            // ⚠️ `await` 两处都要在 `do` 里面：`async let` 的抛出发生在被 await 的那一刻，
            //    只 await 一个会让另一个的错误在函数退出时才被吞掉/上报。
            let (commentPageResult, reviewPageResult) = try await (commentPage, reviewPage)
            return .loaded(
                Self.conversation(comments: commentPageResult, reviews: reviewPageResult)
            )
        } catch {
            return Self.foldConversation(error)
        }
    }

    /// 把两条流合成一条**按时间升序**的流。
    ///
    /// ## 三条规则
    ///
    /// 1. **`PENDING` 的评审不进来**（`PullReviewState.isPartOfConversation`）——
    ///    那是没提交的草稿，只有作者自己看得到。
    /// 2. **按时间升序**（原型里作者的正文在前、`dev-k` 的评审在后）。
    /// 3. **没有时间的那一条排在最后**：评论不可能没有时间，评审的 `submitted_at`
    ///    才有可能缺失 ⇒ 把它放在末尾是"不确定位置的放最后"，而不是插在中间冒充有序。
    ///
    /// ⚠️ **同刻要稳定**：Swift 的 `sorted(by:)` **不保证稳定**，靠原始下标做平手裁决
    /// 才能保证同一份输入永远得到同一份输出（同 `StarGain.rank` 的做法）。
    /// 评论先于评审入列，于是"同刻的评论在评审前面"是确定的 —— 而不是随机的。
    ///
    /// ⚠️ `hasMore` 取两页的**或**：合并之后没有单一游标可用
    /// （两条流各自的 `nextCursor` 不是一回事），所以只留一个布尔值 ——
    /// 它的用途是"界面能知道这不是全部"，**不是**拿它去翻页。
    static func conversation(
        comments: Page<IssueCommentDTO>,
        reviews: Page<PullReviewDTO>
    ) -> PullConversation {
        var items: [PullTimelineItem] = []

        for comment in comments.items {
            items.append(
                PullTimelineItem(
                    id: "c-\(comment.id)",
                    origin: .comment,
                    authorLogin: comment.user?.login,
                    body: comment.body,
                    createdAt: comment.createdAt
                )
            )
        }

        for review in reviews.items {
            let state = PullReviewState(rawState: review.state)
            guard state.isPartOfConversation else { continue }
            items.append(
                PullTimelineItem(
                    id: "r-\(review.id)",
                    origin: .review(state),
                    authorLogin: review.user?.login,
                    body: review.body,
                    createdAt: review.submittedAt
                )
            )
        }

        let indexed = Array(items.enumerated())
        let sorted = indexed.sorted { lhs, rhs in
            let left = lhs.element.createdAt ?? .distantFuture
            let right = rhs.element.createdAt ?? .distantFuture
            return left == right ? lhs.offset < rhs.offset : left < right
        }

        return PullConversation(
            items: sorted.map(\.element),
            hasMore: comments.hasMore || reviews.hasMore
        )
    }

    private static func foldConversation(_ error: any Error) -> LoadState<PullConversation> {
        // ⚠️ 非 `GitHubError` 的抛出**诚实上抛**为"没归类"那一档，不折成 `.transport`
        //    （那会谎称网络问题、给出"检查网络"的错误引导）。
        .failed((error as? GitHubError) ?? .serverError(status: 0))
    }

    private static func foldCommits(_ error: any Error) -> LoadState<Page<CommitSummary>> {
        .failed((error as? GitHubError) ?? .serverError(status: 0))
    }

    private static func foldFiles(_ error: any Error) -> LoadState<Page<FileChange>> {
        .failed((error as? GitHubError) ?? .serverError(status: 0))
    }

    private static func detail(from dto: PullDetailDTO) -> PullDetail {
        PullDetail(
            number: dto.number,
            title: dto.title,
            // ⚠️ 三档判定只有 `PullRequestState(state:mergedAt:)` 一处 ——
            //    自己写 `state == "closed" && mergedAt != nil` 的下场是
            //    总有一处漏掉 `mergedAt` 那一半（见那个初始化器的说明）。
            state: PullRequestState(state: dto.state, mergedAt: dto.mergedAt),
            headRef: dto.head.ref,
            baseRef: dto.base.ref,
            authorLogin: dto.user?.login,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            mergedAt: dto.mergedAt,
            body: dto.body,
            additions: dto.additions,
            deletions: dto.deletions,
            changedFiles: dto.changedFiles
        )
    }

    private static func fileChange(from dto: PullFileDTO) -> FileChange {
        FileChange(
            filename: dto.filename,
            additions: dto.additions,
            deletions: dto.deletions,
            status: FileChange.Status(rawStatus: dto.status),
            patch: dto.patch
        )
    }
}
