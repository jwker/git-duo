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
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(BranchCopy.createSheetTitle)

            SheetField(BranchCopy.createFieldPlaceholder(current: current), text: $name)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.top, Theme.Spacing.s)
                // 名字里的 `/`（`feature/x`）是合法的，且是 git 的常规用法 ——
                // 键盘上要够得到它（`SheetField` 默认关掉了自动大写，这里不额外改键盘类型）。
                .submitLabel(.done)

            if let failure {
                Text(failure)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.destructive)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.top, Theme.Spacing.s)
            }

            ActionButton(
                title: BranchCopy.createConfirmAction,
                style: .primary,
                verticalPadding: 12,
                isWorking: isWorking
            ) {
                Task { failure = await onCreate(name) }
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.m)

            ActionButton(title: BranchCopy.cancelAction, style: .ghost, verticalPadding: 12) {
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
    CreateBranchSheet(current: "main", isWorking: false) { _ in nil }
        .background(Theme.Palette.background)
}
