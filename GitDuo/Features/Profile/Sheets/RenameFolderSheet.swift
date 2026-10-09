import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 重命名收藏夹弹层（PRD §5.13、TECH_SPEC §9.12）。
///
/// 结构：标题 `重命名收藏夹` → 名称输入框（**预填当前名称**）→「保存」→「取消」。
/// 原型出处：`scripts/11-favorites.js` 的 `renameFolderForm`（逐字）。
///
/// ## ⚠️ 校验的失败提示画在**本弹层内**（2026-10-09 改口径，决策 #77）
///
/// 原型的 `renameFolder` 三档分别是
/// `toast('先输入收藏夹名称')` / `toast('已有同名收藏夹')` / **静默关闭**（与原名相同），
/// ⇒ 本件**最早**是按"照原型用 toast 说"写的，注释里当时写着一条处置：
/// 「**这里有正本，就照正本**；`RenameFileSheet` 那种没有原型参照的新规格才自己定内联行」。
///
/// ⚠️ **那条处置在 App 里是错的**，而它在原型里是对的 —— 差别在**层级**：
/// 原型的弹层与 toast 同属一层 DOM（`toast{z-index:90}` 直接盖在弹层上，看得见）；
/// 而 App 的弹层是一层**独立呈现**，挂在根容器上的提示条**被整块盖住**。
/// ⇒ 用户走查报回"点了保存没反应"（走查第 4 条）。现在前两档改成**弹层内那一行**
/// （`SheetFailureHint`，位置在「保存」按钮上方、形态与 `RenameFileSheet` 逐字相同）；
/// "与原名相同"那一档仍然静默关闭（它压根不该有提示）。
///
/// ⚠️ 这是**全 App 的通则**，不只本件：**弹层留着 ⇒ 话画在弹层里；弹层关掉 ⇒ 照旧走提示条**
/// （正本：`TECH_SPEC §8.4` 决策 #77；与原型的不同处置登记在偏差第 45 条）。
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

    /// 校验不过时那一行（`nil` = 不显示）。由**宿主**持有（动作在它那里执行）。
    let hint: String?

    /// 提交新名字。
    ///
    /// ⚠️ **没有返回值**：关不关弹层由宿主决定（成功与"没改"两档都关、
    /// 校验不过那一档留着）—— 见 `FoldersViewModel.rename(from:to:)` 那张表。
    let onRename: (String) async -> Void

    /// 「取消」—— 只关自己（`.sheet(item:)` 会顺手把路由值写回 `nil`）。
    @Environment(\.dismiss) private var dismiss

    @State private var newName: String

    init(name: String, hint: String?, onRename: @escaping (String) async -> Void) {
        self.name = name
        self.hint = hint
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

            // 紧贴按钮上方 —— 它说的是"你刚才按的那一下为什么没成"。
            if let hint {
                SheetFailureHint(hint)
            }

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

#Preview("没有校验问题") {
    RenameFolderSheet(name: "前端好项目", hint: nil) { _ in }
        .background(Theme.Palette.background)
}

#Preview("重名") {
    RenameFolderSheet(name: "前端好项目", hint: FolderCopy.duplicateInRename) { _ in }
        .background(Theme.Palette.background)
}
