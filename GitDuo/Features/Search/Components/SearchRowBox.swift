import SwiftUI
import GitDuoDesign

/// 搜索结果行的**容器** —— 原型 `styles/03-components.css` 的 `.sr-item`。
///
/// ```css
/// /* 2026-10-15 方案 D 起（走查第 73 条）：行间 hairline 内嵌缩进（相邻兄弟选择器） */
/// .sr-item{display:flex;align-items:center;gap:11px;padding:12px 2px;position:relative}
/// .sr-item+.sr-item::before{content:"";position:absolute;top:0;left:45px;right:0;
///                           height:1px;background:var(--border-soft)}
/// ```
///
/// ## 为什么它值得抽出来
///
/// 搜索页有**五种**行共用这一个容器：最近搜索 + 四种结果行（仓库 / 用户 / 代码 / 会话）。
/// 五处各抄一遍"间距 11、内嵌 hairline"，迟早有一处写成别的值或漏掉分隔线
/// —— 而那种偏差单看一行很难发现。
///
/// ## ⚠️ 它与 `LinkRow`（`.file-row`）**不是**同一个东西，别合并
///
/// | | `.sr-item` | `.file-row` |
/// |---|---|---|
/// | 间距 | 11 | 11 |
/// | 内边距 | `12px 2px` | `11px 4px` |
/// | 图标 | 16×16 / 头像 32 | 17×17 + `frame(width:20)` |
///
/// 差 1–2pt。原型里它们是两个独立的类，所以这里也是两个独立的东西
/// （沿 `CardBox` 的说明：本容器只服务 `.sr-item` 这一族，不承担统一全项目行距的职责）。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
struct SearchRowBox<Content: View>: View {

    /// 垂直对齐。代码结果行用 `.top`（原型那行是 `align-items:flex-start`）——
    /// 它的副标题与预览行会把高度撑起来，图标居中就会浮在中间而不是贴着标题。
    let alignment: VerticalAlignment

    /// 是否画顶部分隔线。原型的规则是"相邻兄弟之间画"（首条不画），
    /// 组件不知道自己在不在首位，所以由调用方传 —— 那正是它已经知道的事。
    let showsSeparator: Bool

    /// 分隔线的**左缩进**。默认 57 = 卡内边距 14 + 头像 32 + gap 11（原型 `left:57px`）。
    ///
    /// ⚠️ 搜索历史那几行的图标是 **16pt 线稿**（不是 32pt 头像）⇒ 传 45。
    /// 原型对这一支单给 `--inset:41px`（它的图标 16 不带槽），App 的图标槽是 20 ⇒ 45。
    let separatorInset: CGFloat

    let action: () -> Void

    private let content: Content

    init(
        alignment: VerticalAlignment = .center,
        showsSeparator: Bool,
        separatorInset: CGFloat = 57,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.showsSeparator = showsSeparator
        self.separatorInset = separatorInset
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: alignment, spacing: 11) {
                content
            }
            // 方案 A（2026-10-15，走查第 76 条）：行回到**卡内** ⇒ padding 14
            //（原型 `.sr-item{padding:14px}`）。
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if showsSeparator {
                Rectangle()
                    .fill(Theme.Palette.borderSoft)
                    .frame(height: 1)
                    // hairline 内嵌缩进，从文字/头像起点起，不再通栏。
                    // 原型固定 `left:57px`（卡内边距 14 + 头像 32 + gap 11）；
                    // 搜索历史那几行是 16pt 线稿图标 ⇒ 单给 `left:41px`（14+16+11）。
                    .padding(.leading, separatorInset)
            }
        }
    }
}
