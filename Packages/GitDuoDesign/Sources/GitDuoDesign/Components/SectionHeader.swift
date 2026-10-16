import SwiftUI

/// 分区标题（原型 `styles/03-components.css` 的 `.section-label` 与 `.home-head`）。
///
/// ## 两种形态来自原型
///
/// ```css
/// /* 2026-10-15 方案 D 起（走查第 73 条）—— 组标题从「12px 大写灰小字」
///    升级为 19pt 特粗组头：卡片容器全部去形后，分组全靠它一个元素承担。 */
/// .section-label{font-size:19px;font-weight:800;color:var(--text);
///                letter-spacing:-.3px;margin:22px 2px 6px}
/// .home-head{display:flex;align-items:baseline;justify-content:space-between;gap:8px;margin-top:16px}
/// .home-head .section-label{margin:0}
/// ```
///
/// - **带动作**（`actionTitle` 非空）：整行等宽，「置顶仓库 … 管理」「最近访问 … 清除」
///   就是这一种（`align-items:baseline` ⇒ 用 `firstTextBaseline`）。
/// - **不带动作**：只有一个标题（探索页的列表标题、详情页的各分区）。
///
/// ## ⚠️ 大写规则随方案 D 一起删了
///
/// 旧版挂着 `text-transform:uppercase`（只作用于英文分区名，如 `README.MD`）。
/// 方案 D 的新规则里**没有这一条** ⇒ 本件不再加 `.textCase`。
///
/// ## ⚠️ 两档**外边距**（切片 7.4 补）
///
/// 原型里 `.section-label` 有两种用法，差的就是外边距：
///
/// - **默认**：`margin:22px 2px 6px`（方案 D 起的上边距从 16 提到 22 —— 组与组之间
///   要靠这段空白分开，因为组与组之间已经没有任何容器形状了）——
///   所有"自己撑开上下留白"的分区标题都是这一种；
/// - **`margin:0`**：§4.10 新建 Issue 页的「标签」（`07-issues.js:23` 逐字带着
///   `style="margin:0"`）。那一页是一个 `display:flex;gap:10px` 的纵向流，
///   每个孩子之间的间距由 `gap` 统一给 ⇒ 标题再自带一层上下边距就会把它顶开。
///
/// ⚠️ 这两档**不能靠"调用方自己加负 padding"** 表达：那等于把本组件内部的
/// 数值泄露给每一个调用点，而将来改其中一个就会漏掉一处。
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
    /// 全归零会让标题与下面的内容贴在一起，所以补 2pt（`Spacing.xxs`）。
    private var bottomPadding: CGFloat {
        switch margins {
        case .section: action == nil ? 6 : Theme.Spacing.xxs
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
                // 方案 D：组标题取正文色 —— 12px 时代它是"全屏最安静的一级文字"，
                // 19pt 时代它是页面上最重的元素之一，灰色会让它看起来像一句说明。
                .foregroundStyle(Theme.Palette.textPrimary)
                // 原型 `letter-spacing:-.3px`（大标题收一点字距，笔画不那么散）。
                // 字号令牌管不到字距，这里写原值并注明出处。
                .tracking(-0.3)
                // ⚠️ **2026-10-16 起补这一句**（NATIVE-MIGRATION P3）：本件现在会被放进
                //    `Section` 的 header 位，而 `List` 的分组样式会给分区标题**加一层大写变换**
                //    （SwiftUI 在 `.grouped` / `.insetGrouped` 下默认如此）——
                //    「README.MD」会变成「README.MD」还算好，而混排的英文词会被整句抬成大写。
                //    在别处 `.textCase(nil)` 是空操作，所以这一句对非列表的调用点没有任何影响。
                .textCase(nil)

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

    /// 原型 `margin:22px 2px 6px` 的上边距（方案 D 起 16 → 22，见类型说明）。
    /// `.none` 那一档归零（见类型说明）。
    private var topPadding: CGFloat {
        switch margins {
        case .section: 22
        case .none: 0
        }
    }

    /// 原型 `margin:22px 2px 6px` 的左右边距。
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

        /// `margin:22px 2px 6px` —— `.section-label` 自带的那个（默认）。
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
