import SwiftUI

/// 列表条目 / 内容块的**容器**（原型 `styles/03-components.css` 的 `.card`）。
///
/// ```css
/// /* 2026-10-15 方案 D 起（走查第 73 条）—— 卡片容器去形：
///    不再画白底 + 边框 + 圆角，条目直接坐在白底页面上，
///    行与行之间用 hairline 分隔（相邻兄弟选择器）。 */
/// .card{background:none;border:none;border-radius:0;padding:13px 2px;margin:0}
/// .card+.card{border-top:1px solid var(--border-soft)}
/// ```
///
/// ## 方案 D：它是「条目」，不再是「卡」
///
/// 白底页面上，层次靠**排版与 hairline** 表达（方案 D「分组平铺」）：
/// 本件只剩「内边距 + 相邻行之间的一条 hairline」。**内容面板**（README / 热力图 /
/// 气泡那类"浅灰面"）不要用它 —— 那一族是 `PanelBox`。
///
/// ## 相邻 hairline 由**调用方**决定（`showsTopSeparator`）
///
/// 原型的 `.card+.card` 是相邻兄弟选择器 —— 第一张卡不画。组件不知道自己在不在
/// 首位（`ForEach` 里判断"是不是第一个"的依据调用方最清楚），所以由调用方传
/// `index > 0` —— 沿 `MenuRow` / `LinkRow` 的 `showsSeparator` 同一条处置，
/// 只是方案 D 的 `.card` 把线画在**顶上**（原型如此）。
///
/// ## 为什么值得单独抽一个容器
///
/// 探索仓库详情（§4.13）里有 4 张卡（语言构成 / Latest Release / 参与协作 / 贡献者），
/// 两个列表页里每张 Issue·PR 卡也是同一个形状。把「内边距 13/2 + 相邻 hairline」
/// 抄十遍，就会有一遍写成别的值或漏掉线 —— 而那种偏差在单张条目上很难看出来。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2 点名"仓库卡片"）。
public struct CardBox<Content: View>: View {

    private let verticalPadding: CGFloat
    private let horizontalPadding: CGFloat
    private let showsTopSeparator: Bool
    private let content: Content

    /// - Parameters:
    ///   - vertical: 方案 D 的 `.card{padding:13px 2px}` —— 纵向 13（不在 4pt 阶里，写原值）。
    ///   - horizontal: 同上，横向 2（条目只缩进一点，行间 hairline 从页面内边距起通栏）。
    ///   - showsTopSeparator: 原型 `.card+.card{border-top:…}` —— 列表里**第一张传 `false`**。
    public init(
        vertical: CGFloat = 13,
        horizontal: CGFloat = 2,
        showsTopSeparator: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.verticalPadding = vertical
        self.horizontalPadding = horizontal
        self.showsTopSeparator = showsTopSeparator
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, horizontalPadding)
        .overlay(alignment: .top) {
            if showsTopSeparator {
                Rectangle()
                    .fill(Theme.Palette.borderSoft)
                    .frame(height: 1)
            }
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        CardBox(showsTopSeparator: false) {
            Text("语言构成")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        // 相邻条目：顶上一条 hairline（原型 `.card+.card`）。
        CardBox(showsTopSeparator: true) {
            Text("Latest Release")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
