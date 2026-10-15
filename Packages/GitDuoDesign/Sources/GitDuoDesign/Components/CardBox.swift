import SwiftUI

/// 列表条目 / 内容块的**容器**（原型 `styles/03-components.css` 的 `.card`）。
///
/// ```css
/// /* 2026-10-15 方案 A 起（走查第 76 条）—— 卡片容器**恢复形状**：
///    白面 + 大圆角 18 + 内边距 14，**不画边框**（靠「页面浅灰 vs 卡面白」的明度差）；
///    卡与卡之间 10px 间距，hairline 只留在**卡内**行之间。 */
/// .card{background:var(--card);border:none;border-radius:18px;padding:14px;margin:0}
/// .card+.card{margin-top:10px}
/// ```
///
/// ## 方案 A：它又是「卡」了（与方案 D 相反）
///
/// 页面底转回浅灰（走查第 76 条）后，层次回到「灰底 vs 白卡」的明度差：
/// 本件画**白面 + 圆角 18 + 内边距 14**，**不画边框**。
/// **内容块**（README / 热力图 / 气泡）走 `PanelBox`（同形状，语义不同）。
///
/// ⚠️ 方案 D 那版把它去形（无底/无框/无圆角、行间 hairline 通栏），
/// 本条只把"形状"翻回来；**内嵌 hairline 那套机制保留** —— 它现在服务的是
/// "**卡内**的行"（置顶 / 最近访问 / 菜单 / 搜索结果），不再是"条目之间"。
///
/// ## 相邻 hairline 由**调用方**决定（`showsTopSeparator`）
///
/// 原型的 `.menu-item+.menu-item` / `.recent-row+.recent-row` 是相邻兄弟选择器
/// —— 第一行不画。组件不知道自己在不在首位（`ForEach` 里判断"是不是第一个"
/// 的依据调用方最清楚），所以由调用方传 `index > 0` —— 沿 `MenuRow` /
/// `LinkRow` 的 `showsSeparator` 同一条处置，线画在**顶上**（原型如此）。
///
/// ⚠️ **方案 A 起列表条目不再传它**：条目各自是一张卡，卡与卡之间是**间距**不是线
/// （原型 `.card+.card{margin-top:10px}`）。传了就会在白卡顶上多画一条线。
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
    ///   - vertical: 方案 A 的 `.card{padding:14px}` —— 纵向 14。
    ///   - horizontal: 同上，横向 14（卡内的左右留白；**行容器传 0**，由行自己给 14）。
    ///   - showsTopSeparator: 卡**内**相邻行的 hairline —— **第一行传 `false`**。
    ///     ⚠️ 独立成卡的列表条目不要传（卡间是间距，不是线）。
    public init(
        vertical: CGFloat = 14,
        horizontal: CGFloat = 14,
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
        // 方案 A（2026-10-15，走查第 76 条）：白面 + 大圆角，不画边框 ——
        // 卡片靠「页面浅灰 vs 卡面白」的明度差立起来（原型 `.card{background:var(--card);
        // border:none;border-radius:18px}`）。
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous)
                .fill(Theme.Palette.surface)
        )
        // ⚠️ 卡内行的 hairline 是**通栏到卡的右缘**的（`Rectangle` 铺满宽度再 `padding(.leading)`），
        // 不裁的话会在圆角外露出两个直角的小尖。行容器（`vertical/horizontal: 0`）尤其明显。
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
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
    VStack(spacing: 10) {
        // 方案 A：条目各自成卡，卡间是 10 的间距、不画线。
        CardBox {
            Text("语言构成")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        CardBox(vertical: 0, horizontal: 0) {
            VStack(spacing: 0) {
                // 卡内的行：顶上一条内嵌 hairline（第一行不画）。
                CardBox(vertical: 14, horizontal: 14, showsTopSeparator: false) {
                    Text("置顶 · my-git/gitduo")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                CardBox(vertical: 14, horizontal: 14, showsTopSeparator: true) {
                    Text("置顶 · vercel/next.js")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
            }
        }
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
