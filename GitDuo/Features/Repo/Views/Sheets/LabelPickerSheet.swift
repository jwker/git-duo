import GitHubAPI
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 标签选择 / 新建弹层（PRD §5.2、TECH_SPEC §9.8、决策 #56）。
///
/// 结构（原型 `scripts/07-issues.js` 的 `openLabelSheet`）：
/// 上段标题 `选择标签 · N 个` → 标签行（色块 + 名字 + 已选 `✓`）→
/// 下段标题 `新建标签` → 名称输入框 → 10 格色板 → 「创建并选中」→ 底部提示。
///
/// ## 一个弹层**两处用**（2026-10-08 用户裁定）
///
/// | 宿主 | 选中集合是什么 | 变化之后的后果 |
/// |---|---|---|
/// | §4.10 新建 Issue 页 | 这条 Issue 要带的标签 | 刷新标签行（不发请求） |
/// | §4.4 分区二「筛选」 | 要筛的标签（**走服务端**，决策 #56） | 结果区按新标签重新加载 |
///
/// 弹层本体**完全一样**（用户裁定的原话是"复用同一个弹层"）⇒
/// 本件不认识任何一个宿主，差别全在回调里。
///
/// ## ⚠️ 两条"没成"的路径**不再报给宿主**（2026-10-09 改口径，决策 #77）
///
/// 原先四条路径**全**报给宿主（三个 `onCreation` + 一个 `onFailure`），由宿主各给提示
/// —— 因为"弹层不认识提示通道"这条设计。而**提示条会被弹层整块盖住**：
/// 挂在根容器上，而弹层是一层独立呈现 ⇒ 空名与请求失败这两条**不关弹层**的路径
/// 表现成"点了没反应"（走查第 4 条）。现在它们改成**弹层内那一行**
/// （`SheetFailureHint`，位置在「创建并选中」按钮上方，读 `model.creationHint`）。
///
/// ⚠️ **剩下两条仍然报给宿主**：`.alreadyExists` / `.created` 会**关掉弹层** ⇒
/// 那两句照旧走提示条（弹层不在的时候看得见），而且宿主还要顺手把标签**选中**。
///
/// ## ⚠️ 选中集合归**宿主**，不归本件
///
/// 本件只收 `selected`（只读，用来画 `✓`）并通过 `onToggle` 通知变化。
/// 理由：两处"变化之后要发生什么"不同，而那是宿主的决定 ——
/// 弹层自己存一份的话，两处就会出现**两份选中状态**，
/// 且它们会在"宿主重取数据之后"分叉（弹层那份还是旧的）。
///
/// ## 弹层自己负责关不关
///
/// - `.emptyName` ⇒ **不关**（用户还得接着打字，关掉等于让他重开一次）；
/// - `.alreadyExists` / `.created` ⇒ 关（协议原型 `closeSheet()`）。
///
/// ⚠️ 本文件里领域层的标签一律写全 **`GitDuoKit.Label`**：`SwiftUI.Label` 与它**同名**，
/// 而本文件 import 了 SwiftUI ⇒ 裸写 `Label` 是硬歧义（详见 `SelectedLabelRow` 的说明）。
///
/// ## 加载失败与"确实没有标签"是两件事
///
/// `library == nil` + `loadError == nil` ⇒ 骨架；
/// `library != nil` + 空数组 ⇒ 那个仓库**确实一个标签都没有** ——
/// 此时**不加第二句空态文案**：标题那句 `选择标签 · 0 个` 已经把话说完，
/// 而 §5.2 与原型都没给这一处的第二句话（登记为"规格未给"，不擅自新造）。
struct LabelPickerSheet: View {

    /// 宿主手上已选中的标签（**只读**，用来画 `✓`）。
    let selected: [GitDuoKit.Label]

    /// 点一行 —— 增还是删由**宿主**决定（它才是选中集合的拥有者）。
    let onToggle: (GitDuoKit.Label) -> Void

    /// 这条新建**有结局了、而且弹层要关了**（重名 / 建成两档）。
    ///
    /// ⚠️ **它不含"名为空"那一档** —— 那一档弹层不关，话画在弹层里（`creationHint`）。
    /// 所以宿主拿到这个回调时通常要做两件事：给一句提示条 + 顺手选中那颗标签。
    let onCreation: (LabelCreation) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var model: LabelPickerViewModel

    /// - Parameters:
    ///   - catalog: 标签库用例。**只在初始化时用一次**（拿去建 `LabelPickerViewModel`）——
    ///     它**不存成属性**：存下来的话，读代码的人会以为本件后面还会用到"是哪个仓库"，
    ///     而它其实一个字都不再用（仓库全名由 ViewModel 持有）。
    ///   - fullName: 同上，只喂给 ViewModel。
    init(
        catalog: LabelCatalog,
        fullName: String,
        selected: [GitDuoKit.Label],
        onToggle: @escaping (GitDuoKit.Label) -> Void,
        onCreation: @escaping (LabelCreation) -> Void
    ) {
        self.selected = selected
        self.onToggle = onToggle
        self.onCreation = onCreation
        _model = State(initialValue: LabelPickerViewModel(catalog: catalog, fullName: fullName))
    }

    var body: some View {
        // P4：自绘弹层 → 原生 `Form`（`SheetPrimitives` 五件退休，见 `NATIVE-MIGRATION.md` §P4）。
        // 标签行 → `Form` 内的原生 `Button` 行（leading `LabelDot` + 标题 + 右侧 ✓）。
        // 两段标题 → `Section` header（系统默认即大写小灰，与原 `.sheet-title` 一致）。
        Form {
            Section {
                labelList
            } header: {
                Text(title)
            }

            Section {
                TextField(IssueCopy.newLabelPlaceholder, text: $model.newName)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                palettes
            } header: {
                Text(IssueCopy.newLabelSectionTitle)
            }

            // 决策 #77：两条"没成"的路径画在弹层内（空名 / 请求失败都不关弹层），
            // 而提示条挂在根容器上、会被弹层整块盖住（偏差第 45 条）。
            if let hint = model.creationHint {
                Section {
                    Text(hint)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.destructive)
                        .multilineTextAlignment(.leading)
                }
            }

            Section {
                Button { Task { await create() } } label: {
                    if model.isCreating {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(IssueCopy.createLabelAction)
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Section {
                Text(IssueCopy.labelSheetHint)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .multilineTextAlignment(.leading)
            }
        }
        .presentationDetents([.medium, .large])
        .task { await model.load() }
    }

    // MARK: - 上段标题

    /// ⚠️ 取回来之前**不写计数**（`labelSheetTitlePending`）：调色板里的 `· N 个`
    /// 是**数据**，还没问过服务端时写 `· 0 个` 等于告诉用户"这个仓库没有标签"（§8.5 末条）。
    private var title: String {
        guard let library = model.library else { return IssueCopy.labelSheetTitlePending }
        return IssueCopy.labelSheetTitle(count: library.count)
    }

    // MARK: - 标签行

    @ViewBuilder
    private var labelList: some View {
        if let library = model.library {
            // ⚠️ 空数组**什么都不画**（标题里的 `· 0 个` 已经是那句话，规格未给第二句）。
            if !library.labels.isEmpty {
                rows(library.labels)
            }
        } else if let error = model.loadError {
            // 复用分区失败块（`SectionFailure`）：文案与"重试"那个出口都只有一份实现。
            SectionFailure(error: error) { Task { await model.retry() } }
        } else {
            skeleton
        }
    }

    /// 标签可能上百条（`LabelCatalog.maxPages` × 100）⇒ 放进 `Form`，由它自身滚动。
    private func rows(_ labels: [GitDuoKit.Label]) -> some View {
        ForEach(labels) { label in
            Button { onToggle(label) } label: {
                HStack(spacing: 10) {
                    // 原型 `07-issues.js:38` 的 `.lbl-dot`（leading 的色块形态）。
                    LabelDot(colorHex: label.colorHex)

                    Text(label.name)
                        // 原型 14.5px/500 ⇒ 最近的一档是 `rowTitle`（`.subheadline` 15）。
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    if isSelected(label) {
                        // 原型：已选的那一行右边一个绿色 `✓`（`var(--green)`）。
                        // ⚠️ 文字色取 `success`（那对绿）—— **不是** `accentStrong`：
                        //    2026-10-17 主色统一为橙后，`accentStrong` 已经跟主色走、变橙了。
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.Palette.success)
                    }
                }
            }
            // 读屏：一行里"已选"这个状态没有可见文字承载（只有一个 `✓` 图形）。
            .accessibilityHint(isSelected(label) ? IssueCopy.selectedLabelHint : "")
        }
    }

    /// 按**名字**比对（`Label.id` 就是名字 —— 同一仓库内唯一，§5.2 的"已存在则自动选中"）。
    private func isSelected(_ label: GitDuoKit.Label) -> Bool {
        selected.contains { $0.name == label.name }
    }

    // MARK: - 骨架 / 色板

    /// 与 `BranchSheet` 同一条口径（NATIVE-MIGRATION P1）：渲染真实的 `rows(_:)`
    /// + 占位标签 + `.redacted`。
    ///
    /// ⚠️ 那条"给一个最小高度、免得上跳"的注释随灰条一起作废了：现在行高就是
    /// 原生 `Button` 行的真实行高，骨架与内容不可能差出高度。
    private var skeleton: some View {
        rows((0..<4).map { Label.placeholder(index: $0) })
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 10 格色板（`LabelPalette.hexes`）。
    ///
    /// ⚠️ 用 `FlowLayout` 而不是 `HStack`：10 × 30 + 9 × 8 = 372pt 在 iPhone 上放不下，
    /// `HStack` 会把它压扁（每格变小、间距消失），而"十格色板"这个产品承诺就没了。
    private var palettes: some View {
        FlowLayout(spacing: Theme.Spacing.s, lineSpacing: Theme.Spacing.s) {
            ForEach(LabelPalette.hexes, id: \.self) { hex in
                ColorSwatch(colorHex: hex, isSelected: hex == model.pickedColor) {
                    model.pickedColor = hex
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.s)
        // ⚠️ 不加这一句换行会失效（`FlowLayout` 拿到未指定宽度时按"一行放得下"算）。
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 新建

    private func create() async {
        // ⚠️ `nil` 现在只有一种含义（被在途守卫挡住 ⇒ 什么都不做）。
        //    原先它还有第二种（请求失败），那时要靠 `createError` 分 —— 现在失败
        //    自己写进 `creationHint`，分类这件事不需要了（见 `LabelPickerViewModel.create()`）。
        guard let result = await model.create() else { return }

        switch result {
        case .emptyName:
            // ⚠️ **不关**：用户还得接着打字。话已经由 ViewModel 写进 `creationHint`、
            //    画在按钮上方 —— **不再回调宿主**（回调了它也无事可做）。
            break

        case .alreadyExists, .created:
            onCreation(result)
            dismiss()
        }
    }
}

#Preview("标签库取不到") {
    LabelPickerSheet(
        catalog: LabelCatalog(source: PreviewLabels()),
        fullName: "my-git/gitduo",
        selected: [],
        onToggle: { _ in },
        onCreation: { _ in }
    )
    .background(Theme.Palette.background)
}

/// 预览用的空端点（`load()` 必然失败 ⇒ 走失败块那一路）。
private struct PreviewLabels: RepoLabelsDataSource {

    func labels(owner: String, repo: String, cursor: URL?) async throws -> Page<LabelDTO> {
        throw GitHubError.transport(URLError(.notConnectedToInternet))
    }

    func createLabel(
        owner: String,
        repo: String,
        name: String,
        color: String
    ) async throws -> LabelDTO {
        throw GitHubError.transport(URLError(.notConnectedToInternet))
    }
}
