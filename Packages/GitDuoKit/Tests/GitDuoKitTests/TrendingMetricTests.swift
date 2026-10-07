import Foundation
import Testing

@testable import GitDuoKit

/// 趋势卡片三个角标的文案（原型 `scripts/09-explore.js` 的 `trendRows()`）。
///
/// harness 断言 `新星榜行含「创建」`、`活跃榜行含「推送」` —— 这两个词是契约。
@Suite("TrendingMetric · 创建日 / 最近推送")
struct TrendingMetricTests {

    private func iso(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.gmt
        return formatter.date(from: text) ?? .distantPast
    }

    private let now = ISO8601DateFormatter().date(from: "2026-10-05T12:00:00Z") ?? .distantPast

    // MARK: - 新星榜：创建日

    @Test("创建日角标形如 `🆕 08-05 创建`（原型取 `YYYY-MM-DD` 的后 5 位）")
    func createdLabelFormat() {
        let label = TrendingMetric.createdLabel(createdAt: iso("2026-08-05T12:00:00Z"))

        #expect(label == "🆕 08-05 创建")
        #expect(label.contains("创建"), "harness 断言的就是这个词")
    }

    @Test("月 / 日补零 —— 不出现 `🆕 1-9 创建`")
    func createdLabelIsZeroPadded() {
        #expect(TrendingMetric.createdLabel(createdAt: iso("2026-01-09T12:00:00Z")) == "🆕 01-09 创建")
    }

    @Test("按 **UTC** 取日 —— 与 `created:` 限定符同一套时区，否则两者会自相矛盾")
    func createdLabelUsesUTC() {
        // 这一刻在 UTC 还是 8 月 5 日，但在 UTC+8 已经是 8 月 6 日。
        // 若跟着设备时区走，会出现"限定符说 8 月 5 日之后、卡片却显示 08-06"。
        let label = TrendingMetric.createdLabel(createdAt: iso("2026-08-05T23:30:00Z"))

        #expect(label == "🆕 08-05 创建")
    }

    @Test("不带年份 —— 新星榜只看近 90 天，年份是冗余信息")
    func createdLabelOmitsYear() {
        let label = TrendingMetric.createdLabel(createdAt: iso("2026-08-05T12:00:00Z"))

        #expect(!label.contains("2026"))
        #expect(!label.contains("26"))
    }

    // MARK: - 活跃榜：最近推送

    @Test("最近推送角标形如 `⚡ 30 分钟前推送`")
    func lastPushLabelFormat() {
        let pushed = now.addingTimeInterval(-30 * 60)
        let label = TrendingMetric.lastPushLabel(pushedAt: pushed, now: now)

        #expect(label == "⚡ 30 分钟前推送")
        #expect(label.contains("推送"), "harness 断言的就是这个词")
    }

    @Test("相对时间**现算**，不是存下来的字符串 —— 否则「30 分钟前」会永远停在 30 分钟")
    func lastPushLabelIsLive() {
        let pushed = now.addingTimeInterval(-30 * 60)

        #expect(TrendingMetric.lastPushLabel(pushedAt: pushed, now: now) == "⚡ 30 分钟前推送")
        #expect(
            TrendingMetric.lastPushLabel(pushedAt: pushed, now: now.addingTimeInterval(2 * 3_600))
                == "⚡ 2 小时前推送"
        )
    }

    @Test("跨到「昨天」档也带「推送」后缀")
    func lastPushLabelYesterday() {
        let pushed = now.addingTimeInterval(-30 * 3_600)
        let label = TrendingMetric.lastPushLabel(pushedAt: pushed, now: now)

        #expect(label == "⚡ 昨天推送")
        #expect(label.contains("推送"))
    }
}
