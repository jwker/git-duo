import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 新建分支弹层（PRD §4.8「新建分支」那一项）。
///
/// 结构：标题 → 名字输入框 →（失败时）那一句话 → 「创建并切换」→「取消」。
///
/// ## ⚠️ 名字不合法是**表单校验**，不是网络错误
///
/// §9.7.1 把校验放在客户端（领域层 `BranchName` 纯函数）的理由就是这一条：
/// 服务端对不合法的名字只回一个 **422**，而 422 的文案读起来像"服务器坏了"，
/// 不像"你这个名字不能用"。
///
/// 所以这里**不**在输入框下方提前判红 —— 判据是 `BranchName` 那一套八条规则，
/// 而它们要等提交时才由 `CreateBranch` 跑一遍。本件只负责把返回的那句话显示在原地
/// （一句话 2.4 秒就消失的 toast 不适合承载"该怎么改"）。
///
/// ## 空名字也照样提交
///
/// 不预判"空 ⇒ 禁用按钮"：`BranchName.Issue.empty` 有一句自己的提示
/// （"分支名不能为空"），而一个点不动的按钮不会告诉用户为什么。
struct CreateBranchSheet: View {

    /// 从哪条分支创建（= 当前分支）—— 进输入框占位。
    let current: String

    let isWorking: Bool

    /// 执行创建。**返回失败时给用户看的那句话**；成功为 `nil`。
    let onCreate: (String) async -> String?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var failure: String?

    var body: some View {
        // P4：自绘弹层 → 原生 `Form` + `Section` + `TextField` + 系统 `Button`
        // （`SheetPrimitives` 五件退休，见 `NATIVE-MIGRATION.md` §P4）。
        // 标题用 `Section` header（原生次级灰字，不再大写）；输入框走原生 `TextField`
        // （分支名那档：关自动纠错、不大写）。
        Form {
            Section(BranchCopy.createSheetTitle) {
                TextField(BranchCopy.createFieldPlaceholder(current: current), text: $name)
                    // 名字里的 `/`（`feature/x`）是合法的，且是 git 的常规用法 ——
                    // 键盘上要够得到它（`SheetField` 默认关掉了自动大写，这里不额外改键盘类型）。
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            if let failure {
                Section {
                    Text(failure)
                        .foregroundStyle(Theme.Palette.destructive)
                        .multilineTextAlignment(.leading)
                }
            }

            Section {
                Button {
                    Task { failure = await onCreate(name) }
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(BranchCopy.createConfirmAction)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(BranchCopy.cancelAction) { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    CreateBranchSheet(current: "main", isWorking: false) { _ in nil }
        .background(Theme.Palette.background)
}
