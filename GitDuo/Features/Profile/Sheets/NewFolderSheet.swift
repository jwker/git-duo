import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 新建收藏夹弹层（PRD §5.6、TECH_SPEC §9.12）。
///
/// 结构：标题 `新建收藏夹` → 名称输入框 → 一颗按钮。
/// 原型出处：`scripts/11-favorites.js` 的 `newFavForm` / `newFolderForm`
/// （两张**同一屏、只差按钮文案**，见下面的 `Entry`）。
///
/// ## ⚠️ 两个入口共用这一张弹层，但**行为有别**
///
/// | 入口 | 按钮 | 重名时 |
/// |---|---|---|
/// | 仓库详情页的「收藏」区（§5.6 前半） | `创建并收藏` | 提示"已为你选中"，**照样把仓库放进去** |
/// | 本页（我的收藏 · §5.6 后半） | `创建` | 只提示，**不创建、不动任何仓库** |
///
/// 这两句话的差别（"已为你选中" vs 没有）是那条行为差别的**唯一可见证据** ——
/// 所以按钮文案由 `Entry` 决定，而**校验与动作**分别落在
/// `FolderStore.createAndFavorite`（有唯一实现）与 `FolderStore.create`。
/// 本件一个字都不判（同 `RenameFolderSheet`）。
///
/// ## ⚠️ 它只回调、不关自己
///
/// 关不关、关掉之后要不要接着做别的（仓库入口要顺带收藏）全由宿主决定：
/// 校验不过那一档**必须留着**弹层（用户还能改名再试）。
struct NewFolderSheet: View {

    /// 从哪个入口打开 —— 只影响按钮文案。
    enum Entry: Sendable, Hashable {

        /// 仓库详情页的「收藏」区（§5.6 前半）。
        case repository

        /// 「我的收藏」管理页底部（§5.6 后半）。
        case management

        /// 那颗按钮的字。两串都是 `FolderCopy` 里的逐字文案，这里只做一次翻档。
        var confirmTitle: String {
            switch self {
            case .repository: FolderCopy.createAndFavoriteAction
            case .management: FolderCopy.createAction
            }
        }
    }

    let entry: Entry

    /// 提交那个名字。**没有返回值** —— 关不关由宿主决定。
    let onCreate: (String) async -> Void

    /// 「取消」—— 只关自己。
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(FolderCopy.newSheetTitle)

            // 占位符两个入口是同一句（原型两处都是 `placeholder="收藏夹名称"`）。
            SheetField(FolderCopy.nameFieldPlaceholder, text: $name)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.top, Theme.Spacing.s)
                .submitLabel(.done)

            ActionButton(
                title: entry.confirmTitle,
                style: .primary,
                verticalPadding: 12
            ) {
                Task { await onCreate(name) }
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
    NewFolderSheet(entry: .management) { _ in }
        .background(Theme.Palette.background)
}
