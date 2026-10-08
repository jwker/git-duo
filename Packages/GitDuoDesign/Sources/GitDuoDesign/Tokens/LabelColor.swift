import SwiftUI

/// **服务端给的标签色值 → `Color`** 的唯一转换处。
///
/// ## 为什么需要一个专门的地方
///
/// 本包其余所有颜色都必须走 `Theme` 的语义令牌 —— `Color(hex:)` 甚至**故意不是 `public`**，
/// 业务代码拿不到它，于是写不出内联色值（§10.7 在类型系统上的那道防线）。
/// 标签色是这个规矩的**唯一例外**：颜色由**服务端数据**决定（仓库自定义标签可以有任意颜色），
/// 编译期不可能有令牌。
///
/// 例外必须收口，否则"补 `#`、判大小写、非法值怎么办"这三件事会在
/// 标签胶囊 / 色块 / 小圆点三处各写一遍 —— 而它们分叉时不会报错，
/// 只会让**同一个标签在两个页面上显示成不同颜色**。
///
/// ## 两种写法都收
///
/// | 来源 | 形态 | 例 |
/// |---|---|---|
/// | `GET /repos/{o}/{r}/labels` | **不带** `#` | `d73a4a` |
/// | 原型 CSS（`style="background:#…"`） | **带** `#` | `#d73a4a` |
///
/// 两侧都得认：领域层存的是不带 `#` 的那一版（发请求要的就是它），
/// 而原型 / 调试时抄过来的是带 `#` 的那一版。**大小写也照收**（服务端小写，手抄常常大写）。
///
/// ## 读不出来 ⇒ `nil`，**不编一个颜色**
///
/// 返回 `Color?` 而不是"给个灰色兜底"：这一步是**纯解析**，
/// "兜底画成什么样"是**视觉决策**，属于调用方（`LabelPill` / `ColorSwatch` 用
/// `Theme.Palette.labelFallbackSurface`）。两者混在一起的话，
/// 将来想换个兜底表象就得改这个纯函数，而它的测试会跟着一起动。
public enum LabelColor {

    /// 六位十六进制 → `Color`。带不带 `#` 都收、大小写都收；**不是六位十六进制 ⇒ `nil`**。
    ///
    /// ⚠️ **不收三位缩写**（`#abc`）：GitHub 的 `color` 字段是六位，三位只可能来自
    /// 拼错或手造数据。悄悄展开它会让"这个值有问题"这件事永远不被发现。
    ///
    /// 首尾空白会被剪掉（避免 `"d73a4a\n"` 这种从日志里抄出来的值直接判非法）。
    public static func color(forHex hex: String) -> Color? {
        guard let value = value(forHex: hex) else { return nil }
        return Color(hex: value)
    }

    /// 解析到的那 24 位整数（`0xRRGGBB`）。解析的**唯一实现**，`color(forHex:)` 只是包一层。
    ///
    /// 独立出来是为了让"收哪些写法"这条规则**只有一处**：
    /// 将来若真需要用到数值本身（例如算底色亮度），不必再写一遍判断。
    public static func value(forHex hex: String) -> UInt32? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        // `UInt32(_:radix:)` 本身对大小写不敏感，且不接受 `0x` 前缀（那会让 `0x1234` 也过 —— 六位）。
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return value
    }

    /// 服务端色值 → 画得出来的颜色，**保证非空**：读不出来就用兜底填充。
    ///
    /// 这是三个组件实际要用的那一个 —— 它们都需要"一定有个颜色可画"。
    public static func surface(forHex hex: String) -> Color {
        color(forHex: hex) ?? Theme.Palette.labelFallbackSurface
    }
}
