import Foundation
import GitHubAPI

/// 「我的」页取数的一路结果 —— **要么拿到值，要么拿到那个错误**（TECH_SPEC §9.14）。
///
/// ## 为什么不用 `Result`
///
/// 语义上它就是 `Result<Value, GitHubError>`，但 `Result` 的失败侧不会告诉我们
/// "这一路是哪一路"。而界面上要说的话、要给的出口都挂在**具体那一路**上
/// （热力图卡片内一行灰字 + 重试）。做成自己的类型之后，
/// "失败的那一路"由**它挂在哪个属性上**表达，读代码时不必回头翻错误内容。
///
/// ## 为什么失败侧留的是 `GitHubError` 而不是一句话
///
/// 因为"该说哪句话"是**展示层**的事，而且已经有一处正本了
/// （App 层的 `SectionFailure`：`这一块加载失败` + `重试`，且它自己按错误类型
/// 决定读屏提示 —— 404 与无权限被 GitHub 混同，不得替用户断定，`TECH_SPEC §14`）。
/// 领域层只交事实，不在这里另起一套话术。
public enum ProfileSection<Value: Sendable>: Sendable {

    case value(Value)
    case failure(GitHubError)

    /// 拿到了就是它；没拿到是 `nil`。
    public var value: Value? {
        if case let .value(value) = self { return value }
        return nil
    }

    /// 失败时是那个错误；成功是 `nil`。
    public var error: GitHubError? {
        if case let .failure(error) = self { return error }
        return nil
    }

    public var isFailure: Bool { value == nil }
}

/// `GitHubError` 手写了 `Equatable`（只比 case 与文本，不比底层 `Error`）
/// ⇒ 这里可以顺带把整条链变成可比较的，测试断言"哪一路失败了"就不必写 `switch`。
extension ProfileSection: Equatable where Value: Equatable {}

/// 「我的」页一次取数的全部结果（PRD §4.17、TECH_SPEC §9.14、决策 #74 / #76）。
///
/// ## 三块东西、两条路径、**失败互不牵连**
///
/// | 属性 | 来源 | 失败时 |
/// |---|---|---|
/// | `identity` | `GET /user` | 头像与 `@登录名` **照常显示**（登录名取自 `authState`），只是昵称 / 简介无从得知 |
/// | `grid` | GraphQL 的 `contributionCalendar` | 热力图卡片内一行灰字 + 重试 |
/// | `stats` | GraphQL 两个 `totalCount` + `GET /user` 的 `followers` | 逐项降级（见 `ProfileStats`） |
///
/// 三者分得这么开，是因为它们**真的会各自失败**：REST 与 GraphQL 是两个端点、
/// 两个配额桶，而 GraphQL 自己还允许"部分成功"（`TECH_SPEC §4.3` 第 2 条）。
/// 把它们合成一个"整页成功 / 整页失败"的开关，表现就是**一张热力图取不到、
/// 整个「我的」页变成一片失败态** —— 而头像是本机从登录名画出来的，它根本不会失败。
///
/// ## ⚠️ 零贡献**不是**失败
///
/// 一年没动过账：`grid` 是 `.value(…)`，里面 `totalContributions == 0`、
/// 53 列全是最浅档。PRD §4.17 明写这种情形**照常画一张全空的图**、不给空态 ——
/// "零贡献"是一个有意义的事实，与"没取到"（`.failure`）不是一回事。
/// 类型上这两者也不一样，视图**没法**把它们画成同一种东西。
///
/// ## ⚠️ `year` 是"**这一份数据是拿哪一年换来的**"
///
/// 2026-10-09 加（用户走查第 2 条：热力图要能切年份）。它必须跟着数据走，
/// 而不是放在视图的 `@State` 里：切换年份的那一瞬间，屏幕上是**旧一年的数据**，
/// 而卡片右上如果照"我刚点的那一项"写字，就会出现"写着 2025、画的是 2026"
/// —— 两个数**各自都是真的**，摆在一起才成了假话（同 `ViewerActivityDTO` 那条 `affiliations` 的教训）。
///
/// 所以口径是：**总数与年份是同一份数据的两面**，一起换；要换就得等新的回来。
public struct ProfileOverview: Sendable {

    /// 这一份结果对应的年份（`LoadProfileOverview.load(year:)` 的入参）。
    ///
    /// ⚠️ 即使 `identity` / `grid` 都失败了它也是有的 —— 失败的是"这一年的数"，
    /// 不是"我们在问哪一年"。
    public let year: ContributionYear

    public let identity: ProfileSection<ViewerProfile>

    public let grid: ProfileSection<ContributionGrid>

    public let stats: ProfileStats

    public init(
        year: ContributionYear,
        identity: ProfileSection<ViewerProfile>,
        grid: ProfileSection<ContributionGrid>,
        stats: ProfileStats
    ) {
        self.year = year
        self.identity = identity
        self.grid = grid
        self.stats = stats
    }

    /// 资料头部 —— 拿不到就是 `nil`（此时头像与 `@登录名` 由 `authState` 兜底，见类型说明）。
    public var profile: ViewerProfile? { identity.value }

    public var gridValue: ContributionGrid? { grid.value }
}
