import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 版本说明弹层 —— 「Latest Release」卡片底部那颗「更多」的落点。
///
/// ## ⚠️ 它是一张**新**规格，原型里没有
///
/// 原型 `10-explore-repo.js:45` 把 `${t.relNote}` 直接铺在卡片正文里（一个 `div`），
/// 既没有截断、也没有入口 —— 于是一段几百字的 release note 会把这张卡撑到占满整屏，
/// 把下面的语言构成 / 文件浏览全推走。2026-10-11 定：**正文从卡片移到这里**，
/// 卡片只留一颗「更多」。按钮文案与弹层标题都是这次**自拟**的
/// （`LatestRelease.notesButtonTitle` / `notesSheetTitle(tagName:)`）。
/// 已登记为对原型的有意偏差（`REVIEW-CHECKLIST` **第 51 条**）。
///
/// 形态照既有的只读弹层走：`SheetTitle` + 正文，不加关闭按钮（下拉关，
/// 与 `ExploreFilterSheet` 同一条 —— 它也没有关闭按钮，靠 `presentationDragIndicator`）。
///
/// ## ⚠️ 正文用 Markdown 渲染，不是纯文本
///
/// 与本仓其余长正文一致（README / Issue 正文 / PR 正文都走 `MarkdownBody`）：
/// release note 里常见的 `### 修复` 小标题、`- 列表`、`` `代码` `` 折成纯文本会掉信息。
/// 领域层已经把 `notes` 解析成 `notesBlocks`（解析在取数那一层做一次，
/// 不在 `body` 里重扫全文 —— 见 `MarkdownDocument` 的说明）。
///
/// ## ⚠️ 这里**不接** `onOpenLink`（与 README 那处有意不同）
///
/// README 必须接一次线，是因为它的链接大量是**仓库内的相对地址**（`[中文](README_zh.md)`），
/// 系统打不开一个没有 scheme 的地址、表现为"点了没反应"。
/// 而 release note 里的链接是 **GitHub 自动展开的绝对地址**（PR / issue / compare），
/// 没有一个需要 App 自己解析 ⇒ 全部交给系统打开即可（默认行为就是它）。
/// 真给一个 handler 反而要在这里复刻 `RepoLinkResolver` 的分派，而它没有用武之地。
struct ReleaseNotesSheet: View {

    /// 要展示的版本。⚠️ 取的是**调用方手上那一份**（`ExploreRepoDetailView` 的
    /// `model.insights.value?.release`）—— 本件不自己取数、也没有 ViewModel。
    let release: LatestRelease

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(LatestRelease.notesSheetTitle(tagName: release.tagName))

            // ⚠️ 正文进 `ScrollView`：release note 可以是任意长（几百行都见过）。
            //    不滚动的话它会从弹层底部溢出去，而溢出的部分**看起来像"说明就到这儿"**。
            ScrollView {
                MarkdownBody(blocks: release.notesBlocks)
                    // ⚠️ 2026-10-15 走查第 75 条起 `.document` 档**没有内边距**
                    //    （正文不再是一块面板）⇒ 左右由外面那圈弹层内边距给，这里只补上下两段。
                    .padding(.top, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.l)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.surface)
    }
}

#Preview {
    ReleaseNotesSheet(release: LatestRelease(
        tagName: "v2.1.0",
        notes: """
        ## 新增

        - 支持 GFM 表格
        - 搜索用户资料补全

        ## 修复

        修了单 `:` 分隔行的崩溃，以及若干小问题。
        """
    ))
    .background(Theme.Palette.background)
}
