import Foundation
import GitHubAPI

/// 取「我的」页的两路数据，**并发、各降级**（TECH_SPEC §9.14）。
///
/// ## 它为什么**不 throw**
///
/// 因为它取的是**两个可以各自失败的东西**。用一个 `throws` 表达，调用方就只能
/// 得到"整页失败"这一个信息 —— 而这一页上至少有三样东西**根本不会失败**：
/// `@登录名`（本机取自 `authState`）、**头像**（真实图片取不到时回落成本机画的
/// 首字母块 —— 偏差第 43 条，所以它也只是"换一种画法"、不是失败）、
/// 以及已经拿到手的那一路数据。让它们跟着一起变灰，是决策 #76 末句点名要避免的事。
///
/// 于是失败被折叠进返回值：`identity` 与 `grid` 各自是 `ProfileSection`，
/// `stats` 逐项可空。视图据此**分块**降级（哪一块失败就只降那一块）。
///
/// ## ⚠️ 为什么"两路并发"值得写出来
///
/// 两条请求之间没有任何依赖（一个要昵称，一个要日历 + 计数），串行等于白等一次往返。
/// 而并发在这里是安全的：它们是**两个只读的 GET/POST**，
/// 没有"先写后读"的顺序问题（对照：`TECH_SPEC §13.2` 的提交流程必须三步串行）。
///
/// ## ⚠️ 它不做"部分成功"的打捞
///
/// GraphQL 允许 `data` + `errors` 并存（§4.3 第 2 条），而 `GitHubGraphQLClient`
/// 刻意在那种情形**抛错并带上 `partialData`**，好让调用方自己决定要不要用。
/// 这里的选择是**不打捞**：出错就整块降级成"一行灰字 + 重试"。
///
/// 理由有两条，都不是偷懒：
/// 1. **打捞出来的那份数据是不完整的**，而这一页上没有任何位置能说明"两个计数准、
///    日历缺了几天"—— 用户看到一张画了一半的热力图，会以为那就是他的一年；
/// 2. 出口很便宜 —— 重试一次就是**一次往返 1 点**。
///
/// 代价如实记在这里：**部分成功时那两个计数也一起不显示**（它们本来是可以救回来的）。
public struct LoadProfileOverview: Sendable {

    private let source: any ProfileDataSource
    private let mapper: ProfileMapper
    private let board: ContributionYearBoard

    public init(
        source: any ProfileDataSource,
        mapper: ProfileMapper = ProfileMapper(),
        board: ContributionYearBoard = ContributionYearBoard()
    ) {
        self.source = source
        self.mapper = mapper
        self.board = board
    }

    /// 可切换的年份（顺序 = 菜单顺序，当前年在第一个）—— 2026-10-09 加，用户走查第 2 条。
    ///
    /// ⚠️ 选项由**取数这一侧**给出（而不是让视图自己算年份）：窗口的计算与"这一年怎么取"
    /// 必须是同一个口径，分两处就会有一天出现"菜单里写着 2025、取的却是 2024"。
    public var years: [ContributionYear] { board.years }

    /// 进页默认看的那一年。
    public var currentYear: ContributionYear { board.current }

    /// 取某一年的两路数据（并发、各降级）。窗口由 `board` 按本机日历算。
    ///
    /// ⚠️ `year` **不是可选的**：默认值会造出"忘了说看哪一年也能跑"的调用，
    /// 而那正是"右上写着 2025、图是 2026"这类错误的温床。要当前年就传 `currentYear`。
    public func load(year: ContributionYear) async -> ProfileOverview {
        let interval = board.interval(of: year)

        // 两路并发。`async let` 一写出来两个请求就都发出去了。
        async let profileAttempt = attempt { try await source.loadProfile() }
        async let activityAttempt = attempt {
            try await source.loadActivity(from: interval.start, to: interval.end)
        }

        let profileDTO = await profileAttempt
        let activityDTO = await activityAttempt

        return ProfileOverview(
            year: year,
            identity: profileDTO.map { mapper.profile($0) },
            // ⚠️ 把 `year` 一起交给映射层：服务端按周返回、首周可能带着上一年 12 月的
            //    日子，要按年份前缀裁掉（走查第 60 条，`ProfileMapper.grid(_:year:)`）。
            //    这正是"菜单里写着 2025、取的却是 2024"那类错误的第二道防线。
            grid: activityDTO.map { mapper.grid($0, year: year) },
            // ⚠️ 三个数**各取各的来源**：仓库 / Star 来自 GraphQL（没拿到就是 `nil`），
            //    Follower 来自 `GET /user`（与 GraphQL 那一发完全无关）。
            stats: mapper.stats(
                activity: activityDTO.value,
                followers: profileDTO.value?.followers
            )
        )
    }

    /// 把一次"可能抛错的取数"折成 `ProfileSection`。
    ///
    /// ## 为什么 `catch` 有一个兜底分支
    ///
    /// 生产里到不了（两条路径的实现在 `GitHubAPI` 内，抛的都是 `GitHubError`）；
    /// 留它是为了**不靠"实现一定抛 GitHubError"来保证不崩** ——
    /// 真有第三个错误类型冒出来时，正确的表现是"这一块降级"，
    /// 而不是让 `load()` 把整个页面炸掉。
    /// 归到 `.decoding` 是因为它的语义就是"端点回了一个我们没预期的东西"。
    private func attempt<Value: Sendable>(
        _ body: () async throws -> Value
    ) async -> ProfileSection<Value> {
        do {
            return .value(try await body())
        } catch let error as GitHubError {
            return .failure(error)
        } catch {
            return .failure(.decoding(error))
        }
    }
}

private extension ProfileSection {

    /// `ProfileSection<A>` → `ProfileSection<B>`（失败原样带过去）。
    func map<Mapped: Sendable>(_ transform: (Value) -> Mapped) -> ProfileSection<Mapped> {
        switch self {
        case let .value(value): .value(transform(value))
        case let .failure(error): .failure(error)
        }
    }
}
