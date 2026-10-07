import SwiftUI

/// **分支列表的一行** —— 原型 `scripts/06-files.js` 的 `SCR.branches`。
///
/// ```css
/// .menu-item{display:flex;align-items:center;gap:12px;padding:13px 14px;
///            border-bottom:1px solid var(--border-soft);cursor:pointer;
///            font-size:14.5px;font-weight:550}
/// .menu-item svg{width:19px;height:19px;stroke:var(--text2);stroke-width:1.8}
/// ```
/// 行内结构（原型逐字）：`[分支图标] [分支名] [「当前」胶囊] …… [删除按钮]`。
///
/// ## ⚠️ 它**不判断**"能不能删"，只画
///
/// 「非默认 **且** 非受保护」这条判据在领域层 `BranchSummary.canDelete(defaultBranch:)`
/// ——这里是"唯一判据"（决策 #53）。本件收一个 `canDelete: Bool` 就够：
/// 它只需要知道"画不画那个按钮"。**不要在视图里写第二套判断**：
/// 视图拿不到默认分支名，只能靠猜，而猜错的后果是给受保护分支画一个必然失败的删除按钮。
///
/// ## ⚠️ 文案由调用方给，本件不写死任何字
///
/// `badgeTitle`（「当前」，原型 `.pill.open`）与 `deleteTitle`（「删除」）都从
/// `BranchCopy` 传进来。设计包不得依赖领域层（依赖铁律），
/// 但**文案属于可见契约**、必须能单测（`AGENTS.md` §2）——
/// 所以两侧各让一步：字在领域层，形状在设计包。
///
/// ## 删除按钮与整行**不是嵌套**关系
///
/// 行本身可点（切换分支），删除按钮也要能点。两件事都做成 `Button` 会嵌套，
/// 于是外层 `onTapGesture` + 内层 `Button`：**手势的判定范围是"没被 Button 吃掉的部分"**，
/// 正是原型 `event.stopPropagation()` 想要的效果。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct BranchRow: View {

    public let name: String

    /// 当前分支的胶囊文字（原型「当前」）。`nil` ⇒ 不画胶囊。
    public let badgeTitle: String?

    /// 画不画删除按钮。判据在领域层（`BranchSummary.canDelete`）。
    public let canDelete: Bool

    /// 删除按钮的文字。
    public let deleteTitle: String

    /// 画不画底部分隔线。原型的规则是"除最后一条之外都画"，
    /// 组件不知道自己在不在末位，所以由调用方传（同 `SearchRowBox`）。
    public let showsSeparator: Bool

    public let onSelect: () -> Void

    public let onDelete: () -> Void

    public init(
        name: String,
        badgeTitle: String?,
        canDelete: Bool,
        deleteTitle: String,
        showsSeparator: Bool = true,
        onSelect: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.name = name
        self.badgeTitle = badgeTitle
        self.canDelete = canDelete
        self.deleteTitle = deleteTitle
        self.showsSeparator = showsSeparator
        self.onSelect = onSelect
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: GitHubIcon.branch)
                .font(.system(size: 19))
                .foregroundStyle(Theme.Palette.textSecondary)
                .accessibilityHidden(true)

            Text(name)
                // 原型 `font-size:14.5px;font-weight:550` ⇒ `rowTitle`(14.5 那一档) + medium。
                .font(Theme.Font.rowTitle.weight(.medium))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)

            if let badgeTitle {
                // 原型给这颗胶囊 `margin-left:8px` —— 与上面 `HStack` 的 12 分开算。
                StatusPill(title: badgeTitle, tone: .open)
                    .padding(.leading, Theme.Spacing.s)
            }

            Spacer(minLength: Theme.Spacing.s)

            if canDelete {
                deleteButton
            }
        }
        // 13 / 14：原型原值（`padding:13px 14px`）—— 4pt 阶里没有这两档，写原值并注明出处。
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(Theme.Palette.borderSoft)
                    .frame(height: 1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Text(deleteTitle)
                // 原型 `.btn{font-size:13.5px;font-weight:650}` + `padding:4px 10px`
                // ⇒ 13.5px 落到本仓最近的一档是 `footnote`(13)。
                .font(Theme.Font.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.vertical, Theme.Spacing.xs)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.Palette.surfaceSunken)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("删除分支 \(name)")
    }
}

#Preview {
    VStack(spacing: 0) {
        BranchRow(
            name: "main", badgeTitle: "当前", canDelete: false, deleteTitle: "删除",
            onSelect: {}, onDelete: {}
        )
        BranchRow(
            name: "feature/repo-detail", badgeTitle: nil, canDelete: true, deleteTitle: "删除",
            onSelect: {}, onDelete: {}
        )
        // 受保护分支：判据在领域层，这里只拿到一个 false ⇒ 不画按钮。
        BranchRow(
            name: "release/1.0", badgeTitle: nil, canDelete: false, deleteTitle: "删除",
            showsSeparator: false, onSelect: {}, onDelete: {}
        )
    }
    .background(Theme.Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
