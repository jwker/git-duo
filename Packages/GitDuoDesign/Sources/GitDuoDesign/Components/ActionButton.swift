import SwiftUI

/// 通用动作按钮 —— **底层就是系统 `Button` + 官方按钮样式**。
///
/// ## ⚠️ 2026-10-16（P2）：内部从"自绘 `.btn`"换成官方按钮样式
///
/// 原型 `styles/03-components.css` 的 `.btn` 是一套自定样式（`border-radius:9px`、
/// `padding:9px 16px`、`font-size:13.5px`）。那一套**已经作废** —— 口径见
/// `NATIVE-MIGRATION.md`：**「按原型」= 功能按原型，视觉正本 = Apple HIG / 系统控件**。
///
/// 于是本件不再手画底色与圆角，改成把语义档位映射到官方按钮样式：
///
/// | `Style` | 对应官方样式 | 说明 |
/// |---|---|---|
/// | `.primary` | `.buttonStyle(.borderedProminent)` + `.tint(accentStrong)` | 主操作（主色 · 2026-10-17 起为橙） |
/// | `.ghost` | `.buttonStyle(.bordered)` | 次要操作，吃系统默认 tint |
/// | `.destructive` | `.borderedProminent` + `.tint(destructive)` | 破坏性操作（系统红） |
///
/// ⇒ 白拿系统行为：按下高亮、禁用变灰、动态类型、VoiceOver 的按钮特征、
/// 触摸目标尺寸、深浅色自动适配。这些在自绘版本里**一处都没有**。
///
/// ## ⚠️ `verticalPadding` / `horizontalPadding` 已删除
///
/// 那两个参数唯一的用途是"逐点复刻原型的 CSS 内边距"（原型在四处覆写过
/// `5px` / `9px` / `11px` / `12px`）。官方按钮样式的内边距由 `controlSize` 决定，
/// 不再接受逐点覆写 —— 留着会让调用方以为自己还能调，实际调不动。
///
/// ## 尺寸由 `controlSize` 决定
///
/// - `fillsWidth: true`（默认）：弹层底部与页面主体的**满宽按钮** ⇒ `.controlSize(.large)`。
///   这也是 HIG 在 iOS 上给"弹层主操作"的建议尺寸。
/// - `fillsWidth: false`：**行内并排**的小按钮（如评论区的「发送」）⇒ `.controlSize(.regular)`。
///
/// `fillsWidth` 撑的是 **label**（不是按钮外层）—— 官方样式的底色画在 label 上，
/// 把 `maxWidth` 加在按钮外层不会让底色变宽，只会让点击区多出一块空白。
///
/// ## ⚠️ 它同时服务**弹层**与**页面**（这条没变）
///
/// 所以它单独一件，**不塞进 `SheetPrimitives`** —— 否则页面为了一个按钮
/// 要去 import 一个叫"弹层零件"的东西。
///
/// ## 判据 #43：它进设计包
///
/// 只收基础类型（`String` / `Style` / `Bool` / 一个闭包），不认识任何领域模型。
///
/// ## 它是导航/操作层
///
/// 按钮**不加 Liquid Glass**（§10.2 只允许导航栏 / Tab / 工具栏 / Sheet 外框用玻璃，
/// 而按钮是内容）。
public struct ActionButton: View {

    public enum Style: Sendable, Hashable {

        /// 主操作（官方 `.borderedProminent` + GitHub 绿）。
        case primary

        /// 次要操作（官方 `.bordered`，吃系统默认 tint）。
        case ghost

        /// 危险操作（官方 `.borderedProminent` + `Palette.destructive`）。
        ///
        /// ⚠️ **原型没有这一档**：它的删除确认用的是 `.btn.primary` + 行内
        /// `background:var(--closed-p)`（`deleteBranchAsk`），而 `--closed-p` 正是
        /// 本仓的 `Palette.destructive`（`0xCF222E`，同一个值）。这里收成一档，
        /// 免得每个危险按钮各写一次行内覆盖。
        case destructive
    }

    public let title: String
    public let style: Style

    /// 是否撑满可用宽度（撑的是 label —— 见类型说明）。
    ///
    /// - `true`（默认）：弹层底部与页面主体的满宽按钮（原型里这些调用点都写了
    ///   `style="width:100%"`）。
    /// - `false`：**行内并排**的小按钮 —— `SCR.fileView` 的操作行、评论区的「发送」。
    public let fillsWidth: Bool

    /// 在途（内联转圈 + 禁用，防重复提交，§8.5「操作类」）。
    public let isWorking: Bool

    private let action: () -> Void

    public init(
        title: String,
        style: Style,
        fillsWidth: Bool = true,
        isWorking: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.fillsWidth = fillsWidth
        self.isWorking = isWorking
        self.action = action
    }

    public var body: some View {
        switch style {
        case .primary:
            button
                .buttonStyle(.borderedProminent)
                .tint(Theme.Palette.accentStrong)

        case .ghost:
            // 不设 `.tint` —— 次要操作吃系统 / App 的默认强调色（`Assets` 的 `AccentColor`）。
            button
                .buttonStyle(.bordered)

        case .destructive:
            button
                .buttonStyle(.borderedProminent)
                .tint(Theme.Palette.destructive)
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        // 与标题同色：prominent 那两档是白字，`bordered` 档是正文色。
                        .tint(style == .ghost ? Theme.Palette.textPrimary : Theme.Palette.surface)
                }
                Text(title)
            }
            .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .controlSize(fillsWidth ? .large : .regular)
        // ⚠️ §8.5「操作类」：在途时禁用（防重复提交）。这里用 `.disabled` 是**对的**
        //    —— 与决策 #51/#46 那两处"画出来但这一版就不做"不同，那是**永远**不可点。
        .disabled(isWorking)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.s) {
        ActionButton(title: "＋ 新建分支", style: .primary) {}
        ActionButton(title: "合并分支到 main…", style: .ghost) {}
        ActionButton(title: "删除分支", style: .destructive) {}
        ActionButton(title: "在途的样子", style: .primary, isWorking: true) {}

        // 行内档（评论区的「发送」就是这一档）：按内容宽、不与满宽按钮抢注意力。
        HStack(spacing: Theme.Spacing.s) {
            ActionButton(title: "发送", style: .primary, fillsWidth: false) {}
            ActionButton(title: "取消", style: .ghost, fillsWidth: false) {}
        }
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
