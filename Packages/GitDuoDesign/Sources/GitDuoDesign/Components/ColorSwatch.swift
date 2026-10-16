import SwiftUI

/// 选色色块 —— 原型 `styles/03-components.css` 第 60–61 行的 `.clr-swatch`（PRD §5.2）。
///
/// ```css
/// .clr-swatch{width:30px;height:30px;border-radius:9px;cursor:pointer;border:2px solid transparent}
/// .clr-swatch.on{border-color:var(--text);box-shadow:inset 0 0 0 2px #fff}
/// ```
///
/// ## 选中态是**两层**，不是一层
///
/// 未选中：30×30 的圆角色块 + 一圈 **2px 透明**描边（占位，所以选中时尺寸不跳）。
/// 选中：那圈描边变成 `Color.primary`（深），**再往内加一圈 2px 白环**。
///
/// ⚠️ 两层都要画。只画深色描边的话，选中态在一排彩色方块里**几乎看不出来**
/// —— 描边紧贴着色块，四周又都是别的彩块。中间那圈白是让它"浮起来"的那一笔。
/// 而只画白环不画深边则在白底上完全消失（白压白）。
///
/// ⚠️ 透明描边**不能省**：省掉它，未选中的是 30×30、选中的是 34×34，
/// 点一下整排色块会互相挤动 —— 这正是原型用 `border:2px solid transparent` 而不是
/// `border:none` 的原因。
///
/// ## ⚠️ 2026-10-16（P2）：本件**有意保留自绘**
///
/// `NATIVE-MIGRATION.md` 曾把本件标成"→ `Button` + `.bordered` + `.overlay`"，
/// 实做时否掉了：这里的 label **不是按钮外观，是一个色块本身** ——
/// 套上 `.bordered`（系统灰底 + 圆角矩形 + 内边距）会让它从一个 30×30 的色样
/// 变成一颗"里面有个色块的按钮"，而这一整屏要读的正是**颜色本身**。
///
/// ⇒ `.buttonStyle(.plain)` 在这一处是**正确的选择**（这正是"逐处判读 30 处 plain"
/// 的产出之一：plain 不是遗留问题，它在"label 即内容"的地方就是对的）。
///
/// 变的只有一处：选中态的深色描边从 `Theme.Palette.textPrimary` 换成 **`Color.primary`**
/// —— 系统语义色，深浅色与"提高对比度"辅助功能自动生效，语义也更准
/// （它不是"正文色"，是"前景色"）。
///
/// ## 判据 #43：它进设计包
///
/// 只收 `colorHex: String` + `isSelected: Bool` + 一个闭包，**不认识** `Label` 或色板。
/// "一共有几档、档位是什么"是 `LabelPalette` 的事（领域层），这里只画一格。
///
/// ## 它是导航/操作层里的**内容**
///
/// 色块本身**实色，不加 Liquid Glass**（§10.2），它嵌在弹层的滚动内容里。
public struct ColorSwatch: View {

    /// 服务端给的色值，**六位十六进制、带不带 `#` 都行**。
    public let colorHex: String

    public let isSelected: Bool

    public let action: () -> Void

    public init(colorHex: String, isSelected: Bool, action: @escaping () -> Void) {
        self.colorHex = colorHex
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(LabelColor.surface(forHex: colorHex))
                .frame(width: Self.diameter, height: Self.diameter)
                // 内白环（原型 `box-shadow:inset 0 0 0 2px #fff`）。
                // `.padding(2)` 把它推到深色描边的**内侧** —— 不推的话两圈会重叠在同一圈上。
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .strokeBorder(Theme.Palette.surface, lineWidth: Self.borderWidth)
                            .padding(Self.borderWidth)
                    }
                }
                // 深色描边（原型 `border:2px solid var(--text)`）。
                // ⚠️ 未选中时画的是**透明**描边，不是不画 —— 尺寸必须一致。
                // 2026-10-16（P2）：色值换成系统语义色 `Color.primary`（见类型说明）。
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.primary : Color.clear,
                            lineWidth: Self.borderWidth
                        )
                }
        }
        .buttonStyle(.plain)
        // 读屏不能只念一串十六进制 —— 它要说出"这是什么、选了没有"。
        // 句式与 `FilterChip` 的「\(title)，已筛选」一致（同一个设计包里的惯例）。
        .accessibilityLabel(isSelected ? "色值 \(colorHex)，已选中" : "色值 \(colorHex)")
        .accessibilityAddTraits(.isButton)
    }

    /// 原型 `.clr-swatch{width:30px;height:30px}`。
    public static let diameter: CGFloat = 30

    /// 原型两处的描边宽度（`border:2px` 与 `inset … 2px`）。
    public static let borderWidth: CGFloat = 2
}

#Preview {
    let hexes = [
        "d73a4a", "bc4c00", "9a6700", "0e8a16", "0075ca",
        "5319e7", "8250df", "bf3989", "6a737d", "1f2328",
    ]
    return VStack(alignment: .leading, spacing: Theme.Spacing.l) {
        // 一排十档，第 3 格选中（原型 `clrRow` 的排布）。
        FlowLayout(spacing: Theme.Spacing.s, lineSpacing: Theme.Spacing.s) {
            ForEach(Array(hexes.enumerated()), id: \.offset) { index, hex in
                ColorSwatch(colorHex: hex, isSelected: index == 2) {}
            }
        }
        // 服务端给了个读不出来的色值 ⇒ 兜底填充。
        ColorSwatch(colorHex: "", isSelected: false) {}
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.surface)
}
