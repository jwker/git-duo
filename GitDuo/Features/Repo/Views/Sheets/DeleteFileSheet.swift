import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 删除文件确认弹层（PRD §5.17、决策 #66）。
///
/// 结构：标题 `删除「{文件名}」？` → 说明 → **警告行** → 红底「删除文件」→「取消」。
///
/// ## ⚠️ 它是一张**新**规格，原型里没有（与 §5.16 同一条）
///
/// 原型 `SCR.fileView` 的「更多」只给一句演示 toast。版式照
/// `DeleteBranchSheet`（原型 `06-files.js` 的 `deleteBranchAsk`：标题 + 说明 +
/// 红按钮 + 取消）—— 两张是同一类"对某个对象做一件不可逆的事"的确认层。
///
/// ## ⚠️ 说明那句是一句**承诺**，而它必须真的成立
///
/// `FileCopy.deleteSheetHint` 写的是"删除会立即在 {分支} 上生成一次提交"。
/// 那句承诺的落点是**领域层 `DeleteFile.run`**（一次真 `DELETE /contents`，
/// 服务端把它记成一次提交）—— 本件只是把话印出来。
///
/// ## ⚠️ 那一行警告与说明**不是同一件事**
///
/// - 说明说的是**会发生什么**（"会生成一次提交、本机不备份"）；
/// - 警告行说的是**能不能挽回**（"不可撤销"）。
///
/// 合成一句会让其中一半丢掉：用户可能读懂了"会生成提交"，
/// 却没意识到按下之后这件事不可逆。
///
/// ⚠️ `FileCopy.deleteWarning` 是**逐字**（PRD §5.17 原文里没有 `⚠`），
/// 所以这里不用 `NoticeBar` 惯常那种"文案自带警示符"的写法 ——
/// 那一行靠**底色**（`.danger` 那对令牌）表明它是警告。
///
/// ## ⚠️ 两个结局都由宿主处理（本件不含任何判断）
///
/// 「删掉了」与「现取版本标识时发现它已经不在了」都要关弹层、都要往回走一层
/// （PRD §5.17：后者**不报"删除失败"**）—— 那两句话由 `FileViewModel` 发，
/// 而"往回走"由 `FileView` 在弹层真的关掉之后做（见那边的说明）。
struct DeleteFileSheet: View {

    /// 标题里那个文件名（**只有文件名，不是完整路径** —— §5.17 逐字）。
    let fileName: String

    /// 说明里那个分支名。
    ///
    /// ⚠️ 它与 `FileViewModel.branch` 同源（本页取文件时解析出来的那一条）——
    /// 不重新解析：屏幕上写着 `main`、而这句话说另一条分支，是最难查的一种不一致。
    let branch: String

    let isWorking: Bool

    /// 确认删除。
    ///
    /// ⚠️ **没有返回值**：用户点了「删除文件」就是"照做"，
    /// 而那一步的成败/终态由 `FileViewModel.confirmDelete()` 负责说（toast）；
    /// "要不要往回走"也由它回给 `FileView`。
    ///
    /// ⚠️ 与 `DeleteBranchSheet.onConfirm` **同一个形状**（`() async -> Void`）：
    /// 两张弹层都不等一个结果 —— 等结果会让红按钮在用户眼前转圈转很久，
    /// 而这个动作本来就该"按下、关掉、结果用一条轻提示告诉你"。
    let onConfirm: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // P4：自绘弹层 → 原生 `Form`（`SheetPrimitives` 五件退休，见 `NATIVE-MIGRATION.md` §P4）。
        // `NoticeBar` 警告行属 P6 不动件，保留。
        Form {
            Section {
                // 说明（原 `SheetHint`）。
                Text(FileCopy.deleteSheetHint(branch: branch))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            } header: {
                Text(FileCopy.deleteSheetTitle(fileName: fileName))
            }

            // 警告行（§5.17 逐字）。紧贴红按钮 —— 它要起作用的位置就在那里。
            Section {
                NoticeBar(text: FileCopy.deleteWarning)
            }

            Section {
                Button {
                    Task { await onConfirm() }
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(FileCopy.deleteConfirmAction)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Palette.destructive)

                Button(FileCopy.cancelAction) { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    DeleteFileSheet(fileName: "AppTabs.swift", branch: "main", isWorking: false) {}
        .background(Theme.Palette.background)
}
