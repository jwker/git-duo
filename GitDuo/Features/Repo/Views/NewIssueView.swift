import GitHubAPI
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 新建 Issue 页（PRD §4.10、TECH_SPEC §9.8、决策 #56 / #62）。
///
/// 结构（原型 `scripts/07-issues.js` 的 `SCR.newIssue`，五行、一个纵向流）：
/// 目标仓库说明 → 标题输入 → 正文输入 → 「标签」+ 标签行 → 「提交 Issue」。
///
/// ## ⚠️ 这一页**空得让人想去加点什么**，但原型就是这样
///
/// 没有头部卡、没有分段条、没有失败块、没有骨架屏 —— 它一个请求都不发
/// （`NewIssueViewModel` 的类型说明写了这为什么合理）。
/// 唯一可能出错的地方是最后那个请求，而它的后果只是一句 toast。
///
/// ## ⚠️ 两个输入框都是**共用件**，且两个都不是"另一个的名字"
///
/// 原型里 `#niTitle` 是 `class="sheet-input"`、`#niBody` 是 `class="code-editor"`
/// —— 而 `SheetField` 与 `CodeTextArea` 恰好就是这两份 CSS。
/// 所以这里用的是它们，而不是"因为这一页是页面所以另写一套输入框"。
///
/// ⚠️ 但 `SheetField` 的**文本行为**要显式改：它的默认档是给分支名 / 标签名定的
/// （不纠错、不自动大写），而标题是一句话 ⇒ 传 `disablesAutocorrection: false`
/// + `capitalization: .sentences`（见 `SheetField` 的类型说明）。
///
/// ## ⚠️ 标签行与 §4.4 的筛选行**是同一个组件、两个参数**
///
/// 差别只有两处：末尾多一颗「＋ 标签 / 新建」（`addLabelTitle`）、
/// 读屏提示不同（`hint`）。前者是弹层的入口，后者说的是"从要带的标签里去掉它"。
/// 详见 `SelectedLabelRow` 的说明。
///
/// ## 它是内容层
///
/// 全部实色，**不加 Liquid Glass**（§10.2）。
struct NewIssueView: View {

    let fullName: String

    /// 标签弹层的标签库（§5.2，与 §4.4 分区二**同一个**用例实例 —— 决策 #56）。
    let catalog: LabelCatalog

    /// 轻提示通道。本页有两处会用到它：提交失败、标签弹层的三条路径。
    let toast: ToastCenter

    @State private var model: NewIssueViewModel

    /// 标签弹层开没开。⚠️ 放在视图里而不是 ViewModel：它是**呈现状态**，
    /// 而 `LabelPickerSheet` 自己负责关（`.created` / `.alreadyExists` 时 `dismiss()`）。
    @State private var isPickingLabels = false

    /// 提交成功后退出这一页。
    ///
    /// ⚠️ 用 `@Environment(\.dismiss)` 而不是 `Router.pop()`：后者作用在
    /// **当前选中的 Tab** 上（`Router` 的说明），在这一层用它等于假设
    /// "这一页在哪条栈里"；而 `dismiss()` 只做一件事 —— 弹掉我自己。
    @Environment(\.dismiss) private var dismiss

    init(
        fullName: String,
        creator: CreateIssue,
        catalog: LabelCatalog,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.catalog = catalog
        self.toast = toast
        _model = State(initialValue: NewIssueViewModel(
            fullName: fullName,
            creator: creator,
            toast: toast
        ))
    }

    var body: some View {
        ScrollView {
            // 原型 `.content{display:flex;flex-direction:column;gap:10px}`。
            // ⚠️ 10 不在 4pt 阶里 ⇒ 写原值（本仓对这类间距的既有做法）。
            VStack(alignment: .leading, spacing: 10) {
                Text(IssueCopy.targetRepoLine(fullName: fullName))
                    // 原型 `.t3{font-size:11.5px}` ⇒ `Font.caption`（`.caption2` 11）。
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)

                SheetField(
                    IssueCopy.titlePlaceholder,
                    text: $model.draft.title,
                    // 标题是一句话 —— 见类型说明（`SheetField` 的默认档是给分支名定的）。
                    disablesAutocorrection: false,
                    capitalization: .sentences
                )

                CodeTextArea(IssueCopy.bodyPlaceholder, text: $model.draft.body)

                // 原型 `07-issues.js:23`：`<div class="section-label" style="margin:0">标签</div>`。
                // ⚠️ `margins: .none` —— 这一页的间距全部由外层那个 `gap:10px` 给，
                //    分区标题自带的上 16 / 下 8 会把它顶开（见 `SectionHeader.Margins`）。
                SectionHeader(title: IssueCopy.labelsSectionTitle, margins: .none)

                SelectedLabelRow(
                    labels: model.draft.labels,
                    onRemove: { model.removeLabel($0) },
                    hint: IssueCopy.removeLabelHint,
                    addLabelTitle: IssueCopy.addLabelAction,
                    onAdd: { isPickingLabels = true }
                )
                // 原型 `style="margin-top:-4px"`（那一行与「标签」的净间距是 6）。
                .padding(.top, -Theme.Spacing.xs)

                submitButton
            }
            .padding(.horizontal, Theme.Spacing.page)
            // 原型 `.screen.pushed .content{padding-top:16px}`；此处与
            // `IssueDetailView` / `RepoDetailView` 取同一档（本仓既有做法）。
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        .navigationTitle(IssueCopy.newIssueTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPickingLabels) {
            labelSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 提交

    private var submitButton: some View {
        // ⚠️ 按钮**任何时候都可点** —— 原型与 PRD §4.10 都没有"空内容则禁用"这一档
        //    （标题空 ⇒ 用占位标题照发）。理由写在 `NewIssueViewModel` 的类型说明里。
        ActionButton(
            title: IssueCopy.submitAction,
            style: .primary,
            // 原型 `style="width:100%;padding:12px"` —— 12 是原型原值覆写。
            // §8.5「操作类」：在途时按钮内联 loading + 禁用，防重复提交。
            isWorking: model.isSubmitting
        ) {
            Task {
                // 成功才退出：失败时**留在原地**，用户写的内容一个字都不丢。
                if await model.submit() != nil { dismiss() }
            }
        }
        .padding(.top, Theme.Spacing.xxs)
    }

    // MARK: - 标签弹层（§5.2）

    /// ⚠️ 与 `RepoDetailView` 里那一处**是同一个弹层**（用户裁定"复用同一个弹层"），
    /// 只是宿主不同 ⇒ 选中集合是"这条 Issue 要带的标签"，变化之后**不发请求**、只刷新标签行。
    private var labelSheet: some View {
        LabelPickerSheet(
            catalog: catalog,
            fullName: fullName,
            selected: model.draft.labels,
            onToggle: { label in
                // 点一行是**两向**的：已选则取消、未选则选中（`NewIssueDraft.toggle`）。
                model.toggleLabel(label)
            },
            onCreation: { result in
                // ⚠️ 走到这里的**只有关弹层的那两条**（重名 / 建成）—— 决策 #77：
                //    空名那一档弹层不关，话由弹层自己画在按钮上方，**不到这里来**。
                // 与 `RepoDetailView` 逐字相同：§7 的两句在领域层，这里只挑哪一句。
                switch result {
                case .emptyName:
                    // 到不了（弹层自己说）。留着这一档只是因为 `LabelCreation` 是穷举的；
                    // **这里不许再发一次提示** —— 两处都发会让同一件事说两遍，
                    // 而其中一遍（提示条）还被弹层盖着。
                    break
                case let .alreadyExists(label):
                    toast.show(IssueCopy.duplicateLabelToast)
                    // "已存在"的语义就是"给你用上它"：顺手选中那一颗。
                    if !model.isSelected(label) { model.toggleLabel(label) }
                case let .created(label):
                    toast.show(IssueCopy.labelCreatedToast(name: label.name))
                    if !model.isSelected(label) { model.toggleLabel(label) }
                }
            }
        )
    }
}

#Preview {
    @Previewable @State var environment = AppEnvironment()

    NavigationStack {
        NewIssueView(
            fullName: "my-git/gitduo",
            creator: environment.createIssue,
            catalog: environment.labelCatalog,
            toast: environment.toast
        )
    }
    .environment(environment)
}
