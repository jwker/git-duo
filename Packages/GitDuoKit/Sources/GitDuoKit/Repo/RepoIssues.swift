// Issue 列表的领域层：行模型 · 说明行文案 · 取数用例。
//
// ⚠️ 本文件切片 7 起**从 `Explore/` 移到了 `Repo/`**（决策 #61）：它服务两个页面 ——
// 探索 Issues 列表（§4.14）与仓库详情 Issues 段（§4.4 分区二）。
// 留在 `Explore/` 会让"这是探索页专属"变成一个**目录名说的谎**，
// 而下一个要动它的人会先相信目录名。
// ⚠️ 移动是纯整理（同一个 Swift 模块，路径不进编译单元）—— 没有一行行为因它改变。

import Foundation
import GitHubAPI
import GitDuoCore

/// 探索 Issues 列表的一行（PRD §4.14、TECH_SPEC §4.6.2、决策 #38）。
///
/// ## 状态为什么用 `isOpen` 而不是 `String`
///
/// `IssueDTO.state` 是 `String`（见它的类型说明：GitHub 还在演进 `state_reason`，
/// 枚举化一个仍在变的取值集合会让"某天多一个取值"表现为整页解码失败）。
/// 但**到了领域层**，这个列表的场景是确定的：只有"开放"与"已关闭"两档
/// ⇒ 一个布尔值就是全部所需。多留一个 `String` 只会让视图有机会去 `== "closed"` 地猜。
public struct IssueRow: Sendable, Hashable, Identifiable {

    /// 仓库内唯一编号 —— 卡片上的 `#42`，也是跳详情页的键。
    public let number: Int

    public let title: String

    /// 是否开放。
    ///
    /// ⚠️ 探索 Issues 列表里**只会是 `true`**（决策 #38：那一页只取 `.open`）；
    /// 而仓库详情 Issues 段的「已关闭」档（决策 #61）会取到 `false` ——
    /// 同一个行模型服务两处，值由**请求的那一档**决定。
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

    /// `GET /repos/{owner}/{repo}/issues?state=…&labels=…` 的一页。
    ///
    /// ⚠️ **返回里混着 PR**（GitHub 把 PR 当作一种 Issue），过滤是**领域层的活**
    /// （见 `LoadRepoIssues`）—— 数据层原样返回，才能让"这一页 30 条里怎么只有 9 条"
    /// 这个问题有据可查。
    ///
    /// ⚠️ 参数用 `String` 而**不是**领域层的 `RepoListState`，这是接缝的硬约束：
    /// 本协议由 `GitDuoKit` 声明、由 `GitHubAPI` 的 `GitHubRepoIssuesEndpoint`
    /// **空扩展体**满足（那边看不见领域层的类型 —— 依赖是单向的）。
    /// 词汇转换在 `LoadRepoIssues` 里做一次，别在两处各转一遍。
    /// 服务端取值：`open` / `closed` / `all`。
    ///
    /// ⚠️ `labels` 为空数组 ⇒ 数据层**不带**该参数（不筛）；
    /// 非空 ⇒ 逗号分隔、服务端按 **AND** 语义（要同时带上这些标签）。
    func issues(
        owner: String,
        repo: String,
        state: String,
        labels: [String],
        cursor: URL?
    ) async throws -> Page<IssueDTO>
}

/// 让真实端点满足上面的接缝（协议是我们自己声明的，不是追溯适配）。
///
/// ⚠️ **空扩展体能成立，靠的是方法签名逐字一致** —— 数据层那边改了名字或参数顺序，
/// 这里不会报"少实现一个方法"（那会），但如果两边"看起来都实现了"却对不上，
/// 编译器只会在别处抛一句难懂的错。签名对齐是这套接缝唯一的纪律。
extension GitHubRepoIssuesEndpoint: RepoIssuesDataSource {}

/// 取 Issues 列表的一页（PRD §4.14 / §4.4 分区二、TECH_SPEC §9.8、决策 #38 / #56 / #61）。
///
/// ## 它同时服务两个页面（决策 #61）
///
/// | 调用方 | `state` | `labels` |
/// |---|---|---|
/// | 探索 Issues 列表（§4.14） | `.open` | 不筛 |
/// | 仓库详情 Issues 段（§4.4 分区二） | `.open` / `.closed` | 可有（标签筛选） |
///
/// 两处的**取数规则完全相同**（滤掉混进来的 PR），差别只在"向服务端要哪一批" ⇒
/// 用一个用例 + 参数表达，而不是复制一份。
public struct LoadRepoIssues: Sendable {

    private let source: any RepoIssuesDataSource

    public init(source: any RepoIssuesDataSource) {
        self.source = source
    }

    /// - Parameters:
    ///   - state: 向服务端要哪一档。**没有默认值** —— 四个调用方的意图各不相同，
    ///     给默认值等于让"忘了传"静默地选错一批数据，而结果看起来完全正常。
    ///   - labels: 标签筛选（**走服务端**，决策 #56）。空数组 ⇒ 不筛。
    ///   - cursor: 上一页的 `nextCursor`；`nil` 取第一页。
    /// - Returns: **已滤掉 PR** 的一页。
    ///
    /// ## 为什么过滤放在这一层（而不是数据层或视图层）
    ///
    /// - **不能放数据层**：那样"哪些算 Issue"这条产品口径就沉进了 `GitHubAPI`。
    /// - **不能放视图层**：视图拿到的条目会被分页状态机计数，而
    ///   `{N}` 的语义正是"已加载的**非 PR** 条目数"（决策 #38）——
    ///   过滤晚一步，计数就把 PR 也算进去了，而那个数会与屏幕上看到的条数对不上。
    ///
    /// ⚠️ **分页步长因此不是"每页 30 个 Issue"**：一页 30 条里可能只有 9 个 Issue。
    /// 这不是 bug，是 `GET /issues` 的固有行为 —— 也正因如此，
    /// 用完一页不代表"看完了 30 个 Issue"，`hasMore` 必须原样带走。
    ///
    /// ⚠️ **标签筛选也走服务端**（决策 #56）—— 不做本地过滤：
    /// 本地只能筛**已加载的那一页**（30 条，其中还混着 PR），结果显著偏少，
    /// 而说明行的计数会与"实际有多少"对不上（决策 #38 被否掉的是同一个形状）。
    public func load(
        fullName: String,
        state: RepoListState,
        labels: [String] = [],
        cursor: URL? = nil
    ) async throws -> Page<IssueRow> {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let page = try await source.issues(
            owner: owner,
            repo: repo,
            state: state.rawValue,
            labels: labels,
            cursor: cursor
        )

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
            // ⚠️ 读一次 `state` 而不是按"我们请求的是 open"写死 `true`：
            // 现在这个用例已经能取 `.closed` 了（决策 #61），写死的那一处会
            // 静默把已关闭的 Issue 说成"开放"。
            isOpen: dto.state == "open",
            comments: dto.comments,
            // 用 `created_at` 而不是 `updated_at`：卡片文案说的是"创建"。
            createdAt: dto.createdAt,
            authorLogin: dto.user?.login
        )
    }
}
