import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 添加文件弹层（PRD §5.8、原型 `scripts/15-sheets.js` 的 `openAddSheet`）。
///
/// 结构：标题 `添加文件 · {当前分支}` → 三行（新建文件 / 上传文件 · 文件 App /
/// 上传图片 · 相册）→ 底部说明。
///
/// ## ⚠️ 它在本片**打不开**（决策 #51）
///
/// 唯一入口是代码分区面包屑右侧那个「＋ 添加」，而它在本片**画出但不可点**
/// （三个出口全属切片 8）。也就是说这张弹层现在是**为切片 8 预备的内容视图**：
/// 形态与文案已经定下来，切片 8 只需接上入口、把三行的 `action` 换掉。
///
/// 三个出口**全部**通到编辑器或提交弹层（§5.8），而编辑器（§4.6）也在切片 8，
/// 所以这里三行**都**不可点 —— 不是"其中两个还没做"。
///
/// ## ⚠️ 底部说明**不改回原型那一句**
///
/// 原型写 `大文件走 Git Data API（…上限 100MB）`，而 `TECH_SPEC §9.6`【已定】
/// 明确**不引入 Git Data API**、>1MB 的文件"本期不支持 → 提示并引导网页端"。
/// 照原型印就是让文案承诺一件实现做不到的事 —— 理由见 `RepoCopy.addFileSheetHint`。
struct AddFileSheet: View {

    /// 当前分支 —— 标题里那一句要它（原型 `添加文件 · ${curBranch()}`）。
    let branch: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(RepoCopy.addFileSheetTitle(branch: branch))

            // 三行共用一句 hint（它们点不动的原因是同一件事）。
            row(icon: GitHubIcon.file, title: RepoCopy.newFileAction)
            row(icon: GitHubIcon.file, title: RepoCopy.uploadFileAction)
            row(icon: GitHubIcon.file, title: RepoCopy.uploadImageAction)

            SheetHint(RepoCopy.addFileSheetHint)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.surface)
    }

    /// 一行。照决策 #51 先例：`allowsHitTesting(false)` + 去掉 `.isButton` trait +
    /// 一句 hint，**不是** `.disabled`（后者会变灰、看起来像"暂时不可用"）。
    ///
    /// ⚠️ 闭包必须是**真的什么都不做** —— `allowsHitTesting(false)` 挡的是触摸，
    /// 读屏的激活动作绕过命中测试。
    private func row(icon: String, title: String) -> some View {
        SheetRow(systemImage: icon, title: title, action: {})
            .allowsHitTesting(false)
            .accessibilityRemoveTraits(.isButton)
            .accessibilityHint(RepoCopy.addFileUnavailableHint)
    }
}

#Preview {
    AddFileSheet(branch: "feature/auth-refresh")
        .background(Theme.Palette.background)
}
