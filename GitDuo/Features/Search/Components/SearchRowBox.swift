import SwiftUI
import GitDuoDesign

/// 搜索结果行的**内容布局** —— 原型 `styles/03-components.css` 的 `.sr-item` 里
/// 除"行容器"之外的那一半（`display:flex;align-items:center;gap:11px`）。
///
/// ```css
/// .sr-item{display:flex;align-items:center;gap:11px;padding:12px 2px;position:relative}
/// .sr-item+.sr-item::before{content:"";position:absolute;top:0;left:45px;right:0;
///                           height:1px;background:var(--border-soft)}
/// ```
///
/// ## ⚠️ 2026-10-16 起它**不再是按钮、不再画分隔线**（NATIVE-MIGRATION P3）
///
/// 从前它是"整行 `Button(.plain)` + `padding(14)` + 顶上一条内嵌 hairline"。
/// 搜索页主干换成 `List` 之后，这三样**都是列表行的既有机制** ⇒ 全部撤掉：
/// - 内边距 / 行底 → `List` 的行内边距与 `.listRowBackground`
/// - 分隔线（含 45 / 57 两档内嵌缩进）→ 系统分隔线
/// - 点击与跳转 → `List` 行上的 `Button` + `.buttonStyle(.plain)`（整行可点、按下高亮；
///   系统箭头不再画，与首页 / 仓库 / 探索三页列表行的观感统一，见 `SearchView.resultRow`）
///
/// ⇒ 本件只剩一件事：**把这一行的内容按 `.sr-item` 的间距摆开**。
/// 五种行（最近搜索 + 四种结果）共用它，间距只有一处定义。
///
/// ## ⚠️ 它与 `LinkRow`（`.file-row`）**不是**同一个东西，别合并
///
/// | | `.sr-item` | `.file-row` |
/// |---|---|---|
/// | 间距 | 11 | 11 |
/// | 图标 | 16×16 / 头像 32 | 17×17 + `frame(width:20)` |
///
/// 原型里它们是两个独立的类，所以这里也是两个独立的东西。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
struct SearchRowBox<Content: View>: View {

    /// 垂直对齐。代码结果行用 `.top`（原型那行是 `align-items:flex-start`）——
    /// 它的副标题与预览行会把高度撑起来，图标居中就会浮在中间而不是贴着标题。
    let alignment: VerticalAlignment

    private let content: Content

    init(
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 11) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // ⚠️ 让整行矩形（含 `Spacer`/图标与文字之间的空白）都成为命中区，
        //    否则 `Button` 只认子视图几何并集，行内空白点不动。
        .contentShape(Rectangle())
    }
}
