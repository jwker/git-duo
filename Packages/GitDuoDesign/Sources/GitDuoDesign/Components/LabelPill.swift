import SwiftUI

/// 标签胶囊 —— 原型 `styles/03-components.css` 第 57 行的 `.lbl-tag`（PRD §4.10 / §5.2）。
///
/// ```css
/// .lbl-tag{display:inline-flex;align-items:center;font-size:11px;font-weight:600;
///          padding:2.5px 9px;border-radius:20px;color:#fff}
/// ```
///
/// ## 它长得像 `StatusPill`，但**不是**同一件
///
/// 几何完全一样（11pt / 2.5·9 / 胶囊），差在**三处**，每一处都不能靠 `StatusPill` 表达：
///
/// | | `StatusPill` | `LabelPill` |
/// |---|---|---|
/// | 底色 | 三族**状态色**之一（`Tone` 枚举） | **服务端给的颜色**，任意十六进制 |
/// | 边框 | `1px solid`（状态色同族） | **没有边框** |
/// | 文字 | 状态色（同族深色） | **一律白字** |
///
/// 所以它单独一件、**不复用 `StatusPill` 的 `Tone`**：那三档是"状态"的词汇，
/// 而这里是"用户自定义标签色"。硬塞进 `Tone` 会逼出第四个档位
/// （"自定义色"），而 `Tone` 的注释里刚写过"只有三族、不按单个状态命名"。
///
/// ## ⚠️ 白字的代价：浅色标签读不出来（**已登记**）
///
/// 原型写死 `color:#fff`。实测白字压在默认 10 色色板上：
///
/// | 色 | 对比度 | |
/// |---|---|---|
/// | `#9a6700` 黄 | 4.87:1 | 达标（门槛 4.5） |
/// | `#d73a4a` 红 | 4.57:1 | 达标 |
/// | `#0e8a16` 绿 | **4.50:1** | 贴线 |
///
/// 色板本身已按用户裁定换过一轮，十档全部 ≥ 4.5（见 `GitDuoKit.LabelPalette`）。
///
/// ⚠️ **但仓库里已存在的标签颜色不受此保护**：那是服务端数据，里面照样有浅色 ——
/// GitHub 默认的 `enhancement` 就是 `#a2eeef`，白字只有 **1.31:1**，标签名根本读不出来。
/// 要连它一起治好，只能**按底色亮度自动选黑/白字**，而那偏离原型 ⇒
/// 已登记为开放项（`TECH_SPEC §10.7` 切片 7 段），**未拍板前不擅自实现**。
///
/// ## 判据 #43：它进设计包
///
/// 只收 `name: String` + `colorHex: String` 两个基础类型，**不认识** `Label` 这个领域模型。
///
/// ## 它是内容层
///
/// 胶囊嵌在正文里，**实色，不加 Liquid Glass**（§10.2）。
public struct LabelPill: View {

    public let name: String

    /// 服务端给的色值，**六位十六进制、带不带 `#` 都行**（`LabelColor` 两个都收）。
    public let colorHex: String

    public init(name: String, colorHex: String) {
        self.name = name
        self.colorHex = colorHex
    }

    public var body: some View {
        Text(name)
            .font(Theme.Font.tag)
            // 原型 `color:#fff` —— 走令牌（`surface` 就是 `#FFFFFF`），不写内联色值。
            .foregroundStyle(Theme.Palette.surface)
            // 2.5 / 9 是原型原值（`padding:2.5px 9px`）—— 4pt 间距阶里没有这两档，
            // 故写原值并注明出处（与 `StatusPill` 逐字相同，两件的几何本来就是一回事）。
            .padding(.vertical, 2.5)
            .padding(.horizontal, 9)
            // 原型 `border-radius:20px` 在 11pt 的文字上就是胶囊的两端半圆。
            // ⚠️ 也**不画边框** —— `.lbl-tag` 与 `.pill` 的差别之一就是它没有 `border`。
            .background(LabelColor.surface(forHex: colorHex), in: .capsule)
            // 读屏把整颗胶囊念成一句；不带这一句，读屏只会念出标签名而说不出"这是个标签"。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("标签 \(name)")
    }
}

#Preview {
    // 十档全部来自 `GitDuoKit.LabelPalette.hexes`（这里手抄一份只为看效果）。
    let hexes = [
        "d73a4a", "bc4c00", "9a6700", "0e8a16", "0075ca",
        "5319e7", "8250df", "bf3989", "6a737d", "1f2328",
    ]
    return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
        FlowLayout {
            ForEach(Array(hexes.enumerated()), id: \.offset) { _, hex in
                LabelPill(name: hex, colorHex: hex)
            }
        }
        // 服务端给了个读不出来的色值 ⇒ 兜底填充（见 `Theme.Palette.labelFallbackSurface`）。
        LabelPill(name: "坏色值", colorHex: "nonsense")
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.surface)
}
