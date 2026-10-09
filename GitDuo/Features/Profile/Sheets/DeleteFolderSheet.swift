import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 删除收藏夹确认弹层（PRD §5.14、TECH_SPEC §9.12）。
///
/// 结构：标题 `删除「{夹名}」？` → 说明段 → 红底「删除收藏夹」→「取消」。
/// 原型出处：`scripts/11-favorites.js` 的 `deleteFolderConfirm`（逐字）。
///
/// ## ⚠️ 说明段**回显 `{N}` 两次**，这不是啰嗦
///
/// 一次在"其中的多少项"，一次在"默认收藏夹计数相应 +N"。
/// 用户要能在按下红色按钮**之前**核对那个数 —— 而删除一旦发生**没有撤销**
/// （`TECH_SPEC §9.12` 里没有 undo 这一档）。
///
/// ## ⚠️ 说明段说的是"**收藏记录回落到默认夹**"，不是"删掉了收藏"
///
/// 那半句是本弹层存在的理由：少了它，用户看到的是"我删了一个夹，
/// 那些项目去哪了"—— 而回落是**静默发生**的，屏幕上不会再有第二处提到它。
///
/// ## ⚠️ 「默认收藏夹」走不进来
///
/// 那一行在管理页不是按钮（不给动作），所以到不了这里；逻辑层还有第二道拦截
/// （`FolderDeletionOutcome.protectedDefault` ⇒ 直接提示 `「默认收藏夹」不可删除`）。
struct DeleteFolderSheet: View {

    /// 标题里那个夹名。
    let name: String

    /// 说明里那个项目数（= 打开菜单那一刻的快照）。
    ///
    /// ⚠️ 它与 "默认夹会 +N" 里的 `N` 是**同一个数**，同一次快照算出来
    /// （`FolderCopy.deleteConfirmHint` 只收一个参数，就是为了让这件事在类型上成立）。
    let itemCount: Int

    /// 确认删除。**不等结果**（同 `DeleteFileSheet.onConfirm`）。
    let onConfirm: () async -> Void

    /// 「取消」—— 只关自己。
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(FolderCopy.deleteConfirmTitle(name: name))

            SheetHint(FolderCopy.deleteConfirmHint(name: name, count: itemCount))

            ActionButton(
                title: FolderCopy.deleteAction,
                style: .destructive,
                verticalPadding: 12
            ) {
                Task { await onConfirm() }
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.m)

            ActionButton(title: FolderCopy.cancelAction, style: .ghost, verticalPadding: 12) {
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
    DeleteFolderSheet(name: "以后再看", itemCount: 12) {}
        .background(Theme.Palette.background)
}
