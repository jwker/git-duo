import SwiftUI

/// 筛选 chip —— 探索页那两个「日期 / 语言」按钮（原型 `styles/03-components.css` 的 `.fchip`）。
///
/// ```css
/// .fchip{display:inline-flex;align-items:center;gap:5px;font-size:12px;font-weight:600;
///        padding:6px 12px;border:1px solid var(--border);border-radius:20px;
///        background:var(--card);color:var(--text)}
/// .fchip.on{border-color:var(--link);color:var(--link);background:#f0f6ff}
/// ```
///
/// ## 三处颜色同时变，这是"已选"的全部表达
///
/// 未选：白底 + 中性边 + 正文色，看起来像"一个还没填的占位"。
/// 已选：浅蓝底 + 强调边 + 强调字。**三处一起换**是有意的 ——
/// 只换边框在窄屏上太弱（1pt 的线），只换文字又容易和"禁用"混淆。
///
/// ## 它不认识"选了没有"
///
/// 收 `title` 与 `isHighlighted`，不收 `ExploreFilters`：设计包不依赖领域层（§3），
/// 而"该显示占位词还是选中值"是 `ExploreFilters.rangeChipLabel` 的事。
///
/// ## 它是内容层
///
/// 两个 chip 嵌在探索页的滚动内容里，**实色，不加 Liquid Glass**（§10.2）。
public struct FilterChip: View {

    public let title: String
    public let isHighlighted: Bool

    /// 是否显示右侧的下拉尖角。原型两个 chip 都显示；留成参数是因为
    /// 将来可能出现"点了立即生效、不打开弹层"的 chip。
    public let showsChevron: Bool

    public let action: () -> Void

    public init(
        title: String,
        isHighlighted: Bool,
        showsChevron: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isHighlighted = isHighlighted
        self.showsChevron = showsChevron
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .font(Theme.Font.label)
            .foregroundStyle(isHighlighted ? Theme.Palette.accent : Theme.Palette.textPrimary)
            // 6 / 12 是原型原值（`padding:6px 12px`）。
            .padding(.vertical, 6)
            .padding(.horizontal, Theme.Spacing.m)
            .background(
                // 方案 D（2026-10-15，走查第 73 条）：未选档白卡 → 浅灰面（原型
                // `.fchip{background:var(--chip);border:1px solid transparent}`）。
                Capsule().fill(isHighlighted ? Theme.Palette.accentSurface : Theme.Palette.surfaceSunken)
            )
            .overlay(
                // 原型 `border-radius:20px` 在 26pt 高的 chip 上就是胶囊。
                // 未选档的边框是**透明的**（占位但不画）—— 已选档仍靠"底 + 边 + 字"
                // 三处一起换表达"已选"。
                Capsule().stroke(
                    isHighlighted ? Theme.Palette.accent : Color.clear,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isHighlighted ? "\(title)，已筛选" : title)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    HStack(spacing: Theme.Spacing.s) {
        FilterChip(title: "本周", isHighlighted: true) {}
        FilterChip(title: "语言", isHighlighted: false) {}
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
