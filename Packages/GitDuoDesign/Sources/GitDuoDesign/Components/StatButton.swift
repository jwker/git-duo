import SwiftUI

/// 统计**按钮** —— 仓库头部那一排里**唯一可点**的那颗 `Star · 2,341`
/// （原型 `styles/04-screens.css` 的 `.stat-btn`，见 PRD §4.13）。
///
/// ⚠️ **它现在只有一个使用者**：`StatStar` 里"**能写**"的那一档（2026-10-15，走查第 66 / 67 条）。
///
/// 那一天连着砍掉了本件的两个使用者，理由是同一条（**形状即信号**）：
///
/// | 谁 | 何时不再用本件 | 为什么 |
/// |---|---|---|
/// | Watch / Fork | 第 **66** 条 | 它俩永远点不动（PRD 原文只写"展示"），画成按钮就是承诺一件不会发生的事 ⇒ 改 `StatInfo` |
/// | Star（**写不了**的仓库上） | 第 **67** 条 | 同上 —— 一颗灰按钮仍有按钮的形状，而"写不了"的仓库上那颗星**点不动** ⇒ 改 `StatInfo` |
///
/// ⇒ 于是"有底色 + 边框"在这个 App 里成了"**这块点得动**"的唯一信号。
/// **别随手把它加到别处** —— 加一处，这条线索就弱一分。
///
/// ## ⚠️ 2026-10-16（P2）：外观换成官方的 `.bordered` 胶囊按钮
///
/// 口径见 `NATIVE-MIGRATION.md`：**「按原型」= 功能按原型，视觉正本 = Apple HIG**。
/// 于是本件不再手画"浅灰底 + 圆角矩形"，改成 `Button` + `.buttonStyle(.bordered)`
/// + `.buttonBorderShape(.capsule)` —— 白拿按下高亮、禁用变灰、动态类型，
/// 以及"这确实是个按钮"的系统语义（形状即信号这条判据反而更硬了：底和形状由系统给）。
///
/// 随之作废的有两件（都记在下面，免得将来又被人当成"还没改完"）：
///
/// 1. **"横排 / 随内容宽"那套自定义几何**（2026-10-11 为「太大了」那次反馈改的）
///    —— 现在由 `controlSize` 与 `Label` 决定，而两条结论仍然成立：
///    按钮**不撑满整行**（这是 HIG 的常态，也是这里要的）；**不要**加回
///    `.frame(maxWidth: .infinity)`（那是当年"三等分整宽"的写法）。
/// 2. **「已 Star 时整块吃金色」那条既有偏差**（2026-10-11 查出、一直挂着未处置）
///    —— 已顺手修掉：`activeTint` 现在**只染图标**，文字吃按钮的 tint
///    （`Theme.Palette.textPrimary`）。原型 `.stat-btn.starred svg{fill:#eac54f}`
///    本来就只命中 `svg`，而 `Theme.Palette.starActive` 的抬头明写
///    "只用于星形图标，**绝不用作文字色**"（金色在白底上对比度约 1.5:1）。
///    这条对原型的有意偏差（`REVIEW-CHECKLIST` **第 50 条**）至此收口。
///
/// ## 它为什么收文案而不是收计数
///
/// 按钮上是 `Star · 2,341` 还是 `Starred · 2,342`，取决于**是否已 Star** 这个业务状态
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

    /// 激活时**图标**的颜色。默认强调色；Star 按钮传 `Theme.Palette.starActive`。
    ///
    /// ⚠️ 2026-10-16（P2）起它**只作用于图标** —— 从前它被套在整块（图标 + 文字）上，
    /// 而 `Theme.Palette.starActive` 的抬头明写"绝不用作文字色"。原委见类型抬头第 2 条。
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
    /// `icon` 优先级高于 `systemImage`；传进来后会直接放进 `Label` 的图标位，
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
    /// 做成 **`nonisolated static` 纯函数**（本包那条"reduceMotion 判定可单测"的老规矩）：
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
                // 与文字**同字号**（同 `StatInfo`）：`Theme.Font.label` 而非硬编码点数，
                // 这样 Dynamic Type 放大时图标与文字仍然同步。
                .font(Theme.Font.label)
            )
        }()

        Button(action: action) {
            Label {
                Text(title)
                    .font(Theme.Font.label)
                    .lineLimit(1)
                    // ⚠️ 保留它作兜底：常态下按钮宽度随内容，不会被压缩。
                    //    但若将来被放进一个**定宽**容器（或 Dynamic Type 放大到一行放不下），
                    //    截断会连数字一起吃掉 —— 而那个数正是用户要看的东西。
                    .minimumScaleFactor(0.8)
            } icon: {
                // ⚠️ `activeTint` **只染图标**（见属性说明）。
                iconView.foregroundStyle(isActive ? activeTint : Theme.Palette.textPrimary)
            }
        }
        .buttonStyle(.bordered)
        // 胶囊：与同屏的信息块（`StatInfo`）在高度上接近，形状上明确区分。
        .buttonBorderShape(.capsule)
        // ⚠️ 文字恒 `textPrimary`（不吃 `activeTint`）—— 见属性说明。
        .tint(Theme.Palette.textPrimary)
        // 读屏："Star · 2,341，已选中" —— 图标与文字本就是一个整体，不要逐块念。
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
        // 常态：三颗左对齐、各自只包住自己的内容（**不是**三等分整宽）。
        FlowLayout {
            StatButton(systemImage: "star", activeSystemImage: "star.fill",
                       title: "Starred · 2,342", isActive: true,
                       activeTint: Theme.Palette.starActive) {}
            StatInfo(systemImage: "eye", title: "Watch · 45")
            StatInfo(
                icon: ForkIcon().frame(width: 12, height: 12),
                title: "Fork · 88"
            )
        }

        // 长数字 + 窄容器：放不下就折到下一行。
        FlowLayout {
            StatButton(systemImage: "star", activeSystemImage: "star.fill",
                       title: "Star · 128,441", activeTint: Theme.Palette.starActive) {}
            StatInfo(systemImage: "eye", title: "Watch · 12,004")
            StatInfo(
                icon: ForkIcon().frame(width: 12, height: 12),
                title: "Fork · 9,318"
            )
        }
        .frame(width: 300)
    }
    .padding(Theme.Spacing.page)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.Palette.background)
}
