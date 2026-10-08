import SwiftUI

/// 标签小色块 —— 原型 `styles/03-components.css` 第 59 行的 `.lbl-dot`（PRD §5.2 标签选择弹层）。
///
/// ```css
/// .lbl-dot{width:12px;height:12px;border-radius:4px;display:inline-block;flex:none}
/// ```
///
/// ## 它和 `ColorSwatch` 是同一族的两个尺寸
///
/// 两件都画"**服务端给的标签色**"，差别只在尺寸 / 圆角 / 有没有选中态：
///
/// | | `ColorSwatch` | `LabelDot` |
/// |---|---|---|
/// | 尺寸 | 30×30（原型 `.clr-swatch`） | **12×12**（原型 `.lbl-dot`） |
/// | 圆角 | 9（`Radius.control`） | **4**（`Radius.labelDot`） |
/// | 可点 | 是（选色） | **否**（纯展示，行本身才是按钮） |
/// | 选中态 | 有（深色描边 + 内白环） | 无 |
///
/// 合成一件要靠四个参数去表达差异，而其中两个（可点 / 选中态）在对方身上没有意义 ——
/// 那样调用方每次都要写 `isSelected: false, action: nil` 一堆与它无关的东西。
/// 两件的**共同点只有"取色"**，而那一点已经收口在 `LabelColor` 里了。
///
/// ## `flex:none` 是有意义的
///
/// 原型写了 `flex:none` —— 它是行首的一个定宽装饰，**不许被行里的长名字压扁**。
/// 本仓对应的是 `.fixedSize()`：不加的话，一个很长的标签名会把这个 12×12 压成 6×12 的竖条。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct LabelDot: View {

    /// 服务端给的色值，**六位十六进制、带不带 `#` 都行**。
    public let colorHex: String

    public init(colorHex: String) {
        self.colorHex = colorHex
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.labelDot, style: .continuous)
            .fill(LabelColor.surface(forHex: colorHex))
            .frame(width: Self.diameter, height: Self.diameter)
            // 原型 `flex:none`：行里的长标签名不许把它压扁。
            .fixedSize()
            // 它纯粹是"名字旁边的一个颜色样本"，读屏念两遍没有意义
            // —— 标签名由同一行的那段文字负责念。
            .accessibilityHidden(true)
    }

    /// 原型 `.lbl-dot{width:12px;height:12px}`。
    public static let diameter: CGFloat = 12
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
        ForEach(["d73a4a", "bc4c00", "9a6700", "0e8a16", "0075ca"], id: \.self) { hex in
            HStack(spacing: Theme.Spacing.s) {
                LabelDot(colorHex: hex)
                Text("标签 \(hex)").font(Theme.Font.rowTitle)
            }
        }
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.surface)
}
