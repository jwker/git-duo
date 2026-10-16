import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 删除分支确认弹层（原型 `scripts/06-files.js` 的 `deleteBranchAsk`）。
///
/// 结构：标题 `删除分支「{name}」？` → 说明 → 红色「删除分支」→「取消」。
///
/// ## ⚠️ 说明那句是一句**承诺**，而它必须真的成立
///
/// `BranchCopy.deleteSheetHint` 写的是"删除前会校验该分支是否有未合并提交，有则阻止"。
/// 那句承诺的落点是**领域层 `DeleteBranch.run`**（决策 #53：先 `compare` 看
/// `ahead_by > 0`，通过才发 `DELETE`）—— 本件只是把话印出来，
/// **校验一个字都不在视图里**。
///
/// 这正是 `AGENTS.md §3` 那条"文案 / 权限 / 产品承诺要提为可测领域数据"的现场：
/// 文案承诺了实现做不到的事，曾经就是这么发生的。
///
/// ## ⚠️ 默认分支与受保护分支**点不到这张弹层**
///
/// 不给删除入口的判据在 `BranchSummary.canDelete(defaultBranch:)`（决策 #53），
/// 列表那一步就不画删除按钮。`DeleteBranch.run` 里还有一次**逻辑层拦截** ——
/// 两条路都要在，而拦截的四种结局各有各的文案
/// （`DeleteBranchResult.message(branch:)`，唯一落点）。
struct DeleteBranchSheet: View {

    let branch: BranchSummary

    let isWorking: Bool

    /// 确认删除。四种结局的文案由 `BranchesViewModel` 那边出（它拿得到回落值）。
    let onConfirm: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(BranchCopy.deleteSheetTitle(branch: branch.name))

            SheetHint(BranchCopy.deleteSheetHint)

            ActionButton(
                title: BranchCopy.deleteConfirmAction,
                style: .destructive,
                isWorking: isWorking
            ) {
                Task { await onConfirm() }
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.m)

            ActionButton(title: BranchCopy.cancelAction, style: .ghost) {
                dismiss()
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.s)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.surface)
    }
}

#Preview {
    DeleteBranchSheet(
        branch: BranchSummary(name: "feature/auth-refresh", commitSHA: "abc"),
        isWorking: false
    ) {}
    .background(Theme.Palette.background)
}
