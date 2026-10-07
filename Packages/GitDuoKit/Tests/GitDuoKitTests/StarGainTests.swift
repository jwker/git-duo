import Foundation
import Testing

@testable import GitDuoKit

/// 新星榜的增幅换算与排序（TECH_SPEC §9.10.2 / 决策 #36）。
@Suite("StarGain · 换算 / 角标 / 排序")
struct StarGainTests {

    private struct Row {
        let name: String
        /// 周增量；`nil` = 还没有本地基线
        let delta: Int?
    }

    // MARK: - 窗口换算

    @Test("本周 = 周值原样（PRD §4.12 的 `+812 本周`）")
    func weekScale() {
        #expect(StarGain.windowDelta(weeklyDelta: 812, range: .thisWeek) == 812)
    }

    @Test("本月 ≈ ×4.3、今天 ≈ ×1/7")
    func monthAndDayScale() {
        #expect(StarGain.windowDelta(weeklyDelta: 812, range: .thisMonth) == 3_492)
        #expect(StarGain.windowDelta(weeklyDelta: 812, range: .today) == 116)
    }

    @Test("没有日期范围时按 ×1（原型 `|| 1`）")
    func nilRangeIsIdentity() {
        #expect(StarGain.windowDelta(weeklyDelta: 812, range: nil) == 812)
    }

    @Test("**下限是 1** —— 正在涨的仓库不该显示 `+0 今日`")
    func neverShowsZero() {
        // 今天档系数是 1/7：周增量 3 会算成 0.43 → 取整 0。
        // 对用户来说「+0 今日」比"不显示"更困惑 —— 明明在涨。
        #expect(StarGain.windowDelta(weeklyDelta: 3, range: .today) == 1)
        #expect(StarGain.windowDelta(weeklyDelta: 0, range: .thisWeek) == 1)
    }

    // MARK: - 角标

    @Test("有基线 ⇒ `+812 本周`；角标里的窗口词用 `badgeLabel`（今日而非今天）")
    func badgeWithBaseline() {
        #expect(StarGain.badge(weeklyDelta: 812, range: .thisWeek) == "+812 本周")
        #expect(StarGain.badge(weeklyDelta: 812, range: .thisMonth) == "+3492 本月")
        #expect(StarGain.badge(weeklyDelta: 812, range: .today) == "+116 今日")
    }

    @Test("没有日期范围 ⇒ 窗口词回落「近期」（原型 `RANGE_LABEL[range] || '近期'`）")
    func badgeFallsBackToRecent() {
        #expect(StarGain.badge(weeklyDelta: 812, range: nil) == "+812 近期")
        #expect(StarGain.unspecifiedWindowLabel == "近期")
    }

    @Test("⚠️ **无基线 ⇒ 返回 `nil`**：调用方据此不渲染该角标")
    func badgeIsNilWithoutBaseline() {
        // 决策 #36：这一步**不是**"回退显示总 Star" —— 卡片上已经有一个 Star 角标在显示总 Star，
        // 再回退一次会让同一个数字在同一张卡上出现两次。
        #expect(StarGain.badge(weeklyDelta: nil, range: .thisWeek) == nil)
        #expect(StarGain.badge(weeklyDelta: nil, range: nil) == nil)
    }

    // MARK: - 排序

    @Test("全部无基线 ⇒ **原序不变**，即服务端总 Star 降序（决策 #36 的回退）")
    func allWithoutBaselineKeepsServerOrder() {
        let rows = [
            Row(name: "big", delta: nil), Row(name: "mid", delta: nil), Row(name: "small", delta: nil),
        ]

        let ranked = StarGain.rank(rows, delta: \.delta, range: .thisWeek)

        #expect(ranked.map(\.name) == ["big", "mid", "small"])
    }

    @Test("全部有基线 ⇒ 按窗口增量降序")
    func allWithBaselineSortedByDelta() {
        let rows = [Row(name: "b", delta: 100), Row(name: "d", delta: 500), Row(name: "c", delta: 200)]

        let ranked = StarGain.rank(rows, delta: \.delta, range: .thisWeek)

        #expect(ranked.map(\.name) == ["d", "c", "b"])
    }

    @Test("混合 ⇒ **有基线的排在前**（组内按增量降序），无基线的接在后且保持原序")
    func mixedPutsBaselinedFirst() {
        let rows = [
            Row(name: "noBaselineBig", delta: nil),
            Row(name: "delta100", delta: 100),
            Row(name: "noBaselineSmall", delta: nil),
            Row(name: "delta500", delta: 500),
        ]

        let ranked = StarGain.rank(rows, delta: \.delta, range: .thisWeek)

        // 增量与总量**单位不同**，混排会得出「每周 +5 的 3 星仓库压过 20 万星成熟仓库」这种错序，
        // 所以分组而不是并进一个键。
        #expect(ranked.map(\.name) == ["delta500", "delta100", "noBaselineBig", "noBaselineSmall"])
    }

    @Test("增量相同时**保持原有顺序** —— 否则列表会在两次刷新之间无理由地抖动")
    func tiesKeepOriginalOrder() {
        let rows = [Row(name: "a", delta: 100), Row(name: "b", delta: 100), Row(name: "c", delta: 100)]

        #expect(StarGain.rank(rows, delta: \.delta, range: .thisWeek).map(\.name) == ["a", "b", "c"])
        // 反着传，结果也应反着 —— 证明靠的是"原序"而不是固定的名字顺序
        let reversed = [Row(name: "c", delta: 100), Row(name: "b", delta: 100), Row(name: "a", delta: 100)]
        #expect(StarGain.rank(reversed, delta: \.delta, range: .thisWeek).map(\.name) == ["c", "b", "a"])
    }

    @Test("系数只缩放数值：`今天` 档把 5 与 7 都压成 1 ⇒ 平手，原序生效")
    func scaleCanCollapseOrder() {
        let rows = [Row(name: "five", delta: 5), Row(name: "seven", delta: 7)]

        // 本周：7 > 5，顺序翻过来
        #expect(StarGain.rank(rows, delta: \.delta, range: .thisWeek).map(\.name) == ["seven", "five"])
        // 今天：both → max(1, 1) 与 max(1, 0.71→1) ⇒ 平手 ⇒ 保持原序
        #expect(StarGain.rank(rows, delta: \.delta, range: .today).map(\.name) == ["five", "seven"])
    }

    @Test("空列表不崩 —— 首屏加载前会传进来")
    func emptyInput() {
        #expect(StarGain.rank([Row](), delta: \.delta, range: .thisWeek).isEmpty)
    }
}
