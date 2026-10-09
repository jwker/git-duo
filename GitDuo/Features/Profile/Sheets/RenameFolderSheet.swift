import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 重命名收藏夹弹层（PRD §5.13、TECH_SPEC §9.12）。
///
/// 结构：标题 `重命名收藏夹` → 名称输入框（**预填当前名称**）→「保存」→「取消」。
/// 原型出处：`scripts/11-favorites.js` 的 `renameFolderForm`（逐字）。
///
/// ## ⚠️ 校验的失败提示走**轻提示**，不是输入框下面那一行
///
/// 原型的 `renameFolder` 三档分别是
/// `toast('先输入收藏夹名称')` / `toast('已有同名收藏夹')` / **静默关闭**（与原名相同）
/// —— 即"错误用 toast 说"。所以本件**没有** `failure` 那个内联行
/// （`RenameFileSheet` 有，因为 §5.16 是一张没有原型参照的新规格，
/// 那时只能自己定；这里有正本，就照正本）。
///
/// ## ⚠️ 判据一个字都不在这里
///
/// 空名 / 与**其它**夹重名 / 与原名相同这三条全在 `FolderStore.rename(from:to:)`
/// —— 顺序也是（"与原名相同"必须排在"同名检查"**之前**，否则把夹名改成它自己
/// 会撞上"已有同名收藏夹"，而序列里明明只有它一个）。
/// 本件只把用户输入的那串字原样交出去。
struct RenameFolderSheet: View {

    /// 当前名称 —— 输入框的预填值（§5.13 逐字）。
    let name: String

    /// 提交新名字。
    ///
    /// ⚠️ **没有返回值**：关不关弹层由宿主决定（成功与"没改"两档都关、
    /// 校验不过那一档留着）—— 见 `FoldersViewModel.rename(from:to:)` 那张表。
    let onRename: (String) async -> Void

    /// 「取消」—— 只关自己（`.sheet(item:)` 会顺手把路由值写回 `nil`）。
    @Environment(\.dismiss) private var dismiss

    @State private var newName: String

    init(name: String, onRename: @escaping (String) async -> Void) {
        self.name = name
        self.onRename = onRename
        // ⚠️ **预填的是真值不是占位符**：用户不改就能直接提交。
        //    所以 `SheetField` 的 placeholder 给空串 —— 框里已经有一串字的时候
        //    再写一句"输入名称"会被误读成"这里还没填"（同 `RenameFileSheet`）。
        _newName = State(initialValue: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(FolderCopy.renameSheetTitle)

            SheetField("", text: $newName)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.top, Theme.Spacing.s)
                .submitLabel(.done)

            ActionButton(
                title: FolderCopy.saveAction,
                style: .primary,
                verticalPadding: 12
            ) {
                Task { await onRename(newName) }
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
    RenameFolderSheet(name: "前端好项目") { _ in }
        .background(Theme.Palette.background)
}
