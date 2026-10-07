import Foundation
import GitHubAPI
import GitDuoCore

/// 探索 Issues 列表的一行（PRD §4.14、TECH_SPEC §4.6.2、决策 #38）。
///
/// ## 状态为什么用 `isOpen` 而不是 `String`
///
/// `IssueDTO.state` 是 `String`（见它的类型说明：GitHub 还在演进 `state_reason`，
/// 枚举化一个仍在变的取值集合会让"某天多一个取值"表现为整页解码失败）。
/// 但**到了领域层**，这个列表的场景是确定的：本列表只列开放式（决策 #38）
/// ⇒ `isOpen` 就是全部所需。多留一个 `String` 只会让视图有机会去 `== "closed"` 地猜。
public struct IssueRow: Sendable, Hashable, Identifiable {

    /// 仓库内唯一编号 —— 卡片上的 `#42`，也是跳详情页的键。
    public let number: Int

    public let title: String

    /// 是否开放。⚠️ 探索 Issues 列表**只会有 `true`**（决策 #38）；
    /// 保留这个字段是为了让卡片组件能被「我的仓库」四分区（切片 7）直接复用。
    public let isOpen: Bool

    /// 评论条数（本列表的说明行**不显示它**，但卡片上显示 `3 条评论`）。
    public let comments: Int

    /// 创建时刻（卡片上的 `由 {作者} 创建` 对应的时间）。
    public let createdAt: Date

    /// 作者登录名。**可以是 `nil`** —— 账号被删除后 GitHub 把整段 `user` 置为 `null`。
    public let authorLogin: String?

    /// 去重与 `ForEach` 的键（仓库内编号唯一）。
    public var id: Int { number }

    public init(
        number: Int,
        title: String,
        isOpen: Bool,
        comments: Int,
        createdAt: Date,
        authorLogin: String? = nil
    ) {
        self.number = number
        self.title = title
        self.isOpen = isOpen
        self.comments = comments
        self.createdAt = createdAt
        self.authorLogin = authorLogin
    }

    /// 卡片副标题：`#42 · 2 小时前 · 3 条评论 · 由 reviewer-a 创建`。
    ///
    /// 逐字对齐原型（`10-explore-repo.js:124` 的 `#${i.n} · ${i.d} · 由 ${i.u} 创建`，
    /// 其中 `i.d` 是 `'2 小时前 · 3 条评论'` 这样一个**已拼好的串**）。
    /// 两处与原型不同，都是"遇到原型没覆盖的情形时不要编"：
    /// - **0 条评论不写那一段**（原型的数据里 0 评论就只写时间），
    /// - **作者为 `nil` 时整段去掉** —— 原型那处会拼出 `由 undefined 创建`。
    public func metaLabel(now: Date) -> String {
        var parts = ["#\(number)", RelativeTime.string(from: createdAt, now: now)]
        if comments > 0 { parts.append("\(comments) 条评论") }
        if let authorLogin, !authorLogin.isEmpty { parts.append("由 \(authorLogin) 创建") }
        return parts.joined(separator: " · ")
    }

    /// 读屏用的状态词（图标本身不能只靠形状传达状态）。
    public var stateLabel: String { isOpen ? "开放" : "已关闭" }
}

/// 探索 Issues 列表的说明行与页脚文案（PRD §4.14、决策 #38）。
///
/// 放在领域层是因为**计数口径本身就是一条业务规则**（`{N}` 是"已加载的非 PR 条目数"，
/// 还有下一页时才加 `+`），而不是排版选择。散进视图就没人守得住。
public enum OpenIssueIndicator {

    /// 列表标题下的说明行：`{仓库} · 开放 {N} 个`。
    ///
    /// ⚠️ 原型这句后面还缀着 `· 只读演示数据` —— 那是原型的**演示标记**，不是产品文案，
    /// 不照抄（PRD §4.14 的说明行也没有它）。
    public static func summaryLine(fullName: String, loadedCount: Int, hasMore: Bool) -> String {
        "\(fullName) · 开放 \(countLabel(loadedCount: loadedCount, hasMore: hasMore)) 个"
    }

    /// 计数值本身：还有下一页时是 **`30+`**（下界，不是确数）。
    ///
    /// ## 为什么不用接口里那个"开放 Issue 数"
    ///
    /// `open_issues_count` **把 PR 也算作 Issue**（官方文档明确）⇒ 它会比屏幕上
    /// 实际看到的条数多，而"数字对不上"会被读成"这个 App 数不准"。
    /// 所以取值是**屏幕上真实的、已加载的非 PR 条目数** —— 零额外请求，且逐条对得上
    /// （2026-10-06 用户拍板，`RepositoryDetailDTO` 里为此**有意不解码**那个字段）。
    public static func countLabel(loadedCount: Int, hasMore: Bool) -> String {
        "\(max(0, loadedCount))\(hasMore ? "+" : "")"
    }

    /// 页脚（PRD §4.14 结构一行）。
    ///
    /// ⚠️ **空态时不渲染它**（2026-10-07 拍板）：页脚讲的是"能对这个列表做什么"，
    /// 而列表为空时它无所指。判据在视图侧（`rows.isEmpty`），本常量只给文案。
    public static let footer = "他人仓库：可评论参与讨论，关闭 Issue 需维护者权限"

    /// 空态标题（PRD §4.14「空态」段 · §7）。
    public static let emptyTitle = "暂无开放的 Issue"

    /// 空态引导行（PRD §4.14「空态」段 · §7）。
    ///
    /// ⚠️ 与说明行说的**不是同一件事**：说明行是计数结论（`开放 0 个`），
    /// 这一句是状态本身。所以空态时**两行都要在**，不能只留一个。
    public static let emptyHint = "这个仓库当前没有开放中的 Issue"
}

/// Issue 列表的数据来源 —— 领域层与网络层之间的接缝。
public protocol RepoIssuesDataSource: Sendable {

    /// `GET /repos/{owner}/{repo}/issues?state=open` 的一页。
    ///
    /// ⚠️ **返回里混着 PR**（GitHub 把 PR 当作一种 Issue），过滤是**领域层的活**
    /// （见 `LoadRepoIssues`）—— 数据层原样返回，才能让"这一页 30 条里怎么只有 9 条"
    /// 这个问题有据可查。
    func openIssues(owner: String, repo: String, cursor: URL?) async throws -> Page<IssueDTO>
}

/// 让真实端点满足上面的接缝（协议是我们自己声明的，不是追溯适配）。
extension GitHubRepoIssuesEndpoint: RepoIssuesDataSource {}

/// 取探索 Issues 列表的一页（PRD §4.14、TECH_SPEC §4.6.2、决策 #38）。
public struct LoadRepoIssues: Sendable {

    private let source: any RepoIssuesDataSource

    public init(source: any RepoIssuesDataSource) {
        self.source = source
    }

    /// - Parameter cursor: 上一页的 `nextCursor`；`nil` 取第一页。
    /// - Returns: **已滤掉 PR** 的一页。
    ///
    /// ## 为什么过滤放在这一层（而不是数据层或视图层）
    ///
    /// - **不能放数据层**：那样"哪些算 Issue"这条产品口径就沉进了 `GitHubAPI`，
    ///   而它下次还可能变（切片 7 的「我的仓库」要显示已关闭的）。
    /// - **不能放视图层**：视图拿到的条目会被 `PagedListState` 计数，而
    ///   `{N}` 的语义正是"已加载的**非 PR** 条目数"（决策 #38）——
    ///   过滤晚一步，计数就把 PR 也算进去了，而那个数会与屏幕上看到的条数对不上。
    ///
    /// ⚠️ **分页步长因此不是"每页 30 个 Issue"**：一页 30 条里可能只有 9 个 Issue。
    /// 这不是 bug，是 `GET /issues` 的固有行为 —— 也正因如此，
    /// 用完一页不代表"看完了 30 个 Issue"，`hasMore` 必须原样带走。
    public func load(fullName: String, cursor: URL? = nil) async throws -> Page<IssueRow> {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let page = try await source.openIssues(owner: owner, repo: repo, cursor: cursor)

        return Page(
            items: page.items.filter { !$0.isPullRequest }.map(Self.row(from:)),
            // 游标与响应头原样带走：`nextCursor` 是服务端给的续页地址（§4.4），
            // 丢掉它就等于让"加载更多"永远拿不到下一页。
            nextCursor: page.nextCursor,
            headers: page.headers
        )
    }

    private static func row(from dto: IssueDTO) -> IssueRow {
        IssueRow(
            number: dto.number,
            title: dto.title,
            // 本端点只取 `state=open`（决策 #38），所以这里是 `true`；
            // 仍然读一次而不是写死 `true` —— 将来加了 `state=all` 的参数时，
            // 写死的那一处会静默把所有条目说成"开放"。
            isOpen: dto.state == "open",
            comments: dto.comments,
            // 用 `created_at` 而不是 `updated_at`：卡片文案说的是"创建"。
            createdAt: dto.createdAt,
            authorLogin: dto.user?.login
        )
    }
}
