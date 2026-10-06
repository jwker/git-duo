import Foundation
import Testing

@testable import GitDuoCore

/// 大数紧凑写法（PRD §3.1）。
///
/// 边界值是重点：`999 / 1000` 与 `999_999 / 1_000_000` 这两处各错一位，
/// 就会得到 `1000k` 这种读起来很怪、但不会报错的显示。
@Suite("CompactNumber · 大数缩写")
struct CompactNumberTests {

    @Test(
        "小于 1000 原样输出 —— 不加千分位（原型里 128 个 Star 就是 128）",
        arguments: [(0, "0"), (1, "1"), (41, "41"), (999, "999")]
    )
    func belowThousandIsPlain(_ count: Int, _ expected: String) {
        #expect(CompactNumber.string(from: count) == expected)
    }

    @Test(
        "千位起用 k，整数省掉小数位",
        arguments: [
            (1_000, "1k"),
            (1_500, "1.5k"),
            (12_600, "12.6k"),
            (98_200, "98.2k"),
            (124_000, "124k"),
            (999_000, "999k")
        ]
    )
    func thousandsUseK(_ count: Int, _ expected: String) {
        #expect(CompactNumber.string(from: count) == expected)
    }

    @Test("⚠️ `999_999` 必须升成 `1m`，不能显示成 `1000k`（四舍五入后跨位）")
    func roundsUpAcrossUnitBoundary() {
        #expect(CompactNumber.string(from: 999_999) == "1m")
    }

    @Test(
        "百万起用 m",
        arguments: [(1_000_000, "1m"), (1_500_000, "1.5m"), (12_000_000, "12m")]
    )
    func millionsUseM(_ count: Int, _ expected: String) {
        #expect(CompactNumber.string(from: count) == expected)
    }

    @Test("`1000` 与 `999` 必须不同 —— 差一位就会有一批仓库显示成同一个数")
    func thousandBoundaryIsExact() {
        #expect(CompactNumber.string(from: 999) == "999")
        #expect(CompactNumber.string(from: 1_000) == "1k")
    }

    @Test("负值按 0 处理（不该出现，但出现时 `-1k` 比 `0` 更让人困惑）")
    func negativeIsClampedToZero() {
        #expect(CompactNumber.string(from: -5) == "0")
    }

    @Test("输出里不出现 `.0`：`1.0k` 读起来像有精度，而那位小数并不存在")
    func noTrailingZeroDecimal() {
        for count in [1_000, 2_000, 124_000, 1_000_000] {
            #expect(!CompactNumber.string(from: count).contains(".0"))
        }
    }
}
