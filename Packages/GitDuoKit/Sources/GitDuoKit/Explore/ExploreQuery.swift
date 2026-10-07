import Foundation

/// 一次榜单请求的完整描述（TECH_SPEC §9.10.1）。
///
/// 领域层只负责**说清楚要什么**（限定符 / 排序 / 页大小），**不发请求** ——
/// 发请求是 `GitHubAPI` 的事。这样"限定符拼错了"可以在没有网络的情况下被单测抓住。
public struct ExploreQuery: Equatable, Sendable {

    public let board: TrendingBoard

    /// 产生这条查询的筛选状态（原样带回，供缓存键与界面文案复用）。
    public let filters: ExploreFilters

    /// `q=` 的值，如 `created:>=2026-07-08 language:Swift stars:>50`。
    public let qualifiers: String

    /// 服务端排序字段。新星榜 `stars`（总 Star，作**无基线时的天然回退序**）；活跃榜 `updated`。
    public let sort: String

    public let order: String

    public let perPage: Int

    /// 缓存键（决策 #37 / §9.10.5）。
    public var cacheKey: ExploreCacheKey {
        ExploreCacheKey(board: board, filters: filters)
    }
}

/// 榜单查询的拼装规则（TECH_SPEC §9.10.1）。
///
/// 三个"为什么"都在下面各自的常量上写清楚了。**别把阈值散到调用方** ——
/// `stars:>50` 与 90 天这两个数一旦分叉（比如某处写 30、某处写 90），
/// 用户会看到"同一个榜两次刷新结果对不上"，而排查时无从下手。
public enum ExploreQueryBuilder {

    /// 新星榜的"新建"窗口：近 **90 天**（TECH_SPEC §9.10.1；原型 `NEW_DAYS = 90`）。
    ///
    /// 为什么是固定 90 天而不是跟着日期范围走：日期范围在新星榜里调节的是**增幅的展示窗口**
    /// （`+812 本周` / `+812 本月`），不是"多新的仓库算新"。
    public static let newRepositoryWindowDays = 90

    /// 噪声兜底阈值（§9.10.1「可调」）。
    ///
    /// 没有它，`created:` 会捞回大量 0～几个 Star 的空仓库，把真榜单淹掉。
    public static let minimumStars = 50

    /// 首屏页大小。与仓库列表一致（§4.4），续页靠 `Link` 头（决策 #37）。
    public static let pageSize = 30

    /// 拼出一次请求所需的一切。
    ///
    /// - Parameter now: 显式传入，不内部取 `Date()` —— 否则"今天"在跨零点时会自己变，测不了。
    public static func query(
        board: TrendingBoard,
        filters: ExploreFilters,
        now: Date
    ) -> ExploreQuery {
        ExploreQuery(
            board: board,
            filters: filters,
            qualifiers: qualifiers(board: board, filters: filters, now: now),
            sort: board == .rising ? "stars" : "updated",
            order: "desc",
            perPage: pageSize
        )
    }

    /// 拼 `q=` 的限定符串。
    ///
    /// 顺序固定为 **窗口 → 语言 → 星数兜底**，与 §9.10.1 的写法一致
    /// （`q=created:>=<90 天前> stars:>50`，语言插在星数之前）。
    /// 顺序固定是为了让**同一组条件产生同一个字符串** —— 否则缓存键看着一样、
    /// 实际查询串不同，ETag 与缓存复用都会悄悄失效。
    public static func qualifiers(
        board: TrendingBoard,
        filters: ExploreFilters,
        now: Date
    ) -> String {
        var parts: [String] = []

        switch board {
        case .rising:
            let start = now.addingTimeInterval(-Double(newRepositoryWindowDays) * 86_400)
            parts.append("created:>=\(dayString(start))")
        case .active:
            // `range` 为空（"全部"）时沿用一个周窗 —— 与原型一致：
            // `{'今天':1440,'本周':10080,'本月':43200}[range] || 10080`。
            // ⚠️ 这里**不能**理解成"不加限定符"：Search 的 `pushed:` 一旦省略，
            //    活跃榜就退化成"全站总星排行"，与"持续活跃"的榜单语义完全无关。
            let window = (filters.range ?? .thisWeek).window
            let start = now.addingTimeInterval(-window)
            parts.append("pushed:>=\(dayString(start))")
        }

        if let language = filters.language {
            parts.append("language:\(language)")
        }

        parts.append("stars:>\(minimumStars)")

        return parts.joined(separator: " ")
    }

    /// 日期限定符用 **`YYYY-MM-DD`（UTC，日粒度）**。
    ///
    /// 为什么用日粒度而不是精确到秒：
    /// - GitHub 的 `created:` / `pushed:` 官方支持的两种格式里就有 `YYYY-MM-DD`，是最稳的一种；
    /// - 日粒度让**同一自然日内的查询串保持稳定** ⇒ ETag 条件请求更容易命中 304，
    ///   而 Search 配额独立且只有 30 次/分钟（§9.10.1）；
    /// - 界面把这一维叫「**日期**范围」，日粒度与用户的理解一致。
    ///
    /// 用 UTC 而不是设备时区：同一次筛选在不同时区的设备上必须得到**同一个**查询串，
    /// 否则"手机上的结果和文档里写的对不上"这类问题永远说不清。
    private static func dayString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1
        )
    }
}
