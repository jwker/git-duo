import GitDuoDesign
import SwiftUI

/// 清除最近访问确认弹层（PRD §5.1、原型 `scripts/04-search.js` 的 `openClearRecent`）。
///
/// ## ⚠️ 它**不是** `.confirmationDialog`
///
/// 2026-10-07 目视发现的第一条：原先这里用的是 `.confirmationDialog`，
/// 而它在本项目的目标平台（iPhone）上呈现为**屏幕底部的系统动作表** ——
/// 标题被压成一行小字、说明被塞在按钮底下，与原型那张"标题 + 说明 + 两个整宽按钮"
/// 的卡片对不上。
///
/// 原型 `openClearRecent()` 走的是 `openSheet(html)`，也就是**别处所有弹层同一套**
/// （`.sheet-mask` + `.sheet`，从底部升起的一张卡片），PRD §5.1 逐字给的也是那三行
/// （标题 / 说明 / 两个按钮）⇒ 事实优先级 原型 > TECH_SPEC > PRD 在这里结论一致：
/// 它就该是弹层，不是动作表。
///
/// 版式与 `DeleteBranchSheet` 逐条相同，本件**不复用**它 —— 两者的文案来源与
/// 确认动作完全不同，合成一件要再加两个参数，而每个参数两档里总有一档是错的。
struct ClearRecentSheet: View {

    /// 确认清除。**只做数据那一半** —— 弹层在它返回之后自己关。
    ///
    /// ⚠️ 不让调用方去改自己那个 `isPresented` 布尔量：那个闭包是异步的，
    /// 而 `@State` 只能在主 actor 上改 —— 依赖"闭包恰好继承了主 actor 隔离"
    /// 这种推断，是那种"本地能编、换个编译设置就报错"的写法。
    /// 弹层自己 `dismiss()` 没有这个问题，也和 `DeleteBranchSheet` 的
    /// "确认 → 关掉"次序逐条一致（那边是 VM 关，这里是本件关，都只有一处能关）。
    let onConfirm: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(HomeCopy.clearConfirmTitle)

            SheetHint(HomeCopy.clearConfirmHint)

            ActionButton(
                title: HomeCopy.clearConfirmAction,
                style: .destructive,
                verticalPadding: 12
            ) {
                Task {
                    await onConfirm()
                    dismiss()
                }
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.m)

            ActionButton(title: HomeCopy.clearConfirmCancel, style: .ghost, verticalPadding: 12) {
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
    ClearRecentSheet {}
        .background(Theme.Palette.background)
}
