import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 重命名（移动）文件弹层（PRD §5.16、决策 #66）。
///
/// 结构：标题 `重命名文件` → 路径输入框（**预填当前完整路径**）→ 说明行
/// →（失败时）那一句话 → 「保存」→「取消」。
///
/// ## ⚠️ 它是一张**新**规格，原型里没有
///
/// 原型 `SCR.fileView` 的「更多」只给一句演示 toast
/// （`toast('演示：重命名 / 删除（带 sha 校验）')`）。原型里**唯一**可比的是
/// 收藏夹重命名（`11-favorites.js` 的 `renameFolderForm`，§5.13）——
/// 那张的表单是「标题 + 预填输入框 + 保存 + 取消」，与本节逐字同形；
/// 本件按它写，PRD 多给的那一条是**说明行**。
///
/// ## ⚠️ 它**只交出用户原样输入的那串字**
///
/// 校验（空 / 没改 / 某一级非法）一个字都不在这里：
/// `FileViewModel.rename(input:)` 过一遍 `RepoPath.resolveRenameDestination`
/// —— 那三条判据与"服务端会怎么解释这串字"绑在一起（`a//b` 在服务端是另一条路径），
/// 属于领域层的事。
/// 本件因此**不能**说"空路径 ⇒ 禁用按钮"：一颗点不动的按钮不会告诉用户为什么，
/// 而那里有一句现成的话（`FileCopy.renameEmptyHint`，同 `CreateBranchSheet` 的处置）。
///
/// ## ⚠️ 关弹层的责任**全在宿主**（这一条踩过）
///
/// 成功与"用户什么都没改"两档都由宿主机把 `sheet` 置空，本件**不调 `dismiss()`**。
/// 自己关的后果见 `FileViewModel.sheet` 的说明：呈现关掉了、而路由值还停在 `.rename`
/// ⇒ 用户再点一次「重命名」时弹层**不再出现**（要呈现的东西与正在呈现的是同一个值）。
struct RenameFileSheet: View {

    /// 当前路径 —— 输入框的预填值就是它的**完整路径**（§5.16 逐字）。
    ///
    /// ⚠️ 用 `raw` 而**不是** `displayName`：后者只有最后一段。
    /// 这一屏的输入框接受任意相对路径（可以顺带把它挪进另一层目录），
    /// 只给文件名的话用户一按保存就等于把文件挪到了仓库根目录。
    let source: RepoPath

    let isWorking: Bool

    /// 提交那串字。**返回要显示在输入框下方的那句话**；`nil` = 弹层该关了。
    ///
    /// ⚠️ `nil` 有两档（见 `FileViewModel.rename(input:)`）：办成了（有 toast）、
    /// 以及"用户压根没改路径"（§5.16 明写**直接关闭、不提示**）。
    let onRename: (String) async -> String?

    @Environment(\.dismiss) private var dismiss

    @State private var newPath: String
    @State private var failure: String?

    init(
        source: RepoPath,
        isWorking: Bool,
        onRename: @escaping (String) async -> String?
    ) {
        self.source = source
        self.isWorking = isWorking
        self.onRename = onRename
        // ⚠️ **预填的是真值不是占位符**：用户不改就能直接提交（§5.16）。
        //    所以 `SheetField` 的 placeholder 是空串 —— 写一句"输入新路径"会在
        //    框里已经有一串字的时候被误读成"这里还没填"。
        _newPath = State(initialValue: source.raw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(FileCopy.renameSheetTitle)

            SheetField("", text: $newPath)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.top, Theme.Spacing.s)
                // 路径里的 `/` 是常规用法（`docs/guide.md`）——
                // 键盘上要够得到它（`SheetField` 默认关掉自动大写与纠错，这里不额外改）。
                .submitLabel(.done)

            // 说明行（§5.16 逐字）。放在输入框与按钮之间：
            // 它说的是"按下保存会发生什么"，紧贴按钮才读得顺。
            SheetHint(FileCopy.renameSheetHint)

            if let failure {
                // ⚠️ 这一段原先**裸写在这里**（`Text` + 四个修饰符），2026-10-09 收拢进
                //    `SheetFailureHint`（决策 #77）—— 同样的那四行马上要出现在第 5 处
                //    （收藏夹新建 · 两个入口 / 收藏夹重命名 / 标签新建 · 两个宿主），
                //    再抄三遍就是四份会各自漂移的副本。**形态逐字不变**。
                //
                // ⚠️ 本件是那个形态的**出处**：它原型里没有（§5.16 是新规格，决策 #66），
                //    当时只能自己定一行 —— 定的就是这个。于是"没有原型参照"的那一次自拟，
                //    成了"有原型"那几处（§5.2 / §5.6 / §5.13）的依据。
                SheetFailureHint(failure)
            }

            ActionButton(
                title: FileCopy.renameConfirmAction,
                style: .primary,
                // 弹层底部的确认按钮统一 12（原型 `.browser-body .btn{padding:12px}`）。
                verticalPadding: 12,
                isWorking: isWorking
            ) {
                Task { failure = await onRename(newPath) }
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.m)

            ActionButton(title: FileCopy.cancelAction, style: .ghost, verticalPadding: 12) {
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
    RenameFileSheet(
        source: RepoPath(path: "GitDuo/Features/Repo/Views/FileView.swift"),
        isWorking: false
    ) { input in
        input.isEmpty ? FileCopy.renameEmptyHint : nil
    }
    .background(Theme.Palette.background)
}
