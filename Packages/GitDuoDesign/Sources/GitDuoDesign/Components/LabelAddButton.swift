import SwiftUI

/// 虚线「＋ 标签 / 新建」按钮 —— 原型 `styles/03-components.css` 第 58 行的 `.lbl-add`（PRD §4.10）。
///
/// ```css
/// .lbl-add{border:1px dashed var(--link);color:var(--link);background:transparent;
///          border-radius:20px;font-size:11.5px;font-weight:600;padding:3px 10px}
/// ```
///
/// ## 它和 `LabelPill` 并排站在同一行
///
/// 新建 Issue 页的标签区是：**已选标签（`.lbl-tag`）× N + 这一颗**。
/// 两者几何几乎一样（胶囊、11pt 档、横向内边距 9 与 10），差的正是**语义**：
/// 实心 = 一个已经选上的标签；虚线圈 = **这里还能加东西**。
/// 所以它宁可单独一件，也不做成 `LabelPill` 的一个 `Style` ——
/// 那会让"这颗是可点的、那颗不是"这件事只体现在一个枚举分支里。
///
/// ## 为什么是"虚线"而不是一个深色按钮
///
/// 它在视觉权重上必须**低于**旁边的实心标签：标签是内容，它是入口。
/// 用实心强调色按钮会和标签抢眼，用灰字又像"不可点"——虚线描边正好是
/// "这里空着、可以往里放"的既有词汇（`EmptyBox` 用的是同一个）。
///
/// ## 两处数值说明
///
/// | 项 | 出处 |
/// |---|---|
/// | 字号 11.5px | 落到 `.caption2`(11) + semibold ⇒ 复用 `Font.tag`。⚠️ 旁边的 `.lbl-tag` 是 11px，两者**有意同档**：差 0.5px 肉眼不可见，而并排的两颗胶囊字号不一致反而看得出来 |
/// | 虚线的 dash 图案 | ⚠️ CSS 的 `dashed` **不给具体图案**（由浏览器按边框宽度自定）⇒ 「规格未给」。取 `[4, 4]`，与 `EmptyBox` 的 `.empty-box{border:1px dashed}` 用同一个（同一份原型里两处同类边框，没理由画成两种虚线） |
///
/// ## 判据 #43：它进设计包
///
/// 只收 `title: String` + 一个闭包，**不认识** `Label` 或"已选集合"。
/// 文案由调用方给（`IssueCopy.addLabelAction`）。
///
/// ## 它是内容层
///
/// **透明底 + 描边，不加 Liquid Glass**（§10.2）。
public struct LabelAddButton: View {

    public let title: String

    public let action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                // 原型 11.5px/600 ⇒ `.caption2`(11) + semibold = `Font.tag`。
                .font(Theme.Font.tag)
                .foregroundStyle(Theme.Palette.accent)
                // 原型 `padding:3px 10px`（3 不在 4pt 阶里 ⇒ 写原值）。
                .padding(.vertical, 3)
                .padding(.horizontal, 10)
                .background(
                    // 原型 `border-radius:20px` + `background:transparent`
                    // ⇒ 胶囊描边、不填底。
                    Capsule().strokeBorder(
                        Theme.Palette.accent,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    // 与 `LabelPill` 并排——这就是它在页面上的真实上下文。
    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
        FlowLayout {
            LabelPill(name: "bug", colorHex: "d73a4a")
            LabelPill(name: "docs", colorHex: "0075ca")
            LabelAddButton(title: "＋ 标签 / 新建") {}
        }
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
