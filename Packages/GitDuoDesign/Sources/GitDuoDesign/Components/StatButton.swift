import SwiftUI

/// 统计按钮 —— 仓库头部那一排 `Star · 2,341` / `Watch · 45` / `Fork · 88`
/// （原型 `styles/04-screens.css` 的 `.stat-btn`，见 PRD §4.13）。
///
/// ## ⚠️ 形态**有意偏离原型**：横排、宽度随内容（2026-10-11）
///
/// 原型是 `.stat-btn{flex:1;flex-direction:column;padding:9px 0}` —— 图标在上、文字在下，
/// 三颗**等分整宽**，单颗约 52pt 高。用户反馈"太大了，重新设计、排版"后改为：
///
/// | | 原型 / 改造前 | 现在 |
/// |---|---|---|
/// | 图标与文字 | **上下两行** | **同一行**（`HStack`） |
/// | 宽度 | `flex:1` 三等分撑满整行 | **随内容**（每颗只包住自己那一串） |
/// | 内边距 | `padding:9px 0` | `Theme.Spacing.s` 四边 |
/// | 图标 | 17px | **与文案同字号**（`Theme.Font.label`，12pt） |
/// | 高度 | ≈ 52pt | ≈ 34pt |
///
/// ⚠️ 承载的**三态语义一个都没变**（已选中换实心符号 + 自定前景色、`.disabled` 的灰、
/// 在途时那颗 `ProgressView`）—— 变的只有几何。
/// 已登记为对原型的有意偏差（`REVIEW-CHECKLIST` **第 50 条**）。
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

    /// 自定义图标视图（覆盖 `systemImage`）。用于 SF Symbols 里找不到同形字形的场景，
    /// 例如 `ForkIcon`（上下翻转的小写 `h`：三个空心圆在左上 / 右上 / 左下）。
    /// ⚠️ 自定义图标**没有激活态**（目前唯一的使用者 Fork 本来就没有）。
    public let icon: AnyView?

    /// 按钮文案（如 `Star · 2,341`）。**由调用方算好** —— 见类型说明。
    public let title: String

    public let isActive: Bool

    /// 激活时**图标与文字**的颜色（见下方那条"与原型不符"）。默认强调色；Star 按钮传 `Theme.Palette.starActive`。
    ///
    /// ## ⚠️ 它在**已 Star** 那一档与原型不符（既有问题，2026-10-11 查出、未处置）
    ///
    /// 这里把 `activeTint` 一次性套在**整块**（图标 + 文字）上，而原型
    /// `.stat-btn.starred svg{fill:#eac54f}` 的选择器**只命中 `svg`** —— 文字仍是正文色。
    /// `Theme.Palette.starActive` 的抬头也明写"只用于星形图标的填充 / 描边，**绝不用作文字色**"
    /// （金色在白底上对比度约 1.5:1）。⇒ **原型 / 令牌注释 / 实现**三处不一致。
    ///
    /// ⚠️ 单测拦不住它：`ThemeTests` 那条测的是"与状态色的距离"与"对比度区间"，
    /// **没有一行代码知道它被用在了文字上**。
    ///
    /// ⇒ 修法只有一处（图标吃 `activeTint`、文字恒 `textPrimary`），但**要不要改得单独决定**
    /// —— 它会把"已 Star"的观感从"整块金"变回"金星 + 深字"。
    /// 本次只动几何、保持现状；原委记在 `REVIEW-CHECKLIST` 第 50 条那一段末尾。
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
        self.icon = nil
        self.title = title
        self.isActive = isActive
        self.activeTint = activeTint
        self.action = action
    }

    /// 带**自定义图标视图**的构造器。
    ///
    /// `icon` 优先级高于 `systemImage`；传进来后会直接放进 `HStack`，
    /// 不再包一层 `Image(systemName:)`。调用方负责尺寸（建议 `Theme.Font.label` 同大）。
    /// 自定义图标目前**没有激活态**（只有 Fork 使用，而 Fork 没有 on/off 状态）。
    public init<Icon: View>(
        icon: Icon,
        title: String,
        isActive: Bool = false,
        activeTint: Color = Theme.Palette.accent,
        action: @escaping () -> Void
    ) {
        self.systemImage = ""
        self.activeSystemImage = nil
        self.icon = AnyView(icon)
        self.title = title
        self.isActive = isActive
        self.activeTint = activeTint
        self.action = action
    }

    /// 实际使用的符号名：有激活态且已激活时才换名。
    ///
    /// 做成 **`nonisolated static` 纯函数**（与 `SkeletonBar.animates` 同一模式）：
    /// `View` 协议的成员默认继承主 actor 隔离，而"已 Star 时用的是 `star.fill`"这件事
    /// 最好能被单测钉住 —— 不必靠肉眼看着一个 15pt 的图标去分辨它是实心还是空心。
    nonisolated static func resolvedSystemImage(
        systemImage: String,
        activeSystemImage: String?,
        isActive: Bool
    ) -> String {
        isActive ? (activeSystemImage ?? systemImage) : systemImage
    }

    public var body: some View {
        let iconView: AnyView = {
            if let icon { return icon }
            return AnyView(
                Image(systemName: Self.resolvedSystemImage(
                    systemImage: systemImage,
                    activeSystemImage: activeSystemImage,
                    isActive: isActive
                ))
                // 用户裁定的比例：图标必须和文字**同字号**，不能大一号。
                // 用 `Theme.Font.label`（12pt semibold）而非硬编码点数，
                // 这样 Dynamic Type 放大时图标与文字仍然同步。
                .font(Theme.Font.label)
            )
        }()

        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                iconView
                Text(title)
                    .font(Theme.Font.label)
                    .lineLimit(1)
                    // ⚠️ 保留它作兜底：常态下按钮宽度随内容，不会被压缩。
                    //    但若将来被放进一个**定宽**容器（或 Dynamic Type 放大到一行放不下），
                    //    截断会连数字一起吃掉 —— 而那个数正是用户要看的东西。
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? activeTint : Theme.Palette.textPrimary)
            // ⚠️ **不要加回 `.frame(maxWidth: .infinity)`** —— 那是"三等分整宽"的写法，
            //    加回去等于把这次改造撤销掉（而且单看一颗按钮看不出来）。
            .padding(Theme.Spacing.s)
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
    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
        // 常态：三颗左对齐、各自只包住自己的内容（**不是**三等分整宽）。
        FlowLayout {
            StatButton(systemImage: "star", activeSystemImage: "star.fill",
                       title: "已 Star · 2,342", isActive: true,
                       activeTint: Theme.Palette.starActive) {}
            StatButton(systemImage: "eye", title: "Watch · 45") {}
            StatButton(
                icon: ForkIcon().frame(width: 12, height: 12),
                title: "Fork · 88"
            ) {}
        }

        // 长数字 + 窄容器：放不下就折到下一行 —— 这正是 `FlowLayout` 在这里的用途
        //（改造前是三等分整宽，数字长了只会把字号压小）。
        FlowLayout {
            StatButton(systemImage: "star", activeSystemImage: "star.fill",
                       title: "Star · 128,441", activeTint: Theme.Palette.starActive) {}
            StatButton(systemImage: "eye", title: "Watch · 12,004") {}
            StatButton(
                icon: ForkIcon().frame(width: 12, height: 12),
                title: "Fork · 9,318"
            ) {}
        }
        .frame(width: 300)
    }
    .padding(Theme.Spacing.page)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.Palette.background)
}
