import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 切换分支弹层（PRD §5.7、原型 `scripts/15-sheets.js` 的 `openBranchSheet`）。
///
/// 结构：标题 → 分支行列表（当前那条带一个 `✓`）→「管理分支…」入口（只在自己的仓库）
/// 或一句只读说明（他人仓库）。
///
/// ## 它是一张**内容视图**，不是一个 `isPresented` 开关
///
/// 同 `ExploreFilterSheet` / `UserProfileSheet`：由调用方（`RepoDetailView` /
/// `ExploreRepoDetailView`）用 `.sheet(item:)` 呈现，本件只画内容（`TECH_SPEC §8.4`）。
///
/// ## ⚠️ 两态只差两处，但这两处**必须**各是各的
///
/// | | 自己的仓库 | 他人仓库 |
/// |---|---|---|
/// | 标题 | `切换分支 · 代码与 Commits 联动` | `切换分支 · 浏览他人仓库` |
/// | 底部 | 「管理分支…（创建 / 删除 / 合并）」入口 | 一句说明（**无**入口） |
///
/// 在他人仓库上给一个「管理分支」入口，点进去每一行都必然失败 ——
/// 而失败的原因（没有写权限）从那一屏看不出来。
///
/// ## ⚠️ 它只负责"选哪一条"，不负责切换的副作用
///
/// 选中后要做的事（写记忆、重取目录、清提交列表、给提示）全在调用方的 ViewModel 里
/// —— 那些是业务规则，不是"弹层长什么样"。本件把选择原样回调出去。
struct BranchSheet: View {

    /// 分支列表的加载状态。⚠️ 它**常是 `idle`**（用户一进来就打开弹层）——
    /// 那一档画骨架屏，与"正在取"看起来一样，而两者对用户的含义也一样。
    let state: LoadState<BranchList>

    /// 当前分支。空串 = 还没解析出来（骨架期）。
    let currentBranch: String

    /// 只读（他人仓库）。
    let isReadOnly: Bool

    let onSelect: (String) -> Void

    /// 「管理分支…」——只读时为 `nil`（不画那一行）。
    let onManage: (() -> Void)?

    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(isReadOnly ? BranchCopy.switchSheetTitleReadOnly : BranchCopy.switchSheetTitle)

            content

            Spacer(minLength: 0)
        }
        // 原型 `.sheet{padding:8px 10px 12px}`。
        .padding(.horizontal, 10)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.surface)
    }

    // MARK: - 主体

    @ViewBuilder
    private var content: some View {
        switch state.presentation {
        case .skeleton:
            skeleton

        case .content:
            if let list = state.value {
                rows(list)
            }

        case .failure:
            failure
        }
    }

    @ViewBuilder
    private func rows(_ list: BranchList) -> some View {
        // 分支多起来（几十条）要能滚 —— 弹层是 `.medium` 起步的，装不下那么多行。
        ScrollView {
            VStack(spacing: 0) {
                ForEach(list.branches) { branch in
                    SheetRow(systemImage: GitHubIcon.branch, title: branch.name) {
                        onSelect(branch.name)
                    } trailing: {
                        if branch.name == currentBranch {
                            // 原型：当前那条右边一个绿色 `✓`。
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.Palette.accentStrong)
                        }
                    }
                }
            }
        }
        .scrollDisabled(list.branches.count <= 6)

        if isReadOnly {
            SheetHint(BranchCopy.readOnlySheetHint)
        } else if let onManage {
            SheetRow(systemImage: GitHubIcon.folder, title: BranchCopy.manageBranchesRow) {
                onManage()
            } trailing: {
                Image(systemName: GitHubIcon.chevron)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    /// 与 `BranchesView.skeleton` 同一条口径（NATIVE-MIGRATION P1）：渲染真实的
    /// `rows(_:)` + 占位列表 + `.redacted`，不再手抄行高。
    ///
    /// ⚠️ `allowsHitTesting(false)`：**`.redacted` 不拦截点击** —— 遮住的行被点到
    /// 会把一条叫 `placeholder-0` 的分支名回调出去，那是一次必然失败的切换。
    private var skeleton: some View {
        rows(BranchList.placeholder(count: 4))
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var failure: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("分支列表加载失败")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
            Button("重试", action: onRetry)
                .font(Theme.Font.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.xl) {
        BranchSheet(
            state: .loaded(BranchList(
                branches: [
                    BranchSummary(name: "main", commitSHA: "aaa"),
                    BranchSummary(name: "feature/auth-refresh", commitSHA: "bbb"),
                    BranchSummary(name: "release/2.0", commitSHA: "ccc", isProtected: true)
                ],
                hasMore: false
            )),
            currentBranch: "feature/auth-refresh",
            isReadOnly: false,
            onSelect: { _ in },
            onManage: {},
            onRetry: {}
        )

        BranchSheet(
            state: .loading,
            currentBranch: "",
            isReadOnly: true,
            onSelect: { _ in },
            onManage: nil,
            onRetry: {}
        )
    }
    .background(Theme.Palette.background)
}
