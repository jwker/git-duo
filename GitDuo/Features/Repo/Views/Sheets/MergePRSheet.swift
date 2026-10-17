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
        // P4：自绘弹层 → 原生 `Form`（`SheetPrimitives` 五件退休，见 `NATIVE-MIGRATION.md` §P4）。
        Form {
            Section {
                methods
            } header: {
                Text(PullCopy.mergeSheetTitle(branchFlow: branchFlow))
            }

            Section {
                Button(PullCopy.mergeConfirmAction(base: base)) { onConfirm(method) }
                    .buttonStyle(.borderedProminent)
            }

            Section {
                Text(PullCopy.mergeSheetHint)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - 三种方式

    /// 三行单选。
    ///
    /// ⚠️ 三行是**数据**（`PullCopy.mergeMethodOptions`）不是写三遍 ——
    /// "默认选中第一项"的可信来源就是那个数组的顺序（见 `MergeMethodOption` 的说明）。
    private var methods: some View {
        ForEach(PullCopy.mergeMethodOptions) { option in
            Button { method = option.method } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(option.title)
                            .font(Theme.Font.rowTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        // 原型 `<b class="mk" style="color:var(--green)">✓</b>` ——
                        // 与 `MergeSheet` 的选中标记同一形态（同一个 `success` + `checkmark`）。
                        // ⚠️ 2026-10-17 起是 `success` 而**不是** `accentStrong`：后者跟主色变成橙了。
                        Text(option.detail)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .padding(.top, Theme.Spacing.xxs)
                    }
                    Spacer(minLength: 0)
                    if option.method == method {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            // 原型 `color:var(--green)` ⇒ `success`（2026-10-17）。
                            .foregroundStyle(Theme.Palette.success)
                    }
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
