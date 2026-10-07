import Foundation
import Testing

@testable import GitDuoKit

/// 榜单查询串的拼装（TECH_SPEC §9.10.1）。
///
/// 限定符写错不会编译失败，只会**悄悄返回另一批数据** —— 所以这里逐字断言拼出来的串。
@Suite("ExploreQuery · 限定符 / 排序 / 日期")
struct ExploreQueryTests {

    /// 固定基准时刻：`2026-10-05T12:00:00Z`。用 ISO 字符串构造而不是算时间戳 ——
    /// 手算 epoch 秒数极易写错，而写错的后果是"测试通过了但基准日根本不对"。
    private func iso(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.gmt
        return formatter.date(from: text) ?? .distantPast
    }

    private var now: Date { iso("2026-10-05T12:00:00Z") }

    // MARK: - 新星榜

    @Test("新星榜：`created:` 取 **固定 90 天**窗外 + `stars:>50` 兜底")
    func risingQualifiers() {
        let query = ExploreQueryBuilder.query(board: .rising, filters: .default, now: now)

        // 2026-10-05 往前 90 天 = 2026-07-07
        #expect(query.qualifiers == "created:>=2026-07-07 stars:>50")
    }

    @Test("新星榜：日期范围**不改** `created:` 窗口 —— 它只调节增幅的展示窗口")
    func risingWindowIgnoresDateRange() {
        // 若这里跟着 range 变，`本月` 会变成"近 30 天新建的仓库"，
        // 与新星榜「近 90 天涌现」的定义就不是一回事了。
        let today = ExploreQueryBuilder.query(
            board: .rising, filters: ExploreFilters(range: .today, language: nil), now: now
        )
        let month = ExploreQueryBuilder.query(
            board: .rising, filters: ExploreFilters(range: .thisMonth, language: nil), now: now
        )

        #expect(today.qualifiers.contains("created:>=2026-07-07"))
        #expect(month.qualifiers.contains("created:>=2026-07-07"))
    }

    @Test("新星榜按 **总 Star** 请求排序 —— 这正是无基线时的天然回退序（决策 #36）")
    func risingSortsByStars() {
        let query = ExploreQueryBuilder.query(board: .rising, filters: .default, now: now)

        #expect(query.sort == "stars")
        #expect(query.order == "desc")
    }

    // MARK: - 活跃榜

    @Test("活跃榜：`pushed:` 起点跟日期范围走（本周 = 7 天前）")
    func activeQualifiersFollowRange() {
        let week = ExploreQueryBuilder.query(
            board: .active, filters: ExploreFilters(range: .thisWeek, language: nil), now: now
        )

        #expect(week.qualifiers == "pushed:>=2026-09-28 stars:>50")
    }

    @Test("活跃榜三档窗口：今天 / 本周 / 本月 → 1 / 7 / 30 天前")
    func activeRangeWindows() {
        func pushed(_ range: ExploreDateRange) -> String {
            ExploreQueryBuilder.query(
                board: .active, filters: ExploreFilters(range: range, language: nil), now: now
            ).qualifiers
        }

        #expect(pushed(.today).contains("pushed:>=2026-10-04"))
        #expect(pushed(.thisWeek).contains("pushed:>=2026-09-28"))
        #expect(pushed(.thisMonth).contains("pushed:>=2026-09-05"))
    }

    @Test("⚠️ 活跃榜在「全部」（range 为空）时**仍然加** `pushed:` 限定符")
    func activeNeverDropsTheWindowQualifier() {
        let query = ExploreQueryBuilder.query(
            board: .active, filters: ExploreFilters(range: nil, language: nil), now: now
        )

        // 去掉它，活跃榜会退化成"全站总星排行"，与「持续活跃」的榜单语义完全无关。
        #expect(query.qualifiers.contains("pushed:>="))
        #expect(query.qualifiers.contains("pushed:>=2026-09-28"), "空选沿用一周窗（与原型一致）")
    }

    @Test("活跃榜按 `updated` 请求排序，客户端再按 `pushed_at` 精确排")
    func activeSortsByUpdated() {
        let query = ExploreQueryBuilder.query(board: .active, filters: .default, now: now)

        #expect(query.sort == "updated")
        #expect(query.order == "desc")
    }

    // MARK: - 语言

    @Test("语言限定符**插在星数兜底之前** —— 顺序固定，同一组条件必须得到同一个串")
    func languageQualifierOrder() {
        let query = ExploreQueryBuilder.query(
            board: .rising, filters: ExploreFilters(range: .thisWeek, language: "Swift"), now: now
        )

        #expect(query.qualifiers == "created:>=2026-07-07 language:Swift stars:>50")
    }

    @Test("语言未选时不产生 `language:` —— 不能拼出一个空的限定符")
    func noLanguageWhenUnselected() {
        let query = ExploreQueryBuilder.query(
            board: .active, filters: ExploreFilters(range: .today, language: nil), now: now
        )

        #expect(!query.qualifiers.contains("language:"))
        #expect(!query.qualifiers.contains("  "), "两个空格说明拼接处留下了空片段")
        #expect(!query.qualifiers.hasSuffix(" "))
    }

    // MARK: - 通用

    @Test("首屏页大小 30（决策 #37）")
    func pageSize() {
        #expect(ExploreQueryBuilder.pageSize == 30)
        #expect(ExploreQueryBuilder.query(board: .rising, filters: .default, now: now).perPage == 30)
    }

    @Test("阈值集中在一处：90 天 / 50 星")
    func thresholdsAreSingleSourced() {
        #expect(ExploreQueryBuilder.newRepositoryWindowDays == 90)
        #expect(ExploreQueryBuilder.minimumStars == 50)
    }

    @Test("同一时刻 + 同一筛选 ⇒ **逐字相同**的查询串（否则缓存与 ETag 会悄悄失效）")
    func qualifiersAreDeterministic() {
        let filters = ExploreFilters(range: .thisMonth, language: "Go")

        let first = ExploreQueryBuilder.qualifiers(board: .active, filters: filters, now: now)
        let second = ExploreQueryBuilder.qualifiers(board: .active, filters: filters, now: now)

        #expect(first == second)
    }

    @Test("**日粒度、UTC** —— 同一天内查询串不随时分秒变化")
    func dateGranularityIsOneDay() {
        let morning = ExploreQueryBuilder.qualifiers(
            board: .rising, filters: .default, now: iso("2026-10-05T00:01:00Z")
        )
        let evening = ExploreQueryBuilder.qualifiers(
            board: .rising, filters: .default, now: iso("2026-10-05T23:59:00Z")
        )

        #expect(morning == evening, "同一天内串变了 ⇒ ETag 白费、Search 配额被多耗")
    }

    @Test("跨一天则串必须变 —— 否则「今天」这个窗口永远不会滑动")
    func dateRollsOverAtMidnight() {
        let today = ExploreQueryBuilder.qualifiers(
            board: .active, filters: ExploreFilters(range: .today, language: nil), now: iso("2026-10-05T12:00:00Z")
        )
        let tomorrow = ExploreQueryBuilder.qualifiers(
            board: .active, filters: ExploreFilters(range: .today, language: nil), now: iso("2026-10-06T12:00:00Z")
        )

        #expect(today != tomorrow)
        #expect(today.contains("2026-10-04"))
        #expect(tomorrow.contains("2026-10-05"))
    }

    @Test("查询对象自带缓存键，且键与筛选一一对应")
    func queryCarriesCacheKey() {
        let filters = ExploreFilters(range: .thisMonth, language: "Rust")
        let query = ExploreQueryBuilder.query(board: .active, filters: filters, now: now)

        #expect(query.cacheKey == ExploreCacheKey(board: .active, filters: filters))
    }
}
