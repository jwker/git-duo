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
/// ## ⚠️ 选中集合归**宿主**，不归本件
///
/// 本件只收 `selected`（只读，用来画 `✓`）并通过 `onToggle` 通知变化。
/// 理由：两处"变化之后要发生什么"不同，而那是宿主的决定 ——
/// 弹层自己存一份的话，两处就会出现**两份选中状态**，
/// 且它们会在"宿主重取数据之后"分叉（弹层那份还是旧的）。
///
/// ## ⚠️ 三条"新建"路径 + 一条"请求失败"，分成两个回调
///
/// §5.2 的校验两行 + 成功一路都是**正常产品路径**（`LabelCreation`，
/// 领域层刻意不让它们变成 `throw`），而请求真失败是另一类。
/// 两类分开报给宿主，宿主就能各给各的提示 —— 合成一个回调会让
/// "失败的提示"与"校验的提示"在某一处被写成同一句话。
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

    /// 新建的三条正常路径之一发生了（校验两行 / 成功一路）。
    let onCreation: (LabelCreation) -> Void

    /// 新建的请求本身失败（§5.2 **未给**这条路径的文案 ⇒ 由宿主给一句通用提示）。
    let onFailure: (GitHubError) -> Void

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
        onCreation: @escaping (LabelCreation) -> Void,
        onFailure: @escaping (GitHubError) -> Void
    ) {
        self.selected = selected
        self.onToggle = onToggle
        self.onCreation = onCreation
        self.onFailure = onFailure
        _model = State(initialValue: LabelPickerViewModel(catalog: catalog, fullName: fullName))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(title)

            labelList

            SheetTitle(IssueCopy.newLabelSectionTitle)
                // 原型那一段自己的 `margin-top:8px`。
                .padding(.top, Theme.Spacing.s)

            SheetField(IssueCopy.newLabelPlaceholder, text: $model.newName)
                .padding(.horizontal, Theme.Spacing.s)

            palettes
                // 原型 `margin:12px 0 4px`。
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xs)

            ActionButton(
                title: IssueCopy.createLabelAction,
                style: .primary,
                // 原型 `style="width:100%;padding:11px"`。
                verticalPadding: 11,
                isWorking: model.isCreating
            ) {
                Task { await create() }
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, 10)

            SheetHint(IssueCopy.labelSheetHint)

            Spacer(minLength: 0)
        }
        // 原型 `.sheet{padding:8px 10px 12px}`（同 `BranchSheet` / `DeleteBranchSheet`）。
        .padding(.horizontal, 10)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.surface)
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

    /// 标签可能上百条（`LabelCatalog.maxPages` × 100）⇒ 必须能滚。
    private func rows(_ labels: [GitDuoKit.Label]) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(labels) { label in
                    SheetRow(
                        // 原型 `07-issues.js:38` 的 `.lbl-dot`（leading 的色块形态）。
                        leadingDotColorHex: label.colorHex,
                        title: label.name
                    ) {
                        onToggle(label)
                    } trailing: {
                        if isSelected(label) {
                            // 原型：已选的那一行右边一个绿色 `✓`（`var(--green)` = `#1f883d`）。
                            // ⚠️ `Theme.Palette.accentStrong` 就是 `#1F883D` —— **不是新造的色**，
                            //    而且切片 6 的 `BranchSheet`（当前分支那个 `✓`）用的就是它。
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.Palette.accentStrong)
                        }
                    }
                    // 读屏：一行里"已选"这个状态没有可见文字承载（只有一个 `✓` 图形）。
                    .accessibilityHint(isSelected(label) ? IssueCopy.selectedLabelHint : "")
                }
            }
        }
        // 与 `BranchSheet` 同一条：行少的时候不让它变成可滚区域
        //（可滚但没得滚时，iOS 的下拉回弹会让人以为"下面还有"）。
        .scrollDisabled(labels.count <= 6)
    }

    /// 按**名字**比对（`Label.id` 就是名字 —— 同一仓库内唯一，§5.2 的"已存在则自动选中"）。
    private func isSelected(_ label: GitDuoKit.Label) -> Bool {
        selected.contains { $0.name == label.name }
    }

    // MARK: - 骨架 / 色板

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach(0..<4, id: \.self) { _ in
                SkeletonBar(height: 18, width: 160)
            }
        }
        // 原型 `.sheet-row{padding:12px 10px}` ⇒ 与真行左边缘对齐。
        .padding(.horizontal, 10)
        .padding(.top, Theme.Spacing.s)
        // 首帧骨架的行高（4 × 18 + 3 × 12 = 108）撑不住"换页之后再量"这件事，
        // 给一个最小高度，免得色板那一段在骨架消失时整体上跳一下。
        .frame(maxWidth: .infinity, alignment: .leading)
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
        let result = await model.create()

        // ⚠️ 先看失败：`create()` 返回 `nil` 有两种含义（重入 / 请求失败），
        //    而只有后者会留下 `createError`。分不清的话，请求失败会变成"点了没反应"。
        if let error = model.createError {
            onFailure(error)
            return
        }

        guard let result else { return }

        switch result {
        case .emptyName:
            // **不关**：用户还得接着打字。
            onCreation(result)

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
        onCreation: { _ in },
        onFailure: { _ in }
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
