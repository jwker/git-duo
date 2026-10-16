import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 关闭 Issue 确认弹层（PRD §5.18、TECH_SPEC §9.8、决策 **#79**）。
///
/// 结构：标题 → 说明段 → 主色「关闭 Issue」→「取消」。
///
/// ## ⚠️ 它**没有原型参照**
///
/// 原型 `SCR.issueDetail` 里连操作区都没有（只有评论框 + 失败提示条），
/// 更不会有这张弹层 ⇒ 形态照既有的确认弹层走（§5.11）。
/// ⚠️ 2026-10-16 起那个先例**已换成系统 `.alert`**（NATIVE-MIGRATION P1）；
///    本件仍是自绘 sheet，因为它要装"进行中"状态，留到 P4（弹层那一期）一起改。
/// 已登记为有意偏差（偏差表第 **47** 条那条的一部分）。
///
/// ## ⚠️ 按钮是**主色、不是红底**（与 §5.11 退出登录那张有意不同）
///
/// 关闭一个 Issue 与退出登录不是一回事：前者**随时可以撤销** ——
/// 页面上就有一颗「重新打开 Issue」，而且作者身份本身就够（决策 #79）。
/// 红底传达的是"这一下不可逆"，用在这里是句假话。§5.11 那张用红底是因为
/// 它真的会清掉本机凭据并撤销 GitHub 侧授权。
///
/// ## ⚠️ 说明段那半句是一个**可验证的承诺**
///
/// 「仍然可以重新打开」说的是页面上那颗 `IssueCopy.reopenAction` 真的在 ——
/// 而它由 `IssueOperationAvailability` 保证（能关的人就能重开，两档走同一个判据）。
/// 把它说出来的用处是让用户**敢按下去**：不说的话，"关闭"看起来与"删除"没什么两样。
struct CloseIssueSheet: View {

    /// 「取消」—— 只关自己（`.sheet(item:)` 会顺手把路由值写回 `nil`）。
    @Environment(\.dismiss) private var dismiss

    /// 「关闭 Issue」被按下。
    ///
    /// ⚠️ **不等结果**（同 `SignOutConfirmSheet.onConfirm` 与 `DeleteFileSheet.onConfirm`）：
    /// 这一个动作**不需要**"关完弹层再做事"那种编排 —— 它不会换掉整棵视图树
    /// （登出才会），所以在途状态由**页面上的按钮**表达（`IssueDetailViewModel.isWorking`），
    /// 弹层只负责把用户的意思交出去、然后收起自己。
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(IssueCopy.closeSheetTitle)

            SheetHint(IssueCopy.closeSheetHint)

            ActionButton(
                title: IssueCopy.closeAction,
                style: .primary,
                // 弹层底部的按钮统一 12（原型 `padding:12px`）。
                verticalPadding: 12,
                action: onConfirm
            )
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.m)

            // ⚠️ 「取消」这两个字全项目同一串，直接复用设置页那一份 ——
            //    再写一个 `IssueCopy.cancelAction` 只会多一处将来要同步的副本。
            ActionButton(title: ProfileCopy.cancelAction, style: .ghost, verticalPadding: 12) {
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
    CloseIssueSheet {}
        .background(Theme.Palette.background)
}
