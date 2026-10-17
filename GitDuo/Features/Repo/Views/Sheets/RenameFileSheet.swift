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
        // P4：自绘弹层 → 原生 `Form`（`SheetPrimitives` 五件退休，见 `NATIVE-MIGRATION.md` §P4）。
        // 说明行（`SheetHint`）作为输入框 Section 的 footer，保持「紧贴输入框下方」的位置。
        Form {
            Section {
                TextField("", text: $newPath)
                    // 路径里的 `/` 是常规用法（`docs/guide.md`）——
                    // 键盘上要够得到它（`SheetField` 默认关掉自动大写与纠错，这里不额外改）。
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Text(FileCopy.renameSheetTitle)
            } footer: {
                Text(FileCopy.renameSheetHint)
                    .font(Theme.Font.caption)
            }

            if let failure {
                // 弹层内"这一下没成"的那一行（决策 #77）：位置在确认按钮上方、
                // 读屏能看见，而不是被弹层整块盖住的页面级提示条。
                Section {
                    Text(failure)
                        .foregroundStyle(Theme.Palette.destructive)
                        .multilineTextAlignment(.leading)
                }
            }

            Section {
                Button {
                    Task { failure = await onRename(newPath) }
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(FileCopy.renameConfirmAction)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(FileCopy.cancelAction) { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .presentationDetents([.medium, .large])
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
