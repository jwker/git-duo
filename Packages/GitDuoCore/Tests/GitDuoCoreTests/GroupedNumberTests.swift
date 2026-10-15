import Foundation
import Testing

@testable import GitDuoCore

/// 千分位全量写法（TECH_SPEC §9.11：仓库头部的 Star / Watch / Fork）。
///
/// 这组断言同时钉住两件事：
/// ① 分组本身对（尤其**四位数不能多一个前导逗号** —— 那种错在界面上很难一眼看出）；
/// ② 它与 `CompactNumber` **确实不是同一个函数** —— 两处口径有意不同（卡片缩写、头部全量），
///    哪天有人"顺手统一"了，这个断言会红。
@Suite("GroupedNumber · 千分位全量")
struct GroupedNumberTests {

    @Test(
        "四位以下原样输出",
        arguments: [(0, "0"), (7, "7"), (42, "42"), (999, "999")]
    )
    func belowThousandIsPlain(_ count: Int, _ expected: String) {
        #expect(GroupedNumber.string(from: count) == expected)
    }

    @Test(
        "⚠️ 四位数只在千位与百位之间加逗号 —— 不能出现前导逗号 `,2341`",
        arguments: [(1_000, "1,000"), (2_341, "2,341"), (9_999, "9,999")]
    )
    func thousandsHaveNoLeadingComma(_ count: Int, _ expected: String) {
        #expect(GroupedNumber.string(from: count) == expected)
        #expect(!GroupedNumber.string(from: count).hasPrefix(","))
    }

    @Test(
        "每三位一组，直到百万",
        arguments: [
            (11_240, "11,240"),        // 原型的 kuda/ui-craft —— 超过 1 万仍是全量
            (124_000, "124,000"),
            (999_999, "999,999"),
            (1_000_000, "1,000,000"),
            (98_200_000, "98,200,000"),
        ]
    )
    func groupsEveryThreeDigits(_ count: Int, _ expected: String) {
        #expect(GroupedNumber.string(from: count) == expected)
    }

    @Test("负值按 0 处理（与 CompactNumber 同一口径）")
    func negativeClampsToZero() {
        #expect(GroupedNumber.string(from: -1) == "0")
        #expect(GroupedNumber.string(from: -12_345) == "0")
    }

    @Test("⚠️ 与 CompactNumber 有意不同：同一个数在头部与卡片上是两种写法")
    func differsFromCompactNumberOnPurpose() {
        // 卡片（窄，要省宽度）→ 缩写
        #expect(CompactNumber.string(from: 124_000) == "124k")
        #expect(CompactNumber.string(from: 11_240) == "11.2k")
        // 头部那三个统计数（用户要读准）→ 全量
        #expect(GroupedNumber.string(from: 124_000) == "124,000")
        #expect(GroupedNumber.string(from: 11_240) == "11,240")
    }
}
