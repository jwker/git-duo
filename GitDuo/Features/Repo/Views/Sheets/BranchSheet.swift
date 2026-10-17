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
        // P4：自绘弹层 → 原生 `Form`（`SheetPrimitives` 五件退休，见 `NATIVE-MIGRATION.md` §P4）。
        // 分支行 → `Form` 内的原生 `Button` 行（leading 图标 + 标题 + 右侧 ✓ / chevron）。
        Form {
            Section {
                switch state.presentation {
                case .skeleton:
                    skeleton

                case .content:
                    if let list = state.value {
                        branchRows(list)
                    }

                case .failure:
                    failure
                }
            } header: {
                Text(isReadOnly ? BranchCopy.switchSheetTitleReadOnly : BranchCopy.switchSheetTitle)
            }

            if isReadOnly {
                Section {
                    Text(BranchCopy.readOnlySheetHint)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            } else if let onManage {
                Section {
                    Button { onManage() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: GitHubIcon.folder)
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.Palette.textSecondary)
                            Text(BranchCopy.manageBranchesRow)
                                .font(Theme.Font.rowTitle)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Spacer(minLength: 0)
                            Image(systemName: GitHubIcon.chevron)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 主体

    @ViewBuilder
    private func branchRows(_ list: BranchList) -> some View {
        // 分支多起来（几十条）仍由 `Form` 自身滚动；行本身是原生 `Button` 行。
        ForEach(list.branches) { branch in
            Button { onSelect(branch.name) } label: {
                HStack(spacing: 10) {
                    Image(systemName: GitHubIcon.branch)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Text(branch.name)
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Spacer(minLength: 0)
                    if branch.name == currentBranch {
                        // 原型：当前那条右边一个绿色 `✓` ⇒ `success`（2026-10-17）。
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.Palette.success)
                    }
                }
            }
        }
    }

    /// 与 `BranchesView.skeleton` 同一条口径（NATIVE-MIGRATION P1）：渲染真实的
    /// `branchRows(_:)` + 占位列表 + `.redacted`，不再手抄行高。
    ///
    /// ⚠️ `allowsHitTesting(false)`：**`.redacted` 不拦截点击** —— 遮住的行被点到
    /// 会把一条叫 `placeholder-0` 的分支名回调出去，那是一次必然失败的切换。
    private var skeleton: some View {
        branchRows(BranchList.placeholder(count: 4))
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
