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
/// ## ⚠️ 两档**外边距**（切片 7.4 补）
///
/// 原型里 `.section-label` 有两种用法，差的就是外边距：
///
/// - **默认**：`margin:16px 2px 8px`（写在 `.section-label` 自己身上）——
///   所有"自己撑开上下留白"的分区标题都是这一种；
/// - **`margin:0`**：§4.10 新建 Issue 页的「标签」（`07-issues.js:23` 逐字带着
///   `style="margin:0"`）。那一页是一个 `display:flex;gap:10px` 的纵向流，
///   每个孩子之间的间距由 `gap` 统一给 ⇒ 标题再自带一层上下边距就会把它顶开。
///
/// ⚠️ 这两档**不能靠"调用方自己加负 padding"** 表达：那等于把本组件内部的
/// 三个数值（16 / 2 / 8）泄露给每一个调用点，而将来改其中一个就会漏掉一处。
///
/// ## 它是内容层
///
/// 分区标题在滚动内容里，**实色，不加 Liquid Glass**（§10.2）。
public struct SectionHeader: View {

    public let title: String

    /// 右侧链接按钮文案（`管理` / `清除`）；`nil` = 不渲染。
    public let actionTitle: String?

    public let action: (() -> Void)?

    /// 外边距档位（见类型说明；默认是原型 `.section-label` 自带的那个）。
    public let margins: Margins

    /// 底部留白。
    ///
    /// 带动作时原型把 `.section-label` 的 `margin` 归零（由 `.home-head` 管外边距），
    /// 靠 CSS 的行高撑出一点空隙 —— 而 SwiftUI 的 `Text` 没有那段行距，
    /// 全归零会让标题与卡片贴在一起，所以补 2pt（`Spacing.xxs`）。
    private var bottomPadding: CGFloat {
        switch margins {
        case .section: action == nil ? Theme.Spacing.s : Theme.Spacing.xxs
        case .none: 0
        }
    }

    public init(
        title: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        margins: Margins = .section
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
        self.margins = margins
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
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .padding(.horizontal, horizontalPadding)
    }

    /// 原型 `margin:16px 2px 8px` 的上边距。`.none` 那一档归零（见类型说明）。
    private var topPadding: CGFloat {
        switch margins {
        case .section: Theme.Spacing.l
        case .none: 0
        }
    }

    /// 原型 `margin:16px 2px 8px` 的左右边距。
    private var horizontalPadding: CGFloat {
        switch margins {
        case .section: Theme.Spacing.xxs
        case .none: 0
        }
    }
}

extension SectionHeader {

    /// 原型里 `.section-label` 的两处外边距写法（见类型说明）。
    public enum Margins: Sendable, Hashable {

        /// `margin:16px 2px 8px` —— `.section-label` 自带的那个（默认）。
        case section

        /// `style="margin:0"` —— 排版由外层 `gap` 统一给的那种（§4.10 的「标签」）。
        case none
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        SectionHeader(title: "置顶仓库", actionTitle: "管理") {}
        SectionHeader(title: "最近访问", actionTitle: "清除") {}
        SectionHeader(title: "Latest Release")
        SectionHeader(title: "贡献者 · 23 位")
        // `.none` 那一档：上下左右都不带外边距，间距完全由外层 `gap` 给
        //（§4.10 新建 Issue 页的「标签」）。与上面几行并排看，差别就是"贴住了"。
        SectionHeader(title: "标签", margins: .none)
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
