import SwiftUI

/// 统计按钮 —— 仓库头部那一排 `Star · 2,341` / `Watch · 45` / `Fork · 88`
/// （原型 `styles/04-screens.css` 的 `.stat-btn`，见 PRD §4.13）。
///
/// ## 它为什么收文案而不是收计数
///
/// 按钮上是 `Star · 2,341` 还是 `已 Star · 2,342`，取决于**是否已 Star** 这个业务状态
/// （决策 #41 的基准查询）；组件只负责画，不负责算。这样"那个 ±1 到底以什么为基准"
/// 只有一处实现，而不是散在三个按钮里各写一遍。
///
/// ## 图标为什么需要单独传"激活态的名字"
///
/// 原型切换的是一段 SVG 的 `fill`（描边星 → 实心星）。SF Symbols 里对应的是**两个符号**
/// （`star` / `star.fill`），而**不是所有符号都有 `.fill` 变体**（例如
/// `arrow.triangle.branch` 没有）⇒ 靠"给名字追加 `.fill`"来推导会静默拿到一个不存在的
/// 符号名，界面上表现为**图标凭空消失**。所以由调用方显式给出，且允许为 `nil`（该按钮没有激活态）。
///
/// ## 它是内容层
///
/// 三个按钮长在仓库头部的卡片里 ⇒ **实色，不得加 Liquid Glass**（§10.2 点名"仓库卡片"）。
public struct StatButton: View {

    /// 常态图标（如 `star`）。
    public let systemImage: String

    /// 激活态图标（如 `star.fill`）；`nil` 表示这个按钮没有激活态。
    public let activeSystemImage: String?

    /// 按钮文案（如 `Star · 2,341`）。**由调用方算好** —— 见类型说明。
    public let title: String

    public let isActive: Bool

    /// 激活时图标与文字的颜色。默认强调色；Star 按钮传 `Theme.Palette.starActive`。
    public let activeTint: Color

    public let action: () -> Void

    public init(
        systemImage: String,
        activeSystemImage: String? = nil,
        title: String,
        isActive: Bool = false,
        activeTint: Color = Theme.Palette.accent,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.activeSystemImage = activeSystemImage
        self.title = title
        self.isActive = isActive
        self.activeTint = activeTint
        self.action = action
    }

    /// 实际使用的符号名：有激活态且已激活时才换名。
    ///
    /// 做成 **`nonisolated static` 纯函数**（与 `SkeletonBar.animates` 同一模式）：
    /// `View` 协议的成员默认继承主 actor 隔离，而"已 Star 时用的是 `star.fill`"这件事
    /// 最好能被单测钉住 —— 不必靠肉眼看着一个 17pt 的图标去分辨它是实心还是空心。
    nonisolated static func resolvedSystemImage(
        systemImage: String,
        activeSystemImage: String?,
        isActive: Bool
    ) -> String {
        isActive ? (activeSystemImage ?? systemImage) : systemImage
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: Self.resolvedSystemImage(
                    systemImage: systemImage,
                    activeSystemImage: activeSystemImage,
                    isActive: isActive
                ))
                .font(.system(size: 17))
                Text(title)
                    .font(Theme.Font.label)
                    .lineLimit(1)
                    // 窄屏上 `Watch · 1,234` 可能超出按钮宽度 —— 缩小而不是截断成「Watch …」，
                    // 截断会连数字一起吃掉，那正是用户要看的东西。
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? activeTint : Theme.Palette.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Palette.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Palette.borderSoft, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        // 读屏："Star · 2,341，已选中" —— 图标与文字本就是一个整体，不要逐块念。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

#Preview {
    HStack(spacing: Theme.Spacing.s) {
        StatButton(systemImage: "star", activeSystemImage: "star.fill",
                   title: "已 Star · 2,342", isActive: true,
                   activeTint: Theme.Palette.starActive) {}
        StatButton(systemImage: "eye", title: "Watch · 45") {}
        StatButton(systemImage: "arrow.triangle.branch", title: "Fork · 88") {}
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
