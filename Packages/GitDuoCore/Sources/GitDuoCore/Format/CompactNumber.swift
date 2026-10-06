import Foundation

/// 大数的紧凑写法 —— `124_000 → "124k"`（PRD §3.1：Star / Fork 数"显示为字符串，大数可缩写"）。
///
/// 依据：TECH_SPEC §2.2（`GitDuoCore` 负责"格式化"）、PRD §4.3 卡片内容。
///
/// ## 规则（原型只给了样例，没有给规则，这里把它定下来并测住）
///
/// | 区间 | 写法 | 例 |
/// |---|---|---|
/// | `< 1000` | 原样 | `999` |
/// | `1000 ..< 1_000_000` | 一位小数 + `k`，整数则省掉小数位 | `1k` · `12.6k` · `124k` |
/// | `≥ 1_000_000` | 一位小数 + `m`，同上 | `1.5m` · `12m` |
///
/// ⚠️ **原型里的 `"98k"` 与本实现可能差一位**：原型那份是**手写的演示字符串**
///    （`scripts/01-data.js` 里 `s:"98k"`），不是算出来的。真实数据若为 98,200，
///    按本文规则得 `"98.2k"` —— 以本规则为准（原型给不出规则，只能给出风格）。
///    唯一确定的是**风格**：小写单位字母、最多一位小数、整数不显示 `.0`。
public enum CompactNumber {

    /// - Parameter count: Star / Fork 之类的计数。负值按 0 处理 ——
    ///   它不该出现，但真出现时显示 `-1k` 比显示 `0` 更让人困惑。
    public static func string(from count: Int) -> String {
        let value = max(0, count)

        if value < 1_000 {
            return String(value)
        }

        // 先按 k 归一；四舍五入后若跨到 1000k 就升到 m ——
        // 否则 999_999 会显示成 "1000k"。
        let thousands = rounded(Double(value) / 1_000)
        if thousands < 1_000 {
            return "\(literal(thousands))k"
        }
        return "\(literal(rounded(Double(value) / 1_000_000)))m"
    }

    /// 保留一位小数（四舍五入）。
    private static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// 整数不写 `.0`：`1.0k` 读起来像精度，而它并不存在。
    private static func literal(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
