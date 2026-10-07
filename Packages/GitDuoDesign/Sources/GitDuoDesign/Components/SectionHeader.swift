import SwiftUI

/// 分区标题（原型 `styles/03-components.css` 的 `.section-label` 与 `.home-head`）。
///
/// ## 两种形态来自原型
///
/// ```css
/// .section-label{font-size:12px;font-weight:700;color:var(--text3);
///                text-transform:uppercase;letter-spacing:.6px;margin:16px 2px 8px}
/// .home-head{display:flex;align-items:baseline;justify-content:space-between;gap:8px;margin-top:16px}
/// .home-head .section-label{margin:0}
/// ```
///
/// - **带动作**（`actionTitle` 非空）：整行等宽，「置顶仓库 … 管理」「最近访问 … 清除」
///   就是这一种（`align-items:baseline` ⇒ 用 `firstTextBaseline`）。
/// - **不带动作**：只有一个标题（探索页的列表标题、详情页的各分区）。
///
/// ## ⚠️ `text-transform:uppercase` 是照做的，不是抄错
///
/// 原型这个类上确实挂着 `uppercase`。中文没有大小写，所以它只作用于英文分区名 ——
/// 本切片出现的 `Latest Release` 会被渲染成 **`LATEST RELEASE`**，
/// 切片 6 的 `README.md` 会变成 `README.MD`。这就是原型上看到的样子，
/// 因此照做；若认为观感不对，改这一处即可（一个 `.textCase`）。
///
/// ## 它是内容层
///
/// 分区标题在滚动内容里，**实色，不加 Liquid Glass**（§10.2）。
public struct SectionHeader: View {

    public let title: String

    /// 右侧链接按钮文案（`管理` / `清除`）；`nil` = 不渲染。
    public let actionTitle: String?

    public let action: (() -> Void)?

    /// 底部留白。
    ///
    /// 带动作时原型把 `.section-label` 的 `margin` 归零（由 `.home-head` 管外边距），
    /// 靠 CSS 的行高撑出一点空隙 —— 而 SwiftUI 的 `Text` 没有那段行距，
    /// 全归零会让标题与卡片贴在一起，所以补 2pt（`Spacing.xxs`）。
    private var bottomPadding: CGFloat {
        action == nil ? Theme.Spacing.s : Theme.Spacing.xxs
    }

    public init(
        title: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text(title)
                .font(Theme.Font.sectionLabel)
                .foregroundStyle(Theme.Palette.textTertiary)
                // 见类型说明：原型就是这么写的，中文不受影响、英文会变大写。
                .textCase(.uppercase)

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.Palette.accent)
                    // 按钮要可点，但视觉上比分区标题稍宽一点（原型 `.linkbtn{padding:4px 2px}`），
                    // 否则一行 12pt 的链接点起来太窄。
                    .padding(.vertical, Theme.Spacing.xs)
                    .padding(.horizontal, Theme.Spacing.xxs)
            }
        }
        .padding(.top, Theme.Spacing.l)
        .padding(.bottom, bottomPadding)
        .padding(.horizontal, Theme.Spacing.xxs)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        SectionHeader(title: "置顶仓库", actionTitle: "管理") {}
        SectionHeader(title: "最近访问", actionTitle: "清除") {}
        SectionHeader(title: "Latest Release")
        SectionHeader(title: "贡献者 · 23 位")
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
