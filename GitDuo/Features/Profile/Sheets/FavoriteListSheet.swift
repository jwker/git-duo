import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 「选择收藏列表」弹层（PRD §5.5、TECH_SPEC §9.12 的两段式交互第二步）。
///
/// 结构：标题 `选择收藏列表` → 每个收藏夹一行（名称 + `{N} 项` + 已选 ✓）
/// → 「新建收藏夹…」行 → 底部说明。
/// 原型出处：`scripts/11-favorites.js` 的 `openFavSheet`（逐字）。
///
/// ## ⚠️ 它的**触发点是仓库详情页**，不是「我的收藏」页
///
/// 两段式交互（§9.12）：首次点「收藏到我的列表」直接进默认夹并提示
/// "再点可选择列表"；**再点**才打开本弹层。所以进得来的必然是"已经收藏过"的
/// ⇒ `current` 一定有值。**留成可空是为了让"没收藏"这件事在类型上仍然表达得出来**
/// （真进来时不该猜一个默认夹当选中项）。
///
/// ## ⚠️ 点已选那一行 = **取消收藏**，点别处 = **移动**
///
/// 这条差别（§5.5 逐字：「点当前已选列表 = 从收藏移除；点其它列表 = 移动收藏」）
/// 不在本件里判 —— 本件只把"用户点了哪个夹名"交出去，
/// 由调用方按 `FolderStore` 的三个结果（`moved` / `unchanged` / 移除）
/// 决定说什么话。底部那句说明里的「再点已选列表取消收藏」就是这条规则本身，
/// **不能省**（它是用户唯一能得知"再点一下会取消"的地方）。
struct FavoriteListSheet: View {

    /// 全部收藏夹 + 项目数（一次 `summaries()` 拿回的快照 —— 名称与数量同行出现，
    /// 免得拼出"名字是新的、数量还是旧的"这种半截状态）。
    let summaries: [FolderSummary]

    /// 这个仓库现在属于哪个夹；`nil` = 没收藏过。
    let current: String?

    /// 点了一行。参数是那个夹名（是否等于 `current` 由调用方判）。
    let onPick: (String) -> Void

    /// 点了「新建收藏夹…」→ 换成 §5.6 那张（由宿主的同一个 `.sheet(item:)` 表达）。
    let onNewFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(FolderCopy.listSheetTitle)

            ForEach(summaries) { summary in
                SheetRow(
                    systemImage: GitHubIcon.bookmark,
                    title: summary.name,
                    // ⚠️ `action:` 这个标签必须写出来 —— 省略它，尾随闭包会绑到
                    //    不带 `trailing:` 的那个重载上，右侧这块内容**静默不画**
                    //    （见 `SheetRow` 的说明）。
                    action: { onPick(summary.name) }
                ) {
                    trailing(for: summary)
                }
            }

            // 原型 `svg(I.plus)` + grow + `svg(I.chev)` —— 两个图标都是
            // `.sheet-row svg` 那一档（18pt / `--text2`，见 `SheetRow` 的图标说明）。
            SheetRow(systemImage: GitHubIcon.plus, title: FolderCopy.newFolderRowTitle, action: onNewFolder) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            SheetHint(FolderCopy.listSheetHint)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.surface)
    }

    /// 行尾：`{N} 项` +（若这一行就是当前归属）一枚绿色 ✓。
    ///
    /// ⚠️ 原型的 ✓ 是 `<b style="color:var(--green)">✓</b>`，即 `Palette.accentStrong`
    /// —— 与分支弹层里那个 ✓ 同一个令牌（`SheetPrimitives` 的预览就是那么画的）。
    @ViewBuilder
    private func trailing(for summary: FolderSummary) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(FolderCopy.itemCount(summary.itemCount))
                // 原型 `.t3`（11.5px / `--text3`）。
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)

            if summary.name == current {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Palette.accentStrong)
            }
        }
    }
}

#Preview {
    FavoriteListSheet(
        summaries: [
            FolderSummary(folder: Folder(name: FolderDefaults.name), itemCount: 45),
            FolderSummary(folder: Folder(name: "前端好项目"), itemCount: 2),
            FolderSummary(folder: Folder(name: "Swift 学习"), itemCount: 5)
        ],
        current: "Swift 学习",
        onPick: { _ in },
        onNewFolder: {}
    )
    .background(Theme.Palette.background)
}
