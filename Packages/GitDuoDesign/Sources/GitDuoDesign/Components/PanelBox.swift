import SwiftUI

/// **内容面板** —— 自成一块的内容容器：README / 热力图 / 评论气泡 / 输入区
/// （原型 `.heatmap` / `.markdown` / `.comment .bubble` / `.composer`）。
///
/// ```css
/// /* 2026-10-15 方案 A 起（走查第 76 条）—— 面板与卡片同为「白面」 */
/// .heatmap{background:var(--card);border:none;border-radius:18px;padding:16px}
/// .markdown{background:var(--card);border:none;border-radius:18px;padding:16px}
/// ```
///
/// ## 方案 A：面板与卡片**同形状**，只是语义不同
///
/// 页面底转回浅灰（第 76 条）后，层次是「页面灰 → 卡面白 → 卡内控件灰」：
/// 面板和 `CardBox` 画的都是**白面 + 圆角 18**，靠内边距与语义分开 ——
/// 本件装"自成一块的内容"，`CardBox` 装"列表里的一条 / 一行"。
///
/// ⚠️ 方案 D 时两者是**对立**的（条目去形、面板灰面），本条把它们拉回同一形状；
/// 拆成两个类型是为了"这块是内容、那块是条目"这件事仍有个名字
/// （沿 `CardBox` 去形后留名的同一条理由）。
///
/// ## 圆角随原型逐处取值
///
/// 原型的面板圆角现在统一是 18（`Radius.cardLarge`），仍收参数是为了
/// 弹层里那些需要跟弹层同心的小面板（默认取 `cardLarge`）。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct PanelBox<Content: View>: View {

    private let cornerRadius: CGFloat
    private let verticalPadding: CGFloat
    private let horizontalPadding: CGFloat
    private let content: Content

    public init(
        cornerRadius: CGFloat = Theme.Radius.cardLarge,
        vertical: CGFloat = 14,
        horizontal: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.verticalPadding = vertical
        self.horizontalPadding = horizontal
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, horizontalPadding)
        .background(
            Theme.Palette.surface,
            in: .rect(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.m) {
        PanelBox {
            Text("贡献热力图那块的面")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        PanelBox(cornerRadius: Theme.Radius.bubble, vertical: 16, horizontal: 16) {
            Text("README 那块的面（radius 12 / padding 16）")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
