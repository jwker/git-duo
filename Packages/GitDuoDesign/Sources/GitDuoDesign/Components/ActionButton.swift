import SwiftUI

/// 通用动作按钮 —— 原型 `styles/03-components.css` 的 `.btn`。
///
/// ```css
/// .btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;
///      border:none;border-radius:9px;padding:9px 16px;font-size:13.5px;font-weight:650}
/// .btn.primary{background:var(--green);color:#fff}
/// .btn.ghost{background:var(--chip);color:var(--text)}
/// ```
///
/// ## 它同时服务**弹层**与**页面**
///
/// 原型里 `.btn` 是全局的：弹层底部用它（`openAddSheet` / `openCommitSheet`），
/// 页面主体也用它（`SCR.branches` 的两个满宽按钮、`SCR.fileView` 的操作行）。
/// 所以它单独一件，**不塞进 `SheetPrimitives`** —— 否则页面为了一个按钮
/// 要去 import 一个叫"弹层零件"的东西。
///
/// ## 判据 #43：它进设计包
///
/// 只收基础类型（`String` / `Style` / `Bool` / 一个闭包），不认识任何领域模型。
///
/// ## ⚠️ `verticalPadding` 是有意暴露的
///
/// 原型在四处覆写了 `.btn` 的纵向内边距（`5px` / `9px` / `11px` / `12px`），
/// 而**横向始终 16**（`UserProfileSheet` 那种满宽按钮横向由 `maxWidth` 决定）。
/// 与其生造四档"尺寸"，不如把这一个数交给调用点 —— 每一处都能注明它的出处。
///
/// ## 它是导航/操作层
///
/// 按钮**不加 Liquid Glass**（§10.2 只允许导航栏 / Tab / 工具栏 / Sheet 外框用玻璃，
/// 而按钮是内容）。
public struct ActionButton: View {

    public enum Style: Sendable {

        /// 主操作（绿底白字，原型 `.btn.primary`）。
        case primary

        /// 次要操作（浅灰底深字，原型 `.btn.ghost`）。
        case ghost

        /// 危险操作（红底白字）。
        ///
        /// ⚠️ **原型没有这一档**：它的删除确认用的是 `.btn.primary` + 行内
        /// `background:var(--closed-p)`（`deleteBranchAsk`），而 `--closed-p` 正是
        /// 本仓的 `Palette.destructive`（`0xCF222E`，同一个值）。这里收成一档，
        /// 免得每个危险按钮各写一次行内覆盖。
        case destructive

        var background: Color {
            switch self {
            case .primary: Theme.Palette.accentStrong
            case .ghost: Theme.Palette.surfaceSunken
            case .destructive: Theme.Palette.destructive
            }
        }

        var foreground: Color {
            switch self {
            case .primary, .destructive: Theme.Palette.surface
            case .ghost: Theme.Palette.textPrimary
            }
        }
    }

    public let title: String
    public let style: Style

    /// 纵向内边距。原型 `.btn` 是 `9px`；四处调用点各自覆写过（`5` / `11` / `12`）。
    public let verticalPadding: CGFloat

    /// 横向内边距。原型 `.btn{padding:9px 16px}` 是 16；
    /// `SCR.fileView` 的主按钮覆写成 **22**（`padding:9px 22px`）。
    ///
    /// ⚠️ 撑满宽度时**不生效**（见 `fillsWidth`）：`maxWidth: .infinity` 之后再补
    /// 横向内边距，会让整条按钮比可用宽度宽出两倍内边距 —— 那一处会溢出。
    public let horizontalPadding: CGFloat

    /// 是否撑满可用宽度。
    ///
    /// - `true`（默认）：弹层底部与页面主体的满宽按钮。原型里这些调用点都写了
    ///   `style="width:100%"`（`openAddSheet` / `openCommitSheet` / `SCR.branches`）。
    /// - `false`：**行内并排**的小按钮 —— 原型 `.btn` 本身是 `display:inline-flex`
    ///   （按内容宽、不撑满），`SCR.fileView` 的操作行就是这样四个按钮居中排开。
    ///
    /// 为什么要一个开关而不是让调用方在外面 `.frame(width:)`：撑满是**按钮自己**
    /// 的布局（`.frame(maxWidth:)` 必须落在背景之前），在外面补一个框架改不动它。
    public let fillsWidth: Bool

    /// 在途（内联转圈 + 禁用，防重复提交，§8.5「操作类」）。
    public let isWorking: Bool

    private let action: () -> Void

    public init(
        title: String,
        style: Style,
        verticalPadding: CGFloat = 9,
        horizontalPadding: CGFloat = 16,
        fillsWidth: Bool = true,
        isWorking: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.fillsWidth = fillsWidth
        self.isWorking = isWorking
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if isWorking {
                    ProgressView().controlSize(.small).tint(style.foreground)
                }
                Text(title)
                    // 原型 13.5px/650 ⇒ 最近的一档是 `footnote`(13) + semibold。
                    .font(Theme.Font.footnote.weight(.semibold))
            }
            .foregroundStyle(style.foreground)
            .padding(.vertical, verticalPadding)
            // 撑满时横向内边距必须为 0：它要加在 `maxWidth: .infinity` **之前**。
            .padding(.horizontal, fillsWidth ? 0 : horizontalPadding)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            // 行内模式不许被父级压扁（一个 4 个字的按钮被截成"编…"比不可点更难懂）。
            .fixedSize(horizontal: !fillsWidth, vertical: false)
            .background(
                // 原型 `border-radius:9px` ⇒ `Radius.control`。
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(style.background)
            )
        }
        .buttonStyle(.plain)
        // ⚠️ §8.5「操作类」：在途时禁用（防重复提交）。这里用 `.disabled` 是**对的**
        //    —— 与决策 #51/#46 那两处"画出来但这一版就不做"不同，那是**永远**不可点。
        .disabled(isWorking)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.s) {
        ActionButton(title: "＋ 新建分支", style: .primary, verticalPadding: 12) {}
        ActionButton(title: "合并分支到 main…", style: .ghost, verticalPadding: 12) {}
        ActionButton(title: "删除分支", style: .destructive, verticalPadding: 12) {}
        ActionButton(title: "在途的样子", style: .primary, verticalPadding: 12, isWorking: true) {}
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
