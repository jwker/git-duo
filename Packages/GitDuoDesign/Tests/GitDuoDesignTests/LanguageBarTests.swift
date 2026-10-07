import SwiftUI
import Testing

@testable import GitDuoDesign

/// 占比条的分段宽度换算（TECH_SPEC §9.11）。
///
/// 为什么值得单独测：色带由若干 `Rectangle` 拼成，若每段各算一次
/// `总宽 × 百分比 ÷ 100`，各段之和会因浮点舍入与总宽差上零点几个点 ——
/// 于是**深色段之间露出一条头发丝宽的背景色缝隙**，看起来像"语言之间还有别的语言"。
/// 让最后一段吃掉余数即可严丝合缝，而这件事只能靠断言确认（肉眼量不出 0.4pt）。
@Suite("LanguageBar · 分段宽度")
struct LanguageBarTests {

    @Test("空输入 ⇒ 空数组（与 `LanguageComposition` 的空态口径一致）")
    func emptyProducesNothing() {
        #expect(LanguageBar.segmentWidths(percents: [], total: 300).isEmpty)
    }

    @Test("单段独占整条色带")
    func singleSegmentFillsTheBar() {
        #expect(LanguageBar.segmentWidths(percents: [100], total: 320) == [320])
    }

    @Test("原型那一组：72 / 18 / 10 在 320pt 上拼满，零缝隙")
    func prototypeSharesTileExactly() {
        let widths = LanguageBar.segmentWidths(percents: [72, 18, 10], total: 320)

        #expect(widths.reduce(0, +) == 320)
        #expect(widths == [230, 58, 32])
    }

    @Test("⚠️ 均分三段时最后一段吃掉舍入余数 —— 各段之和恒等于总宽")
    func equalThirdsStillTileExactly() {
        let widths = LanguageBar.segmentWidths(percents: [34, 33, 33], total: 300)

        #expect(widths == [102, 99, 99])
        #expect(widths.reduce(0, +) == 300)
    }

    @Test(
        "任何百分比组合下，各段宽度之和都恰等于总宽（含非整数总宽）",
        arguments: [[100], [50, 50], [34, 33, 33], [72, 18, 10], [1, 99], [90, 9, 1], [25, 25, 25, 25]]
    )
    func widthsAlwaysSumToTotal(_ percents: [Int]) {
        for total in [CGFloat(300), 320, 345.5, 128] {
            let widths = LanguageBar.segmentWidths(percents: percents, total: total)
            #expect(widths.count == percents.count)
            #expect(widths.reduce(0, +) == total, "percent=\(percents) total=\(total)")
            #expect(widths.allSatisfy { $0 >= 0 })
        }
    }
}
