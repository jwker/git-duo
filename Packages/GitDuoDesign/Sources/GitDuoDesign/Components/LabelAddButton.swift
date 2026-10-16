import SwiftUI

/// 标签行末尾那颗「＋ 标签 / 新建」按钮 —— 原型 `styles/03-components.css` 第 58 行的
/// `.lbl-add`（PRD §4.10）。
///
/// ## 它和 `LabelPill` 并排站在同一行
///
/// 新建 Issue 页的标签区是：**已选标签（`.lbl-tag`）× N + 这一颗**。
/// 两者几何几乎一样（胶囊、11pt 档），差的正是**语义**：
/// 实心 = 一个已经选上的标签；这颗 = **这里还能加东西**。
/// 所以它宁可单独一件，也不做成 `LabelPill` 的一个 `Style` ——
/// 那会让"这颗是可点的、那颗不是"这件事只体现在一个枚举分支里。
///
/// ## ⚠️ 2026-10-16（P2）：外观换成官方的 `.bordered` 小胶囊按钮
///
/// 口径见 `NATIVE-MIGRATION.md`：**「按原型」= 功能按原型，视觉正本 = Apple HIG**。
/// 原型那套「虚线描边 + 蓝字」已经作废 —— 虚线是 CSS 时代的表达，
/// 系统件里"这里还能加东西、且点得动"由 `.bordered` 承担
/// （虚线在官方控件里没有对应档，且它本身就与"不可用"的观感相邻）。
///
/// 留下的两条结论仍然成立：
///
/// 1. 它在视觉权重上**低于**旁边的实心标签（`.small` + 次要按钮样式）；
/// 2. 文案**由调用方给**（`IssueCopy.addLabelAction`，本身已含 `＋`）——
///    这里不再补一个 `Image(systemName: "plus")`，否则屏幕上会出现两个加号。
///
/// ## 判据 #43：它进设计包
///
/// 只收 `title: String` + 一个闭包，**不认识** `Label` 或"已选集合"。
///
/// ## 它是内容层
///
/// **不加 Liquid Glass**（§10.2）。
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
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        // 它要能塞进标签行、不与实心标签抢眼 ⇒ 小号。
        .controlSize(.small)
        .tint(Theme.Palette.accent)
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
