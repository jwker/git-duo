import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 退出登录确认弹层（PRD §5.11、TECH_SPEC §3.6 / §9.15）。
///
/// 结构：标题 `退出登录？` → 说明段 → 红底「退出登录」→「取消」。
/// 原型出处：`scripts/13-auth.js` 的 `openSignOutSheet`（逐字）。
///
/// ## ⚠️ 说明段里那句括号是一个**可验证的承诺**
///
/// 「授权记录不再出现在 GitHub 设置里」—— 它不是客套：切片 1 的真机验收第 7 步
/// 验的就是它，而它是"**退出登录**"与"只是本机清掉"之间**唯一**的区别
/// （`ProfileCopy.signOutSheetHint` 的说明）。
///
/// ## ⚠️ 序号 ① 的动作是**先关弹层、再登出**
///
/// 登出会把 `authState` 打回未认证 ⇒ `RootView` 整个换掉主界面，而本弹层正挂
/// 在即将消失的那棵树上（`SettingsView`）—— 表现为"弹层被突然掀掉"。
/// 所以确认按钮**只回调**，由 `SettingsView` 把它记成一个标记，
/// 等 `.sheet(onDismiss:)` 真的走完再登出（同 `FileView` 那条"弹层关完才 pop"的先例）。
struct SignOutConfirmSheet: View {

    /// 「取消」—— 只关自己（`.sheet(item:)` 会顺手把路由值写回 `nil`）。
    ///
    /// ⚠️ 与其余几张弹层同一条：**确认走宿主、取消走 `dismiss()`**。
    @Environment(\.dismiss) private var dismiss

    /// 「退出登录」被按下。**不等结果**（同 `DeleteFileSheet.onConfirm`）——
    /// 等结果会让红按钮在用户眼前转很久，而这个动作本来就该
    /// "按下、关掉、回登录页"。
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(ProfileCopy.signOutSheetTitle)

            SheetHint(ProfileCopy.signOutSheetHint)

            ActionButton(
                title: ProfileCopy.signOutConfirmAction,
                style: .destructive,
                // 弹层底部的按钮统一 12（原型 `padding:12px`）。
                verticalPadding: 12,
                action: onConfirm
            )
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.m)

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
    SignOutConfirmSheet {}
        .background(Theme.Palette.background)
}
