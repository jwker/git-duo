import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 文件操作菜单（PRD §5.15、决策 #66）。
///
/// 结构：标题 `文件操作 · {文件名}` → 两行（`重命名` / `删除文件`（危险色））。
///
/// ## ⚠️ 它是一张**新**规格，原型里没有
///
/// 原型 `SCR.fileView` 的「更多」只给一句演示 toast
/// （`toast('演示：重命名 / 删除（带 sha 校验）')`）—— 两张后续弹层都不存在。
/// 形态按 §5.15 指定照 §5.12（收藏夹操作菜单），而那一张在原型里
/// （`11-favorites.js:93/94`）的两行**都是带图标的**
/// （`svg(I.pencil)` / `svg(I.trash)`）⇒ 这里也用 `systemImage`。
///
/// ## ⚠️ 它**只回调、不关自己**
///
/// 两个动作各自要换成**另一张弹层**（§5.16 / §5.17），而"换哪一张"由调用方
/// 用同一个 `.sheet(item:)` 表达 —— 弹层自己 `dismiss()` 再让调用方 present，
/// 会变成"关一次、开一次"两次动画，而那中间的一帧是空屏。
struct FileOperationsSheet: View {

    /// 这一屏的上下文（§5.15 明写带**文件名**而不是完整路径：标题放不下长路径，
    /// 且用户此刻不需要在两级目录之间做区分）。
    let fileName: String

    let onRename: () -> Void

    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(FileCopy.fileOperationsSheetTitle(fileName: fileName))

            SheetRow(systemImage: GitHubIcon.pencil, title: FileCopy.renameAction) {
                onRename()
            }

            // ⚠️ `titleTone: .destructive` —— §5.15 明写「危险色」。
            //    少了它，"这是破坏性操作"这条信息在画面上**完全消失**（点进去才知道）。
            SheetRow(
                systemImage: GitHubIcon.trash,
                title: FileCopy.deleteAction,
                titleTone: .destructive
            ) {
                onDelete()
            }

            // 底部说明：`§5.12` 那一张有一句（"删除收藏夹后…不影响仓库本身"），
            // 而 §5.15 **只给了两个动作行**、没有给说明句 ⇒ 这里**不编一句**。
            // （编出来的话会是一件用户可见的、没有任何文档依据的承诺。）

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
    FileOperationsSheet(fileName: "AppTabs.swift", onRename: {}, onDelete: {})
        .background(Theme.Palette.background)
}
