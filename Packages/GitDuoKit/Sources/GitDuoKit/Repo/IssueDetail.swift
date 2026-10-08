import Foundation
import GitHubAPI
import GitDuoCore

/// Issue 详情（PRD §4.9、TECH_SPEC §9.8、决策 #57 / #62）。
///
/// ## 它与 `IssueRow` 是两个类型
///
/// `IssueRow` 回答"列表里那一行画什么"（标题 / 状态 / 评论数 / 创建时间）。
/// 本类型回答"这个 Issue 是什么"（正文 / 关闭时间 / 作者）。
/// 合成一个的下场与 `IssueDTO` / `IssueDetailDTO` 那条一样：
/// "列表里怎么没有正文"会变成每次都要回忆一遍的事。
///
/// ## ⚠️ 没有 `PATCH`、没有"关闭 / 重新打开"
///
/// 决策 #62：PRD §4.9 与原型 `06-files.js:113` 的 `SCR.issueDetail` 都**只有评论**，
/// 没有维护者操作入口。`PATCH …/issues/{n}` 虽然在 `§4.6.2` 的端点清单里，
/// 但那只是清单、不等于产品范围 ⇒ 本期不做，**不是遗漏**。
public struct IssueDetail: Sendable, Hashable, Identifiable {

    /// 仓库内编号 —— 头部那句 `#42`，也是路由的键。
    public let number: Int

    public let title: String

    /// 是否开放。判定与 `IssueRow.isOpen` 同源（读原始 `state`，不按"我们请求的那一档"写死）。
    public let isOpen: Bool

    /// 正文（Markdown 源文）。
    ///
    /// ⚠️ **可以是 `nil` 也可以是空串**，但两者在界面上是**同一种样子**（都不气泡）——
    /// 要不要出气泡走 `hasBody`，别在视图里各判一次。
    public let body: String?

    /// 创建者。**可以是 `nil`**（账号已删除）。
    ///
    /// 作者为 `nil` 时头部**整段去掉**（`IssueCopy.metaLabel`）。
    public let authorLogin: String?

    public let createdAt: Date

    /// 关闭时刻。**可以是 `nil`** —— 仍然开放时是它；已关闭也可能缺失
    /// （官方 schema 里 nullable）⇒ 那种情况下只说"已关闭"、不编时间。
    public let closedAt: Date?

    public var id: Int { number }

    public init(
        number: Int,
        title: String,
        isOpen: Bool,
        body: String? = nil,
        authorLogin: String? = nil,
        createdAt: Date,
        closedAt: Date? = nil
    ) {
        self.number = number
        self.title = title
        self.isOpen = isOpen
        self.body = body
        self.authorLogin = authorLogin
        self.createdAt = createdAt
        self.closedAt = closedAt
    }

    /// 读屏用的状态词 —— 与 `RepoListState` / `PullRequestState.label` 同一套词。
    public var stateLabel: String { isOpen ? "开放" : "已关闭" }

    /// 正文值不值得画成一条气泡。
    ///
    /// ## 为什么这条规则在领域层
    ///
    /// 原型把正文画成**作者发的第一条评论**（`06-files.js:122-128` 那条 `.comment`
    /// 就是 `reviewer-a` 的正文）。所以"要不要出气泡"不是排版选择，
    /// 而是"这个 Issue 有没有正文"这条产品判断。
    ///
    /// ⚠️ 判据是**去掉空白之后非空**：一个只写了换行的正文在用户眼里就是没写，
    /// 而为它画一个空气泡看起来像加载失败。`body == nil` 与 `body == ""`
    /// 在这里**同一种处理** —— 它们在服务端是两种写法，在屏幕上是一件事。
    public var hasBody: Bool {
        !(body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 状态说明：`该 Issue 仍然开放` / `已于 2 天前关闭`。
    ///
    /// - Parameter now: 现时（相对时间的基准）。**必传** —— 让它有默认值
    ///   等于在视图里悄悄引入第二个时间源，而"相对时间每次重绘都在变"这件事
    ///   必须只有一个入口（同 `IssueRow.metaLabel(now:)`）。
    public func headNote(now: Date) -> String {
        guard !isOpen else { return IssueCopy.openNote }
        guard let closedAt else { return IssueCopy.closedNoteWithoutTime }
        return IssueCopy.closedNote(relativeTime: RelativeTime.string(from: closedAt, now: now))
    }

    /// 头部元信息行：`#42 · my-git/gitduo · 由 reviewer-a 创建于 2 小时前`。
    public func metaLabel(fullName: String, now: Date) -> String {
        IssueCopy.metaLabel(
            number: number,
            fullName: fullName,
            authorLogin: authorLogin,
            relativeTime: RelativeTime.string(from: createdAt, now: now)
        )
    }
}

/// Issue 详情页首屏的两样：正文与讨论。
///
/// ## 为什么 `comments` 是 `LoadState` 而不是 `[IssueComment]`
///
/// 这是**决策 #57 的全部要点**：详情是两次请求（`GET /issues/{n}` +
/// `GET /issues/{n}/comments`），两次**可分别失败、分别重试** ——
/// 评论拉失败不该让正文也消失。
///
/// 所以两条数据的失败后果不同：
///
/// | 请求 | 失败 |
/// |---|---|
/// | 详情 | 整页失败 + 一个重试出口（`load` 抛错） |
/// | 评论 | **降级**：正文与头部照常显示，评论区自带一个重试（`comments` 是 `.failed`） |
///
/// 同 `RepoDetailSnapshot` 对 Star 基准的处理：**不把可降级的那半并进不可降级的那半的错误**。
///
/// ## 为什么评论用 `Page<IssueComment>` 而不是自造一个"讨论"类型
///
/// 因为评论**本来就是分页的**（`LoadIssueDetail.commentPageSize = 100`），
/// 而 `Page` 已经带着 `nextCursor` / `hasMore` 两样东西 ——
/// 一页装不下时"还没取完"这件事必须有地方存（同 `BranchList.hasMore` 的口径）。
/// `LoadRepoCommits` 也是这么做的（返回 `Page<CommitSummary>`），这里不另立一套。
public struct IssueDetailSnapshot: Sendable {

    public let detail: IssueDetail

    /// 评论区状态。详情成功返回时它**不会是 `.idle` / `.loading`**
    /// —— 已经取过了，只可能是 `.loaded` 或 `.failed`。
    public let comments: LoadState<Page<IssueComment>>

    public init(detail: IssueDetail, comments: LoadState<Page<IssueComment>>) {
        self.detail = detail
        self.comments = comments
    }
}

/// Issue 详情 + 评论的接缝（切片 7 起 `GitHubRepoIssuesEndpoint` 的一部分）。
///
/// ## 它**继承** `IssueCommentReading`
///
/// 因为详情页确实要读评论（`LoadIssueDetail` 两次请求里的第二次），
/// 而评论的读还有第二个消费者（PR 详情的对话分区）⇒
/// 读评论那一条单独声明在 `IssueComment.swift`，这里继承过来。
/// 好处是 `LoadPullDetail` 只需 `any IssueCommentReading`，
/// 不必为了读评论而带上一个它用不到的 `issue(...)`。
///
/// ⚠️ 为什么与 `RepoIssuesDataSource` 分开：见 `IssueCommentPosting` 的说明
/// （一个端点服务三屏之后，宽协议会让每个用例的测试替身替别的屏写桩）。
public protocol IssueDetailDataSource: IssueCommentReading {

    /// `GET /repos/{o}/{r}/issues/{n}`。
    func issue(owner: String, repo: String, number: Int) async throws -> IssueDetailDTO
}

/// 让真实端点满足上面的接缝。空扩展体能成立，靠的是**方法签名逐字一致**。
extension GitHubRepoIssuesEndpoint: IssueDetailDataSource {}

/// 取 Issue 详情的首屏（PRD §4.9、TECH_SPEC §9.8、决策 #57）。
public struct LoadIssueDetail: Sendable {

    /// 评论一页的大小 —— 取端点的上限 100。
    ///
    /// ⚠️ **不是其余列表的 30**：讨论是"这一页的内容本身"，
    /// 只取 30 条会让"点进来只看到一半讨论"变成一件屏幕上完全看不出来的事。
    /// （这是数据层 `issueComments(perPage:)` 的默认值，这里显式再写一次 ——
    /// 领域层不该依赖数据层的默认值，那是两个包之间的隐形契约。）
    public static let commentPageSize = 100

    private let source: any IssueDetailDataSource

    public init(source: any IssueDetailDataSource) {
        self.source = source
    }

    /// 进页取数：**先详情、后评论**。
    ///
    /// ## 为什么是串行而不是并发
    ///
    /// 两次请求确实互不依赖，但**串行的代价是一次往返**，而并发换来的那点时间
    /// 在两个都很快的调用上量不出来。反过来，串行有一个实在的好处：
    /// 详情失败时**一次请求都没多花**（详情 404 的 Issue 根本不需要去拉评论）。
    /// 这与 `LoadRepoDetail` 串行取 Star 基准是同一个取舍。
    ///
    /// - Throws: 详情请求的任何错误（`RepositoryMappingError.malformedFullName`、
    ///   `GitHubError.notFound` 等）。⚠️ **评论的失败不会走到这里**。
    public func load(fullName: String, number: Int) async throws -> IssueDetailSnapshot {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let dto = try await source.issue(owner: owner, repo: repo, number: number)
        let detail = Self.detail(from: dto)
        let comments = await fetchComments(owner: owner, repo: repo, number: number)
        return IssueDetailSnapshot(detail: detail, comments: comments)
    }

    /// 只重取评论 —— **决策 #57「分别重试」的那个出口**。
    ///
    /// 评论区失败后界面上的重试按钮走这里：它不重新拉详情（那份数据就在手边、
    /// 而且重新拉会让整页闪一次骨架屏）。同 `ToggleStar` 的存在理由 ——
    /// 把"用户能重试的粒度"与"实际发几个请求"对齐。
    ///
    /// ⚠️ **不抛错**，失败折进 `LoadState.failed`：它是"界面上的一块区域的状态"，
    /// 不是一个会让整页开天窗的错误。这与 `load` 抛错的差别正是本页两条数据
    /// 失败后果不同的体现。
    public func comments(fullName: String, number: Int) async -> LoadState<Page<IssueComment>> {
        guard let (owner, repo) = try? RepositoryMapper.splitFullName(fullName) else {
            // ⚠️ 折进"未归类"那一档而**不是** `.notFound`：后者会被界面说成
            // "这个 Issue 不存在或无权访问"，而真实原因是路由给来的 `fullName` 形状不对
            // —— 那是客户端自己的 bug，说成"不存在"会把排查引向错误的方向。
            return .failed(.serverError(status: 0))
        }
        return await fetchComments(owner: owner, repo: repo, number: number)
    }

    // MARK: - 私有

    private func fetchComments(
        owner: String,
        repo: String,
        number: Int
    ) async -> LoadState<Page<IssueComment>> {
        do {
            let page = try await source.issueComments(
                owner: owner,
                repo: repo,
                number: number,
                perPage: Self.commentPageSize,
                cursor: nil
            )
            // ⚠️ `nextCursor` / `headers` 原样带走：丢掉游标就等于
            //    "还有下一页"这件事在代码里没有任何地方知道（同 `LoadRepoIssues`）。
            return .loaded(
                Page(
                    items: page.items.map(Self.comment(from:)),
                    nextCursor: page.nextCursor,
                    headers: page.headers
                )
            )
        } catch let error as GitHubError {
            return .failed(error)
        } catch {
            // 非 `GitHubError` 的抛出**诚实上抛**为"没归类"那一档，
            // 不折成 `.transport`（那会谎称是网络问题，给用户"检查网络"的错误引导 ——
            // 同决策 #33 对令牌出口的要求）。
            return .failed(.serverError(status: 0))
        }
    }

    private static func detail(from dto: IssueDetailDTO) -> IssueDetail {
        IssueDetail(
            number: dto.number,
            title: dto.title,
            // ⚠️ 读 `state` 而不是写死 `true`：同一个端点也会返回已关闭的 Issue。
            isOpen: dto.state == "open",
            body: dto.body,
            authorLogin: dto.user?.login,
            createdAt: dto.createdAt,
            closedAt: dto.closedAt
        )
    }

    private static func comment(from dto: IssueCommentDTO) -> IssueComment {
        IssueComment(
            id: dto.id,
            body: dto.body,
            authorLogin: dto.user?.login,
            createdAt: dto.createdAt
        )
    }
}
