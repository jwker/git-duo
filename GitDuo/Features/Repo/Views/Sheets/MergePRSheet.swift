import GitHubAPI
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 合并 PR 弹层（PRD §5.3、TECH_SPEC §9.9、原型 `openMergeSheet`）。
///
/// 结构（原型 `08-pr.js:110-122` 逐块对应）：
/// 标题 → 三种合并方式（单选，默认第一项）→ 确认按钮 → 底部提示。
///
/// ## ⚠️ 它与 `MergeSheet`（合并**分支**）是两张不同的弹层，不要合并
///
/// | | `MergeSheet`（§4.8，决策 #52） | 本件（§5.3） |
/// |---|---|---|
/// | 合并的是什么 | 两条**本地分支**（`POST …/merges`） | 一个 **PR**（`PUT …/pulls/{n}/merge`） |
/// | 关键输入 | 源分支**可选** + 目标分支只读 | **合并方式**三选一 |
/// | 目标从哪来 | 当前分支（PRD 明写只读） | PR 自己的 `base.ref` |
/// | 可选提交信息 | 有 | **没有** |
///
/// 两者的字段集**没有一处重合**（一个是"哪条分支"，一个是"怎么合"）——
/// 合成一张"合并弹层"意味着四个可选参数加两条分支判断，
/// 而"多出来一个不该出现的输入框"在屏幕上看起来完全正常。
///
/// ## ⚠️ 成败都**不**由本件关弹层
///
/// 与 `MergeSheet` 同一条处置：本件只把用户选的那一种方式交出去
/// （`onConfirm`），关弹层与后续（请求 / 提示 / 刷新）都在宿主。
///
/// 宿主的选择是**确认即关**（原型 `doMerge()` 就是 `closeSheet()` 然后 toast）——
/// 那也顺带避开一个真实的坑：提示条挂在 Tab 那一层，
/// **弹层盖着的时候弹出来的提示用户看不见**。
///
/// ## 它是内容层
///
/// 全部实色，**不加 Liquid Glass**（§10.2）—— 弹层自身的材质由系统
/// `presentationDetents` 提供。
struct MergePRSheet: View {

    /// `feature/repo-hub → main`（标题要的那一截）。
    let branchFlow: String

    /// 目标分支名（确认按钮上那句 `确认合并进 main` 只要它）。
    let base: String

    /// 用户点了确认。参数是他选中的合并方式。
    let onConfirm: (PullMergeMethod) -> Void

    /// 选中的方式。**初值 = 第一项**（原型 `i===0 ? '✓' : ''`），
    /// 而"第一项是谁"由 `PullCopy.defaultMergeMethod` 说了算 ——
    /// 这里写 `.merge` 的话，哪天把 `rebase` 挪到第一行，弹层里亮着的还会是 `Merge commit`。
    @State private var method: PullMergeMethod = PullCopy.defaultMergeMethod

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(PullCopy.mergeSheetTitle(branchFlow: branchFlow))

            methods

            ActionButton(
                title: PullCopy.mergeConfirmAction(base: base),
                style: .primary,
                // 原型 `style="width:100%;padding:12px"` —— 弹层底部的确认按钮统一 12。
                verticalPadding: 12
            ) {
                onConfirm(method)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.m)

            SheetHint(PullCopy.mergeSheetHint)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.surface)
    }

    // MARK: - 三种方式

    /// 三行单选。
    ///
    /// ⚠️ 三行是**数据**（`PullCopy.mergeMethodOptions`）不是写三遍 ——
    /// "默认选中第一项"的可信来源就是那个数组的顺序（见 `MergeMethodOption` 的说明）。
    ///
    /// ⚠️ `action:` 这个标签**必须写出来**：本行右侧要放那颗 ✓，
    /// 而省略它会让尾随闭包绑到不带标签的那个 `init` 上，图标根本不画
    /// （`SheetPrimitives` 里那条陷阱的说明）。
    private var methods: some View {
        ForEach(PullCopy.mergeMethodOptions) { option in
            SheetRow(
                title: option.title,
                subtitle: option.detail,
                action: { method = option.method }
            ) {
                // 原型 `<b class="mk" style="color:var(--green)">✓</b>` ——
                // 与 `MergeSheet` 的选中标记同一形态（同一个 `accentStrong` + `checkmark`）。
                if option.method == method {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Palette.accentStrong)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        MergePRSheet(branchFlow: "feature/repo-hub → main", base: "main") { _ in }
    }
    .background(Theme.Palette.background)
}
