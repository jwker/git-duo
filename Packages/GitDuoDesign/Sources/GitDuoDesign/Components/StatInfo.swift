import SwiftUI

/// 一条统计**信息** —— 仓库头部那一排里的 `👁 Watch · 45` / `⑂ Fork · 88`
/// （与 `StatButton` 并排；2026-10-15 新增，走查第 **66** 条）。
///
/// ## 为什么要与 `StatButton` 分成两个件
///
/// 那三颗里**只有 Star 能点**。Watch 与 Fork 从来就点不动
/// （PRD §4.4 / §4.13 原文写的就是「**展示** Watch 数」「**展示** Fork 数」），
/// 但它们此前与 Star 长得**一模一样**（同一个 `StatButton`：底色 + 圆角 + 边框），
/// 且刻意不加灰 ⇒ 外观与那颗能点的无法区分，点下去没有任何反应。
/// 用户 2026-10-15 报回「没有必要做成按钮形状了」，打的就是这一点。
///
/// ⇒ 现在**形状本身就是信号**：有底色 / 边框 = 点得动（`StatButton`），
/// 没有 = 只是一条信息（本件）。这比"两颗都灰掉"更准 ——
/// 灰是"暂时不可用"，而 Watch / Fork 是**这一版压根没有这个动作**。
///
/// ## ⚠️ 为什么是 `padding(.vertical:)` 而不是给 `FlowLayout` 加对齐参数
///
/// `FlowLayout.placeSubviews` 用的是 `.topLeading`，两块高度不同就会顶不齐。
/// 但这两块的**内容高度天然相同**（同字号的图标 + 同字号的文字，都是 `Theme.Font.label`），
/// 差值只来自 `StatButton` 自己那一圈 `padding(Spacing.s)` ⇒ 这里补一个**同样的垂直内边距**
/// 就恰好等高，`topLeading` 下也就自然对齐。
/// ⚠️ 千万别改成 `.frame(height:)` 之类的固定值 —— Dynamic Type 一放大就错位。
/// 若将来**第三处**也需要行内垂直居中，再给 `FlowLayout` 加 `alignment` 参数不迟。
///
/// ## ⚠️ 颜色比按钮浅一档，这是有意的
///
/// 文字走 `textSecondary`（按钮走 `textPrimary`）—— 它是**信息**、不是控件，
/// 本就不该与那颗能点的抢注意力。这一档差也是"这块点不动"的第二重提示（第一重是形状）。
///
/// ## 它不再有"点不动"那句读屏 hint
///
/// 原来两颗各挂一句 `watchUnavailableHint` / `forkUnavailableHint`，
/// 是为了解释「一个按下去没反应的按钮」。现在它不是按钮 —— 读屏用户不会再试图点它，
/// 那句解释也就不需要了。两个常量连同它们一起删掉：留着那句 hint，
/// 「这颗还不能点」在代码里就仍然看起来成立（同 `addFileUnavailableHint` 的先例）。
public struct StatInfo: View {

    /// 图标（如 `eye`）。
    public let systemImage: String

    /// 自定义图标视图（覆盖 `systemImage`）—— 理由与 `StatButton` 那条相同：
    /// SF Symbols 里没有「实线 fork」这个字形，`ForkIcon` 是设计包自绘的。
    public let icon: AnyView?

    /// 文案（如 `Watch · 45`）。**由调用方算好** —— 与 `StatButton` 同口径。
    public let title: String

    /// **图标**的着色；`nil` = 跟随文字（`textSecondary`）。
    ///
    /// ⚠️ 2026-10-15 新增，目前**只有一个使用者**：`StatStar` 里"已 Star"那颗星
    /// 吃 `Theme.Palette.starActive` —— 那个令牌的定义正是「**已 Star** 态的金色」，
    /// 且明写**不得用作文字色**（白底上对比度不足 2:1）。所以它**只染图标**，
    /// 文字恒 `textSecondary`。
    ///
    /// ⚠️ 别拿它给 Watch / Fork 上色：那两颗没有"激活态"这个概念，
    /// 而"颜色 = 状态"这条线索一旦在两处出现，就不再是一条线索了。
    public let iconTint: Color?

    public init(systemImage: String, title: String, iconTint: Color? = nil) {
        self.systemImage = systemImage
        self.icon = nil
        self.title = title
        self.iconTint = iconTint
    }

    public init<Icon: View>(icon: Icon, title: String) {
        self.systemImage = ""
        self.icon = AnyView(icon)
        self.title = title
        self.iconTint = nil
    }

    public var body: some View {
        let iconView: AnyView = {
            if let icon { return icon }
            // 用户裁定的比例：图标必须与文字**同字号**（同 `StatButton`，
            // 用 `Theme.Font.label` 而非硬编码点数，Dynamic Type 放大时两者同步）。
            return AnyView(Image(systemName: systemImage).font(Theme.Font.label))
        }()

        // ⚠️ 2026-10-16（P2）：手写的 `HStack` 换成官方的 `Label` ——
        //    这块东西的**语义**本来就是"一个图标 + 一段文字"，而 `Label` 正是那件官方件
        //    （它天然是"图标与文字是一个整体"的读屏单位，从前那句
        //    `.accessibilityElement(children: .ignore)` 就是手工补这一条）。
        Label {
            Text(title)
                .font(Theme.Font.label)
                .lineLimit(1)
                // 与 `StatButton` 同口径的兜底：常态下宽度随内容，不会被压缩。
                .minimumScaleFactor(0.8)
                .foregroundStyle(Theme.Palette.textSecondary)
        } icon: {
            // ⚠️ 图标与文字**分开着色**（2026-10-15 起）：`iconTint` 只作用于图标。
            iconView
                .foregroundStyle(iconTint ?? Theme.Palette.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.s)
        // 读屏："Watch · 45" —— 图标是纯装饰（`ForkIcon` 也没有名字），只念文案。
        .accessibilityLabel(title)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
        // 常态：一颗按钮 + 两条信息，左对齐、各自只包住自己的内容。
        // ⚠️ 这里要盯的就是"顶齐"——按钮有内边距、信息没有底色，两块应当上下夹齐。
        FlowLayout(spacing: Theme.Spacing.s) {
            StatButton(systemImage: "star", activeSystemImage: "star.fill",
                       title: "Star · 2,341", activeTint: Theme.Palette.starActive) {}
            StatInfo(systemImage: "eye", title: "Watch · 45")
            StatInfo(icon: ForkIcon().frame(width: 12, height: 12), title: "Fork · 88")
        }

        // 长数字 + 窄容器：放不下折到下一行之后，第二行那两块的顶齐还得成立。
        FlowLayout(spacing: Theme.Spacing.s) {
            StatButton(systemImage: "star", activeSystemImage: "star.fill",
                       title: "Starred · 128,441", isActive: true,
                       activeTint: Theme.Palette.starActive) {}
            StatInfo(systemImage: "eye", title: "Watch · 12,004")
            StatInfo(icon: ForkIcon().frame(width: 12, height: 12), title: "Fork · 9,318")
        }
        .frame(width: 300)

        // 两颗点不动的那一屏。
        // ⚠️ 这段注释在 2026-10-15 之前写着"本张预览不会同时出现三颗裸信息，因为 Star
        //    那一刻仍是灰按钮（决策 #80）" —— 那句话**现在不成立了**：走查第 67 条
        //    把 Star 也收进了裸信息（写不了的仓库上）。三颗齐的那一屏见 `StatStar` 预览 ②。
        FlowLayout(spacing: Theme.Spacing.s) {
            StatInfo(systemImage: "eye", title: "Watch · 3")
            StatInfo(icon: ForkIcon().frame(width: 12, height: 12), title: "Fork · 7")
        }
    }
    .padding(Theme.Spacing.page)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.Palette.background)
}
