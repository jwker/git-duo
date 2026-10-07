import SwiftUI

/// **面包屑条** —— 仓库详情「代码」分区顶部那一条（原型 `scripts/05-repo.js` 的 `crumb`）。
///
/// ```css
/// .crumb{font-size:12.5px;color:var(--text2);background:var(--card);
///        border:1px solid var(--border-soft);border-radius:9px;padding:8px 12px;margin-bottom:8px}
/// .crumb b{color:var(--link);font-weight:600}
/// .branch-chip{display:inline-flex;align-items:center;gap:4px;background:var(--chip);
///              border-radius:7px;padding:3px 8px;font-weight:650;color:var(--link);
///              cursor:pointer;font-size:12px;white-space:nowrap}
/// ```
///
/// 形状：`[分支胶囊] · 仓库全名 / 中间层 / **当前层**` +（可选）右侧动作位。
///
/// ## ⚠️ 它只收基础类型（判据 #43）
///
/// 收 `branch: String` 与 `path: [String]`，**不认识** `Repository` / `RepoPath`。
/// "当前在哪一级、下一级该请求哪个 path"是领域层的事（`RepoPath`）；
/// 这里只回答"一条面包屑长什么样"。
///
/// ## ⚠️ 路径段是**字符串数组**，第 0 段就是仓库全名
///
/// 原型把仓库名当作路径的第一段（`navToSub('')` 回到根目录）。
/// 所以根目录下 `path.count == 1`，此时那一段既是首段也是当前层 ——
/// **它不该是可点的**（点了原地不动）。
///
/// ⚠️ **有意偏差（已登记）**：原型在根目录仍然把仓库名画成蓝色可点链接
/// （`<span class="crumb-link" onclick="navToSub('')">`），
/// 而 PRD §4.4 明写「当前层加粗不可点」。取 PRD ——
/// 原型那一处是"忘了给根目录换成 `<b>`"，不是"根目录就该可点"：
/// 点它不会发生任何事，而一颗按下去没反应的链接比不画链接更糟。
///
/// ## 长路径**折行**，不截尾
///
/// 原型是行内流式内容，放不下就换行。所以路径那一段走 `FlowLayout`
/// （本包里已有的流式布局），而不是 `HStack` —— 后者会把中间某段压成 `Packag…`，
/// 而"我在哪一级"正是这条控件唯一的信息。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct BreadcrumbBar<Trailing: View>: View {

    public let branch: String

    /// 路径段，**第 0 段是仓库全名**；最后一段是当前层。
    public let path: [String]

    /// 点分支胶囊。`nil` ⇒ 胶囊不可点（决策 #46：`allowsHitTesting(false)` + 读屏 hint，
    /// **不是** `.disabled` —— 后者会变灰、看起来像"暂时不可用"）。
    public let onTapBranch: (() -> Void)?

    /// 点某个中间层。参数是 `path` 的下标。`nil` ⇒ 全部路径段不可点。
    public let onSelectSegment: ((Int) -> Void)?

    private let trailing: Trailing

    public init(
        branch: String,
        path: [String],
        onTapBranch: (() -> Void)? = nil,
        onSelectSegment: ((Int) -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.branch = branch
        self.path = path
        self.onTapBranch = onTapBranch
        self.onSelectSegment = onSelectSegment
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 0) {
            branchChip
            Text(" · ")
                .font(Theme.Font.breadcrumb)
                .foregroundStyle(Theme.Palette.textSecondary)

            // 路径段折行（原型是行内流式内容）。
            // `spacing: 0` 是有意的：分隔符 ` / ` 已经作为每段的前缀画出来了，
            // 再给一个间距会让 ` / ` 两边同时出现两种宽度。
            FlowLayout(spacing: 0, lineSpacing: Theme.Spacing.xxs) {
                ForEach(Array(path.enumerated()), id: \.offset) { index, title in
                    segment(index: index, title: title)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if Trailing.self != EmptyView.self {
                // 右侧动作位（原型 `margin-left:auto` 的「＋ 添加」）。
                trailing.padding(.leading, Theme.Spacing.s)
            }
        }
        // 8 / 12：原型原值（`padding:8px 12px`）。
        .padding(.vertical, Theme.Spacing.s)
        .padding(.horizontal, Theme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .stroke(Theme.Palette.borderSoft, lineWidth: 1)
        )
    }

    // MARK: - 分支胶囊

    private var branchChip: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: GitHubIcon.branch)
                .font(.system(size: 13))
            Text(branch)
                .font(Theme.Font.label)
            // 原型的 `▾` 是一个**字面字符**，且它在折叠前后都不变（`.branch-chip` 没有状态样式）
            // ⇒ 这里照印同一个字符，不换成会旋转的 `chevron.down`
            // （换掉就等于替原型改了一个它明写的细节）。
            Text("▾")
                .font(Theme.Font.caption)
        }
        .foregroundStyle(Theme.Palette.accent)
        .padding(.vertical, 3)
        .padding(.horizontal, Theme.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.branchChip, style: .continuous)
                .fill(Theme.Palette.surfaceSunken)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTapBranch?() }
        .allowsHitTesting(onTapBranch != nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前分支 \(branch)")
        .accessibilityHint(onTapBranch == nil ? "不可切换" : "切换分支")
        .accessibilityAddTraits(onTapBranch == nil ? AccessibilityTraits() : .isButton)
    }

    // MARK: - 路径段

    @ViewBuilder
    private func segment(index: Int, title: String) -> some View {
        // 每段自带前缀分隔符：`/`（原型 `' / '`）。⚠️ 前缀而**不是**独立的兄弟元素 ——
        // 折行时若分隔符自己成一行，会在行尾留下一根孤零零的斜杠。
        let prefix = index == 0 ? "" : " / "
        let isCurrent = index == path.count - 1

        if isCurrent || onSelectSegment == nil {
            // 当前层：加粗（原型 `.crumb b{font-weight:600}`，颜色仍是链接色）。
            Text(prefix + title)
                .font(Theme.Font.breadcrumb.weight(.semibold))
                .foregroundStyle(Theme.Palette.accent)
                .lineLimit(1)
        } else {
            Button {
                onSelectSegment?(index)
            } label: {
                Text(prefix + title)
                    .font(Theme.Font.breadcrumb)
                    .foregroundStyle(Theme.Palette.accent)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        }
    }
}

extension BreadcrumbBar where Trailing == EmptyView {

    /// 不带右侧动作位的那一种（探索页的面包屑原型就没有按钮）。
    public init(
        branch: String,
        path: [String],
        onTapBranch: (() -> Void)? = nil,
        onSelectSegment: ((Int) -> Void)? = nil
    ) {
        self.init(
            branch: branch,
            path: path,
            onTapBranch: onTapBranch,
            onSelectSegment: onSelectSegment,
            trailing: { EmptyView() }
        )
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.m) {
        BreadcrumbBar(
            branch: "feature/repo-detail",
            path: ["my-git/gitduo", "Packages", "GitDuoKit", "Sources"],
            onTapBranch: {},
            onSelectSegment: { _ in }
        ) {
            Text("＋ 添加")
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.vertical, 5)
                .padding(.horizontal, Theme.Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.Palette.surfaceSunken)
                )
        }

        // 根目录：只有一段 ⇒ 它既是首段也是当前层，加粗不可点。
        BreadcrumbBar(branch: "main", path: ["my-git/gitduo"], onSelectSegment: { _ in })

        // 只读（探索页）：胶囊与路径段都不可点。
        BreadcrumbBar(branch: "main", path: ["cli/cli"])
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
