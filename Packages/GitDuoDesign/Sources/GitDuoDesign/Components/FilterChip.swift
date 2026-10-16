import SwiftUI

/// 筛选 chip —— 探索页那两个「日期 / 语言」按钮、搜索页的热门词
/// （原型 `styles/03-components.css` 的 `.fchip`）。
///
/// ## ⚠️ 2026-10-16（P2）：外观换成官方的 `.bordered` / `.borderedProminent` 胶囊
///
/// 口径见 `NATIVE-MIGRATION.md`：**「按原型」= 功能按原型，视觉正本 = Apple HIG**。
/// 原型那套「白底 / 浅蓝底 + 强调边 + 强调字，三处一起换」已经作废
/// —— 它是在没有系统件可用的前提下自拟的一套"已选"表达。
///
/// 现在用的是系统里现成的两档：
///
/// | 状态 | 官方样式 | 观感 |
/// |---|---|---|
/// | 未选 | `.bordered` + `.tint(textPrimary)` | 深字浅底，中性 |
/// | 已选 | `.borderedProminent` + `.tint(accent)` | 强调色底 + 白字 |
///
/// 这两档的差别是**整块底色的反转**，比原来"边框 + 字色 + 浅底"三处各变一点的读法更硬，
/// 而且它是系统在所有 App 里共用的那一种读法。
///
/// ## ⚠️ 为什么不是 `Menu`
///
/// `NATIVE-MIGRATION.md` 的 A 组里曾把本件标成"→ `Menu`"，实做时否掉了：
/// 这两个 chip 的 `action` 打开的是**一个 medium detent 弹层**
/// （`ExploreFilterSheet`，里面有十档色板与横滑列表），不是一份选项清单
/// ⇒ `Menu` 装不下它，硬套会把一个弹层降级成一个列表。
/// 系统件里对应的形态就是"一个打开弹层的胶囊按钮"，即本件现在的样子。
///
/// ## 它不认识"选了没有"
///
/// 收 `title` 与 `isHighlighted`，不收 `ExploreFilters`：设计包不依赖领域层（§3），
/// 而"该显示占位词还是选中值"是 `ExploreFilters.rangeChipLabel` 的事。
///
/// ## 它是内容层
///
/// 它嵌在探索页 / 搜索页的滚动内容里，**实色，不加 Liquid Glass**（§10.2）。
public struct FilterChip: View {

    public let title: String
    public let isHighlighted: Bool

    /// 是否显示右侧的下拉尖角。探索页两个 chip 都显示；留成参数是因为
    /// 搜索页的"热门词" chip 点了立即生效、不打开弹层（那一档传 `false`）。
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
        if isHighlighted {
            chip
                .buttonStyle(.borderedProminent)
                .tint(Theme.Palette.accent)
                .accessibilityLabel("\(title)，已筛选")
        } else {
            chip
                .buttonStyle(.bordered)
                .tint(Theme.Palette.textPrimary)
                .accessibilityLabel(title)
        }
    }

    /// 两档共用同一个 label —— 差别只在选中的那两行样式上。
    private var chip: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    HStack(spacing: Theme.Spacing.s) {
        FilterChip(title: "本周", isHighlighted: true) {}
        FilterChip(title: "语言", isHighlighted: false) {}
        // 搜索页那一档：点了立即生效，不显示尖角。
        FilterChip(title: "swiftui", isHighlighted: false, showsChevron: false) {}
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
