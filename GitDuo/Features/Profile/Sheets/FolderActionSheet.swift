import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 收藏夹操作菜单弹层（PRD §5.12、TECH_SPEC §9.12）。
///
/// 结构：标题 `{夹名} · {N} 项` → 两行（`重命名` / `删除收藏夹`（**危险色**））
/// → 底部一句回落说明。
/// 原型出处：`scripts/11-favorites.js` 的 `openFolderSheet`（逐字）。
///
/// ## ⚠️ 它**只回调、不关自己**
///
/// 两个动作各自要**换成**另一张弹层（§5.13 / §5.14）—— 由宿主用同一个
/// `.sheet(item:)` 表达（见 `FoldersViewModel.SheetRoute`）。
/// 弹层自己 `dismiss()` 再让宿主 present，会变成"关一次、开一次"两次动画，
/// 而那中间的一帧是空屏（同 `FileOperationsSheet` 的处置）。
///
/// ## ⚠️ 夹名与项目数是**宿主传进来的快照**
///
/// 不是这里回读的：弹层开着的时候列表可能正在重读（例如另一个入口刚改过），
/// 回读会拿到新的数 —— 于是"标题写的 3 项"与用户接下来看到的事情对不上。
struct FolderActionSheet: View {

    /// 标题里那个夹名。
    let name: String

    /// 标题里那个项目数（= 打开菜单那一刻的快照）。
    let itemCount: Int

    let onRename: () -> Void

    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(FolderCopy.folderSheetTitle(name: name, count: itemCount))

            SheetRow(systemImage: GitHubIcon.pencil, title: FolderCopy.renameAction) {
                onRename()
            }

            // ⚠️ `titleTone: .destructive` —— 原型那一行是红字
            //    （`style="color:var(--closed-p)"` = `Palette.destructive`）。
            //    少了它，"这是破坏性操作"这条信息在画面上完全消失（点进去才知道）。
            SheetRow(
                systemImage: GitHubIcon.trash,
                title: FolderCopy.deleteAction,
                titleTone: .destructive
            ) {
                onDelete()
            }

            SheetHint(FolderCopy.folderSheetHint)

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
    FolderActionSheet(name: "前端好项目", itemCount: 2, onRename: {}, onDelete: {})
        .background(Theme.Palette.background)
}
