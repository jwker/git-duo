import SwiftUI
import GitDuoDesign

/// 搜索结果行的**容器** —— 原型 `styles/03-components.css` 的 `.sr-item`。
///
/// ```css
/// .sr-item{display:flex;align-items:center;gap:11px;padding:11px 2px;
///          border-bottom:1px solid var(--border-soft);cursor:pointer}
/// .sr-item:last-child{border-bottom:none}
/// ```
///
/// ## 为什么它值得抽出来
///
/// 搜索页有**五种**行共用这一个容器：最近搜索 + 四种结果行（仓库 / 用户 / 代码 / 会话）。
/// 五处各抄一遍"间距 11、上下 11、左右 2、除末条外画一条 `borderSoft` 细线"，
/// 迟早有一处写成 4 或漏掉分隔线 —— 而那种偏差单看一行很难发现。
///
/// ## ⚠️ 它与 `LinkRow`（`.file-row`）**不是**同一个东西，别合并
///
/// | | `.sr-item` | `.file-row` |
/// |---|---|---|
/// | 间距 | 11 | 11 |
/// | 内边距 | `11px 2px` | `11px 4px` |
/// | 图标 | 16×16 | 17×17 + `frame(width:20)` |
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

    /// 是否画底部分隔线。原型的规则是"除最后一条之外都画"，
    /// 组件不知道自己在不在末位，所以由调用方传 —— 那正是它已经知道的事。
    let showsSeparator: Bool

    let action: () -> Void

    private let content: Content

    init(
        alignment: VerticalAlignment = .center,
        showsSeparator: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.showsSeparator = showsSeparator
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: alignment, spacing: 11) {
                content
            }
            // 11 / 2：原型原值（`padding:11px 2px`）。左右那 2pt 在 4pt 阶里
            // 就是 `Spacing.xxs`，不是魔法值。
            .padding(.vertical, 11)
            .padding(.horizontal, Theme.Spacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(Theme.Palette.borderSoft)
                    .frame(height: 1)
            }
        }
    }
}
