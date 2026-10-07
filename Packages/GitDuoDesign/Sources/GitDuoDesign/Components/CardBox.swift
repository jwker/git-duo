import SwiftUI

/// 内容卡片的**容器**（原型 `styles/03-components.css` 的 `.card`）。
///
/// ```css
/// .card{background:var(--card);border:1px solid var(--border-soft);
///       border-radius:14px;padding:14px}
/// ```
///
/// ## 为什么值得单独抽一个容器
///
/// 探索仓库详情（§4.13）里有 4 张卡（语言构成 / Latest Release / 参与协作 / 贡献者），
/// 两个列表页里每张 Issue·PR 卡也是同一个形状。把「白底 + 1pt 浅边 + 14pt 圆角」
/// 抄五遍，就会有一遍写成 `Radius.card`（10）或漏掉描边 ——
/// 而那种偏差在单张卡上很难看出来。
///
/// ⚠️ `TrendCard`（趋势卡）、`PinCard`（置顶卡）、`RepoCard`（仓库行）**没有**改用本容器：
/// 它们的圆角在原型里就是另外两个值（趋势卡也是 14，但仓库行是 10）。
/// 本容器只服务"04-screens 那一族卡片"，不承担统一全项目圆角的职责 ——
/// 那需要另一次决议。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2 点名"仓库卡片"）。封装在这里，
/// 也就是把这条铁律钉在了一个地方：往卡片里加玻璃，只有这一处可加。
public struct CardBox<Content: View>: View {

    private let verticalPadding: CGFloat
    private let horizontalPadding: CGFloat
    private let content: Content

    /// - Parameters:
    ///   - vertical: 原型里这一族卡片有两种：`.card{padding:14px}`（趋势卡）
    ///     与详情页内联的 `padding:12px 14px`。默认取后者（12）——
    ///     详情页用了四次，而趋势卡自己有实现。
    ///   - horizontal: 原型两处都是 14。4pt 阶里没有这一档，写原值并注明出处。
    public init(
        vertical: CGFloat = Theme.Spacing.m,
        horizontal: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
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
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous)
                .stroke(Theme.Palette.borderSoft, lineWidth: 1)
        )
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.s) {
        CardBox {
            Text("语言构成")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        CardBox {
            Text("Latest Release")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
