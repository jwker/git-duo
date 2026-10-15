import Foundation

/// 千分位全量写法 —— `2341 → "2,341"`（TECH_SPEC §9.11：仓库头部的 Star / Watch / Fork 计数）。
///
/// ## 它为什么和 `CompactNumber` 并存，而不是合并成一个
///
/// 两处的**用途不同，且原型已经把它们分开了**：
///
/// | 位置 | 原型数据源 | 写法 |
/// |---|---|---|
/// | 仓库卡片（窄，要省宽度） | `scripts/01-data.js` 的 `REPOS` | `124k` · `26.8k` · `98k` |
/// | 仓库头部那三个统计数（用户要读准） | 同文件的 `TRENDING` | `2,341` · `11,240` |
///
/// 决定性的一行是 `kuda/ui-craft` 的 `s:"11,240"` —— 它**超过 1 万却仍是全量**，
/// 说明头部这一侧不是"数值小才碰巧没缩写"，而是**有意不缩写**。
/// 若把两者合并成一个函数，就必然有一侧要妥协。
///
/// ## 为什么不用 `NumberFormatter`
///
/// 它的分组符号随 `Locale` 变（德语/西班牙语把 `,` 用作**小数点**，分组符是 `.`）⇒
/// 同一份代码在不同系统语言下会显示成不同字符串，而"计数怎么显示"是**产品口径**、
/// 不该跟着手机语言漂移。更要紧的是测试：`NumberFormatter` 读进程级 locale，
/// 一个断言在不同机器上可能时而通过时而失败 —— 那种间歇失败的测试比没有测试更坏事。
/// 所以这里手写分组，**只认 ASCII 逗号**，与原型一致。
public enum GroupedNumber {

    /// - Parameter count: Star / Watch / Fork 之类的计数。
    ///   负值按 0 处理 —— 计数不该为负，真出现时显示 `-1` 比显示 `0` 更让人困惑
    ///   （与 `CompactNumber.string(from:)` 同一口径）。
    public static func string(from count: Int) -> String {
        let value = max(0, count)
        let digits = String(value)

        // 四位以下无需分组 —— 提前返回，省掉下面那次逐字符遍历与两次反转。
        guard digits.count > 3 else { return digits }

        var grouped = ""
        for (offset, digit) in digits.reversed().enumerated() {
            // `offset > 0` 是必要的：否则四位数的最高位前面会多一个逗号（`,2341`）。
            if offset > 0, offset.isMultiple(of: 3) { grouped.append(",") }
            grouped.append(digit)
        }
        return String(grouped.reversed())
    }
}
