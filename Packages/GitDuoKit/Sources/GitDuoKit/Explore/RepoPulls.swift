import Foundation
import GitHubAPI

/// PR 的三种展示状态（PRD §4.15、TECH_SPEC §4.6.2）。
///
/// ## ⚠️ `merged` 是**算出来的**，GitHub 没有这个状态
///
/// `PullRequestDTO.state` 只有 `open` / `closed` 两个取值：**合并**与"关闭但没合并"
/// 在它上面长得一模一样。区分只能靠 `merged_at`（`state == "closed" && merged_at != nil`）。
///
/// 那条规则有**两个写法**，各自待在自己能待的那一层：DTO 上是 `PullRequestDTO.isMerged`
/// （GitHubAPI 看不见本枚举 —— 依赖单向），领域层是这个枚举的
/// `init(state:mergedAt:)`（见下面的扩展）。调用方**不许**自己写那个布尔表达式：
/// 各写一次的下场是**总有一处漏掉 `merged_at` 那一半**，于是所有被关闭的 PR
/// 都显示成"已合并"，而这看起来完全正常。
public enum PullRequestState: String, Sendable, Hashable {

    /// 开放中。
    case open

    /// 已合并（`closed` + 有合并时间）。
    case merged

    /// 已关闭但**未**合并。
    case closed

    /// 读屏用的状态词。
    public var label: String {
        switch self {
        case .open: "开放"
        case .merged: "已合并"
        case .closed: "已关闭"
        }
    }

    /// 状态**胶囊**上的可见状态词（切片 5.4 新增）。
    ///
    /// ## ⚠️ 它是英文的，而 `label` 是中文的 —— 这不是笔误
    ///
    /// 原型 `scripts/02-icons.js` 的 `pillOf` 逐字如此：
    /// ```js
    /// const pillOf = s => ({
    ///   'open':'<span class="pill open">● Open</span>',
    ///   'closed-i':'<span class="pill closed-i">● Closed</span>',
    ///   'closed-p':'<span class="pill closed-p">● Closed</span>',
    ///   'merged':'<span class="pill merged">⇿ Merged</span>',
    /// }[s] || '');
    /// ```
    /// 按 `AGENTS.md §1`（原型是文案的最终裁决者）照抄，**不自行译成中文**。
    /// 两处用不同的词是有分工的：`label` 给读屏（中文、与页脚文案一套词），
    /// 这一句是**画在屏幕上的字**。
    ///
    /// ⚠️ 原型那串里还有一个前置字形（`●` / `⇿`）。**有意不带**：
    /// 它是一个"状态点"，而颜色信息已经由胶囊的前景 / 底 / 边三处表达了
    /// （见 `StatusPill`）；把它混进文案会让读屏念出一个多余的符号，
    /// 也会让切片 7 的详情页复用时拿不到一个干净的状态词。已登记为已知偏差。
    public var pillTitle: String {
        switch self {
        case .open: "Open"
        case .merged: "Merged"
        case .closed: "Closed"
        }
    }
}

extension PullRequestState {

    /// 由「原始 `state` + `merged_at`」判定（切片 5 的搜索结果行与 PR 列表共用）。
    ///
    /// ## 为什么这里又出现一次那条规则
    ///
    /// `PullRequestDTO.isMerged` 是**DTO 层的事实**（GitHubAPI 看不见本枚举 ——
    /// 依赖是单向的，数据层不得引用领域层）；本初始化器是**领域层的判定**，
    /// 供所有"手上只有原始 `state` 与 `mergedAt`"的调用方共用
    /// （`PullRequestDTO`、`SearchConversationDTO` 各是其一）。
    ///
    /// ⚠️ 两者**是同一条规则的两种写法**，改规则必须同时改 —— `PullRequestDTO.isMerged`
    /// 的注释里写明了它的镜像在这里。之所以仍然这么分：让调用方各写一遍
    /// `state == "closed" && mergedAt != nil` 的下场是**总有一处漏掉 `mergedAt` 那一半**，
    /// 于是所有被关闭的 PR 都显示成"已合并"，而这看起来完全正常。
    ///
    /// ## 三档的判据
    ///
    /// - `closed` + 有 `mergedAt` ⇒ `.merged`
    /// - `open` ⇒ `.open`
    /// - 其余（`closed` 但没有 `mergedAt`）⇒ `.closed`
    ///
    /// ⚠️ Issue 也走这里：它没有 `mergedAt`，于是只会取到 `.open` / `.closed`
    /// —— 与"Issue 没有已合并"这件事天然一致。
    public init(state: String, mergedAt: Date?) {
        if state == "closed", mergedAt != nil {
            self = .merged
        } else if state == "open" {
            self = .open
        } else {
            self = .closed
        }
    }
}

/// 探索 PR 列表的一行（PRD §4.15、决策 #39）。
///
/// ## 与 `IssueRow` 的两处有意不对称
///
/// | | `IssueRow` | `PullRow` |
/// |---|---|---|
/// | 作者 | 有（卡片上写 `由 {作者} 创建`） | **没有**（原型卡片上没有作者） |
/// | 状态 | 只有开放（决策 #38） | 开放 + 已合并（决策 #39） |
///
/// 第一处是照原型（PRD §4.15 的卡片内容只有 `#N · {head} → {base}`）；
/// 第二处是产品口径 —— PR 的「已合并」是一个**有价值的结局**，
/// 而 Issue 的「已关闭」只说明没人做了（决策 #39 的完整理由见 PRD §4.15）。
///
/// ⚠️ **不取 `+842 −156`（改动行数）**：`additions` / `deletions` 只在**单个 PR** 端点
/// （`GET /pulls/{n}`）返回，列表端点**不返回** —— 这是 GitHub 的设计，不是遗漏
/// （`PullRequestDTO` 的类型说明写明了）。
public struct PullRow: Sendable, Hashable, Identifiable {

    public let number: Int
    public let title: String
    public let state: PullRequestState

    /// 源分支名（`head.ref`）。
    ///
    /// ⚠️ 来自 **Fork 的 PR**，它只是 fork 里的分支名、**不带 fork 的 owner** ——
    /// 所以看到 `main → main` 并不意味"自己合并自己"。
    public let headRef: String

    /// 目标分支名（`base.ref`）。
    public let baseRef: String

    public var id: Int { number }

    public init(
        number: Int,
        title: String,
        state: PullRequestState,
        headRef: String,
        baseRef: String
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.headRef = headRef
        self.baseRef = baseRef
    }

    /// 卡片副标题：`#57 · feature/repo-hub → main`
    /// （逐字对齐原型 `10-explore-repo.js:139` 的 `#${pr.n} · ${pr.b}`）。
    public var metaLabel: String {
        "#\(number) · \(headRef) → \(baseRef)"
    }
}

/// 探索 PR 列表的说明行与页脚（PRD §4.15）。
///
/// ⚠️ 说明行**只有仓库全名**，没有任何计数 —— 与 Issues 列表有意不同：
/// 本列表按 `state=all` 取（开放 + 已合并 + 已关闭），没有一个"一句话说得清"的数
/// （说"共 N 个 PR"会把已关闭的也算进去，而用户看不到那些的意义）。
/// 原型那句后面缀的 `· 只读演示数据` 是演示标记，不照抄。
public enum PullListIndicator {

    /// 列表标题下的说明行：**只有仓库全名**（PRD §4.15 结构一行）。
    ///
    /// 写成函数而不是让视图直接 `Text(fullName)`：本列表的说明行**刻意不含任何计数**
    /// （理由见类型说明），而"刻意不写某个东西"这件事只有收在一处才守得住 ——
    /// 视图里出现一个 `Text(fullName)`，下一个人顺手加个"· N 个"是极自然的动作。
    public static func summaryLine(fullName: String) -> String { fullName }

    /// 页脚（PRD §4.15 结构一行）。⚠️ **空态时不渲染**，理由同 `OpenIssueIndicator.footer`。
    public static let footer = "他人仓库：可评论 Review，合并 / 关闭需维护者权限"

    /// 空态标题（PRD §4.15「空态」段 · §7）。
    public static let emptyTitle = "暂无 Pull Request"

    /// 空态引导行（PRD §4.15「空态」段 · §7）。
    public static let emptyHint = "这个仓库还没有任何 Pull Request"
}

/// PR 列表的数据来源 —— 领域层与网络层之间的接缝。
public protocol RepoPullsDataSource: Sendable {

    /// `GET /repos/{owner}/{repo}/pulls?state=all` 的一页。
    func pullRequests(owner: String, repo: String, cursor: URL?) async throws -> Page<PullRequestDTO>
}

/// 让真实端点满足上面的接缝（协议是我们自己声明的，不是追溯适配）。
extension GitHubRepoPullsEndpoint: RepoPullsDataSource {}

/// 取探索 PR 列表的一页（PRD §4.15、决策 #39）。
public struct LoadRepoPulls: Sendable {

    private let source: any RepoPullsDataSource

    public init(source: any RepoPullsDataSource) {
        self.source = source
    }

    /// - Parameter cursor: 上一页的 `nextCursor`；`nil` 取第一页。
    /// - Returns: 一页 PR（**开放 + 已合并**，每行按状态换图标）。
    ///
    /// ## ⚠️ 两边都有过滤，但滤的不是同一样东西
    ///
    /// | | `LoadRepoIssues` | `LoadRepoPulls` |
    /// |---|---|---|
    /// | 滤掉什么 | **混进来的 PR**（`pull_request` 字段） | **已关闭但未合并的** |
    /// | 依据 | `GET /issues` 会混入 PR | PRD §4.15 只列开放 + 已合并 |
    ///
    /// 两个取数用例长得像、规则却不同 —— 这正是**不能合并成一个**的理由：
    /// 合并后必然要传一个"滤什么"的开关，而那个开关迟早会被用错一侧。
    ///
    /// ⚠️ 另一处不同：这里的过滤条件**在映射之后才成立**（"已关闭未合并"要靠
    /// `merged_at` 算出来，见 `PullRequestState`）⇒ 是 `map` 完再 `filter`，
    /// 而不是像 `LoadRepoIssues` 那样先 `filter`（那边判据 `pull_request`
    /// 在原始 DTO 上就成立）。
    ///
    /// ⚠️ 因此**分页步长同样不是"每页 30 个 PR"**：一页里被滤掉几条就少几条，
    /// 而"这一页没有可显示的了"不代表"后面也没有"⇒ `hasMore` 必须原样带走。
    public func load(fullName: String, cursor: URL? = nil) async throws -> Page<PullRow> {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let page = try await source.pullRequests(owner: owner, repo: repo, cursor: cursor)

        return Page(
            items: page.items.map(Self.row(from:)).filter { $0.state != .closed },
            nextCursor: page.nextCursor,
            headers: page.headers
        )
    }

    private static func row(from dto: PullRequestDTO) -> PullRow {
        PullRow(
            number: dto.number,
            title: dto.title,
            state: state(from: dto),
            headRef: dto.head.ref,
            baseRef: dto.base.ref
        )
    }

    /// `open` / `merged` / `closed` —— 判定收在 `PullRequestState(state:mergedAt:)`
    /// 那**一个**初始化器里（DTO 上的 `isMerged` 是它的镜像，见那里的说明）。
    private static func state(from dto: PullRequestDTO) -> PullRequestState {
        PullRequestState(state: dto.state, mergedAt: dto.mergedAt)
    }
}
