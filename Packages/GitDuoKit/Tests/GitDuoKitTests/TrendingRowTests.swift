import Foundation
import Testing

@testable import GitDuoKit

/// 探索榜的行：角标内容与排序（PRD §4.12、TECH_SPEC §9.10.1–§9.10.2、决策 #36）。
///
/// ## 这组断言守的是"不造数"
///
/// 三个指标文案都是**可见契约**（harness 直接断言榜单行里出现「创建」与「推送」），
/// 而最容易出的错是**在没有依据时编一个数**：
///
/// - **没有基线** ⇒ 不显示增幅。那不是"0"，是"没问过"。
/// - **增量为 0** ⇒ 也不显示。`StarGain.windowDelta` 的下限是 1（为"今天档把 +3 算成 0"
///   准备的），照用会让一屏 30 个仓库**齐刷刷显示 `+1 本周`** —— 那个 1 是凭空来的。
/// - **增量为负** ⇒ 同样不显示。原型只印 `+`，印 `−3 本周` 是自造文案。
///
/// 排序那条守的是"不抖动"：`sorted(by:)` **不保证稳定**，靠原下标裁决才能让
/// 同一份输入永远得到同一份输出。
@Suite("探索榜 · 角标内容与排序")
struct TrendingRowTests {

    private let now = Date(timeIntervalSince1970: 1_786_000_000)

    /// 一个固定的 UTC 时刻 —— 用来断言 `🆕 MM-DD 创建` 里的那一对数字。
    ///
    /// 用 `Calendar` 而不是硬编码秒数：那样断言才是在读"日期"，而不是在猜时区换算。
    private func utcDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.gmt
        return calendar.date(from: components)!
    }

    private func source(
        _ fullName: String,
        stars: Int = 100,
        created: Date? = nil,
        pushed: Date? = nil,
        delta: Int? = nil
    ) -> TrendingRowBuilder.Source {
        TrendingRowBuilder.Source(
            summary: RepoSummary(fullName: fullName, starCount: stars),
            createdAt: created ?? utcDate(year: 2026, month: 8, day: 5),
            pushedAt: pushed,
            weeklyDelta: delta
        )
    }

    // MARK: - 新星榜的角标

    @Test("有正增量 ⇒ 两条：指标在前（`+812 本周`）、创建日在后（`🆕 08-05 创建`）")
    func risingShowsMetricThenDetail() {
        let indicators = TrendingRowBuilder.indicators(
            board: .rising,
            filters: .default,                       // 日期范围 = 本周 ⇒ 窗口词也是「本周」
            source: source("a/b", delta: 812),
            now: now
        )

        #expect(indicators.count == 2)
        #expect(indicators[0].text == "+812 本周")
        #expect(indicators[0].role == .metric)
        #expect(indicators[1].text == "🆕 08-05 创建")
        #expect(indicators[1].role == .detail)
    }

    @Test("今天档的窗口词是 `今日`（与 chip 上的 `今天` **有意不同**，原型就这么分）")
    func todayWindowUsesItsOwnWord() {
        let indicators = TrendingRowBuilder.indicators(
            board: .rising,
            filters: ExploreFilters(range: .today, language: nil),
            source: source("a/b", delta: 812),
            now: now
        )

        #expect(indicators[0].text == "+116 今日", "812 / 7 ≈ 116")
    }

    @Test("⚠️ **没有基线** ⇒ 只剩创建日那一条（不显示增幅，也不显示破折号）")
    func risingHidesGainWithoutBaseline() {
        let indicators = TrendingRowBuilder.indicators(
            board: .rising, filters: .default, source: source("a/b", delta: nil), now: now
        )

        #expect(indicators.count == 1)
        #expect(indicators[0].text == "🆕 08-05 创建")
        #expect(indicators.allSatisfy { !$0.text.contains("+") })
    }

    @Test("⚠️ 增量为 **0** ⇒ 同样不显示 —— 否则一屏齐刷刷 `+1 本周`（那个 1 是凭空来的）")
    func risingHidesZeroGain() {
        let indicators = TrendingRowBuilder.indicators(
            board: .rising, filters: .default, source: source("a/b", delta: 0), now: now
        )

        #expect(indicators.count == 1)
        #expect(!indicators.contains { $0.role == .metric })
        #expect(indicators.allSatisfy { !$0.text.contains("+") },
                "`windowDelta` 的下限 1 是为窗口换算准备的，不是给「无涨」兜底的")
    }

    @Test("⚠️ 增量为**负** ⇒ 也不显示（原型只印 `+`，`−3 本周` 是自造文案）")
    func risingHidesNegativeGain() {
        let indicators = TrendingRowBuilder.indicators(
            board: .rising, filters: .default, source: source("a/b", delta: -3), now: now
        )

        #expect(indicators.count == 1)
        #expect(indicators.allSatisfy { !$0.text.contains("\u{2212}") && !$0.text.contains("-3") })
    }

    @Test("创建日按 **UTC** 取日 —— 与 `created:` 限定符同一套时区")
    func createdLabelUsesUTC() {
        // 北京时间 8/6 00:30 = UTC 8/5 16:30；按 UTC 取日必须是 08-05，
        // 否则"限定符说 8 月 5 日之后、卡片却显示 08-06"会自相矛盾。
        let date = utcDate(year: 2026, month: 8, day: 5)
        #expect(TrendingMetric.createdLabel(createdAt: date) == "🆕 08-05 创建")
    }

    // MARK: - 活跃榜的角标

    @Test("有推送时间 ⇒ 一条：`⚡ 30 分钟前推送`")
    func activeShowsLastPush() {
        let indicators = TrendingRowBuilder.indicators(
            board: .active,
            filters: .default,
            source: source("a/b", pushed: now.addingTimeInterval(-1_800)),
            now: now
        )

        #expect(indicators.count == 1)
        #expect(indicators[0].text == "⚡ 30 分钟前推送")
        #expect(indicators[0].role == .metric)
    }

    @Test("⚠️ **没有推送时间 ⇒ 空数组**（不是拿创建日顶上 —— 那会把「创建于」显示成「推送于」）")
    func activeWithoutPushTimeHasNoIndicators() {
        let indicators = TrendingRowBuilder.indicators(
            board: .active, filters: .default, source: source("a/b", pushed: nil), now: now
        )

        #expect(indicators.isEmpty)
    }

    // MARK: - 排序

    @Test("新星榜：**有基线的一组按增量降序在前，无基线的一组保原序在后**")
    func risingRanksScoredFirstThenUnscored() {
        let rows = TrendingRowBuilder.rows(
            board: .rising,
            filters: .default,
            sources: [
                source("a/low", delta: 5),
                source("b/none", delta: nil),
                source("c/high", delta: 20),
            ],
            now: now
        )

        #expect(rows.map(\.fullName) == ["c/high", "a/low", "b/none"])
    }

    @Test("⚠️ 首次运行（全都没基线）⇒ 顺序 = 传入顺序（即服务端的总 Star 降序）")
    func allUnscoredKeepsServerOrder() {
        let rows = TrendingRowBuilder.rows(
            board: .rising,
            filters: .default,
            sources: [source("a/first", delta: nil), source("b/second", delta: nil)],
            now: now
        )

        #expect(rows.map(\.fullName) == ["a/first", "b/second"])
    }

    @Test("活跃榜：按最近推送降序，**没有推送时间的排最后**")
    func activeRanksByRecentPushWithNilsLast() {
        let rows = TrendingRowBuilder.rows(
            board: .active,
            filters: .default,
            sources: [
                source("a/old", pushed: now.addingTimeInterval(-3_600)),
                source("b/never", pushed: nil),
                source("c/new", pushed: now.addingTimeInterval(-60)),
            ],
            now: now
        )

        #expect(rows.map(\.fullName) == ["c/new", "a/old", "b/never"])
    }

    @Test("⚠️ **同刻稳定**：推送时间一样时保持传入顺序（否则列表会在两次刷新之间无理由地抖动）")
    func equalPushTimesKeepInputOrder() {
        let same = now.addingTimeInterval(-600)
        let rows = TrendingRowBuilder.rows(
            board: .active,
            filters: .default,
            sources: [
                source("a/first", pushed: same),
                source("b/second", pushed: same),
                source("c/third", pushed: same),
            ],
            now: now
        )

        #expect(rows.map(\.fullName) == ["a/first", "b/second", "c/third"])
    }

    @Test("⚠️ 两个都没有推送时间时也按原序（不是随机）")
    func bothNilPushTimesKeepInputOrder() {
        let rows = TrendingRowBuilder.rows(
            board: .active,
            filters: .default,
            sources: [source("a", pushed: nil), source("b", pushed: nil)],
            now: now
        )

        #expect(rows.map(\.fullName) == ["a", "b"])
    }

    // MARK: - 行的其余部分

    @Test("`id` 用仓库全名（与 `ForEach` 的去重同一口径）")
    func idIsTheFullName() {
        let rows = TrendingRowBuilder.rows(
            board: .rising, filters: .default, sources: [source("kuda/ui-craft", delta: nil)], now: now
        )

        #expect(rows.first?.id == "kuda/ui-craft")
        #expect(rows.first?.fullName == "kuda/ui-craft")
    }

    @Test("两个时刻原样留着（视图需要给读屏更完整的文案，角标串本身未必适合念出来）")
    func timestampsAreKeptForAccessibility() {
        let created = utcDate(year: 2026, month: 8, day: 5)
        let pushed = now.addingTimeInterval(-1_800)
        let rows = TrendingRowBuilder.rows(
            board: .active,
            filters: .default,
            sources: [source("a/b", created: created, pushed: pushed)],
            now: now
        )

        #expect(rows.first?.createdAt == created)
        #expect(rows.first?.pushedAt == pushed)
    }

    @Test("榜单行的摘要**不含可写性**（搜索接口给不出 `permissions`，决策 #43）")
    func rowSummaryHasNoWritability() {
        let rows = TrendingRowBuilder.rows(
            board: .rising, filters: .default, sources: [source("a/b", delta: nil)], now: now
        )

        #expect(rows.first?.summary.canWrite == nil)
        #expect(rows.first?.summary.canOpenWritableDetail == false, "不猜 ⇒ 保守走向只读页")
    }
}
