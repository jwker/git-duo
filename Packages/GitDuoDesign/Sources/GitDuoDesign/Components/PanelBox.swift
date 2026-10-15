import SwiftUI

/// **内容面板** —— 方案 D 里"嵌在页面里的浅灰面"那一族容器
/// （原型 `--chip` 面板：`.heatmap` / `.markdown` / `.pin-card` 等，2026-10-15 走查第 73 条）。
///
/// ```css
/// .heatmap{background:var(--chip);border:none;border-radius:14px;padding:14px}
/// .markdown{background:var(--chip);border:none;border-radius:12px;padding:16px}
/// ```
///
/// ## 方案 D 的两路分工
///
/// 白底页面上，「卡」拆成了两种表达：
///
/// | | 条目（`CardBox`） | 面板（本件） |
/// |---|---|---|
/// | 画什么 |什么都不画，行间 hairline | **一块浅灰面**（无边框） |
/// | 装什么 | 列表里的一行 / 一条 | 自成一块的内容：README、热力图、置顶卡、气泡… |
/// | 底色 | 无（坐在页面上） | `surfaceSunken`（`--chip`） |
///
/// 边框在两路上都**不存在**了 —— "面"本身就是形状，再包一圈线就回到了旧世界。
///
/// ## 圆角随原型逐处取值
///
/// 原型的面板圆角不是一个值（热力图 14 / markdown 12 / 置顶卡 12），所以收参数；
/// 默认取 `sheet`(14)（热力图那档）。
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
        cornerRadius: CGFloat = Theme.Radius.sheet,
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
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.Palette.surfaceSunken)
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
