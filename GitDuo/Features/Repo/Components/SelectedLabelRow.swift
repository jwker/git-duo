import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 已选标签行 —— §4.4 分区二「筛选」筛出来的那几颗（PRD §4.4、决策 #56）。
///
/// ## ⚠️ 两处**形状相同、语义不同**（切片 7.4 起两处共用）
///
/// | 宿主 | 行内容 | 点一颗胶囊 | 末尾那颗按钮 |
/// |---|---|---|---|
/// | §4.4 分区二「筛选」 | 只有胶囊 | 取消那个筛选 | **没有**（「筛选」在分段条上） |
/// | §4.10 新建 Issue 页 | 胶囊 + 一颗 | 从这条 Issue 要带的标签里去掉它 | 「＋ 标签 / 新建」 |
///
/// 两处的**几何逐字相同**（`FlowLayout` + 折行 + `LabelPill`），差别只有两样，
/// 所以它们都是**参数**而不是第二份实现：
/// 末尾那颗按钮走 `onAdd`（`nil` = 不画），读屏提示走 `hint`。
///
/// ⚠️ `hint` **必传**（不给默认值）：两处点下去的结果不一样（一处是"取消筛选"、
/// 一处是"移除此标签"）—— 给它一个默认值，就等于让某一处悄悄用上另一处的话，
/// 而读屏用户听到的是一个**反的动作**，屏幕上完全看不出来。
/// 两句都落在领域层（`RepoIssuesSectionCopy.cancelFilterHint` /
/// `IssueCopy.removeLabelHint`），这样"有没有被写反"是一条可测的断言。
///
/// ## ⚠️ §4.4 的那一行为什么排在分段条**下方一行**，而不是"在分段条上"
///
/// PRD §4.4 分区二的原话是「已选标签在**分段条上**以标签胶囊呈现」，
/// 而 2026-10-08 用户裁定改成**另起一行**，两条理由：
///
/// - 分段条本身是**等宽横滑**的（`SegmentedBar` 的三格并列），往里塞任意多个标签
///   会把它撑变形，而"撑到几个才换行"没有答案；
/// - 「筛选」那一格是**按钮**、不是分段（同一份裁定）⇒ 分段条的选中态只属于
///   「开放 / 已关闭」两格。把标签混进那一行，会让"选中的到底是档位还是标签"
///   变成一个说不清的问题。
///
/// 已登记为**有意偏差**（偏 PRD 的分段语义、偏原型的排版）。
///
/// ## 点一颗胶囊 = 去掉它
///
/// ⚠️ **视觉上没有「×」** —— 这是**已知的可用性缺口**：胶囊看起来与别处的静态标签
/// 一模一样，视力用户看不出它可点，目前只有读屏那一句 hint 说了这件事。
///
/// ⚠️ 这条**已裁定**（2026-10-08，用户拍板**不加 ×**）：点胶囊本身即生效，
/// 形态保持原型的样子。补一个 × 要改 `LabelPill`（设计包的共用件，§4.10 的新建页
/// 与切片 8 都在用）⇒ 牵动一片，换来的只是"看起来可点"。
/// 将来若真要补：这一处加个 × + `LabelPill` 加一个可选参数即可，**不是重写**。
///
/// ## 判据 #43：它留 Feature
///
/// 参数是 `[Label]`（领域模型）⇒ 它认识业务，不进 `GitDuoDesign`。
///
/// ## ⚠️ 本文件里必须写 `GitDuoKit.Label`
///
/// `SwiftUI.Label` 与领域层的 `GitDuoKit.Label` **同名**。凡是同时
/// `import SwiftUI` 又 `import GitDuoKit` 的文件，裸写 `Label` 就是**硬歧义**
/// （`'Label' is ambiguous for type lookup in this context`）——
/// 好在它报错、不是静默选错一个。**判据：只要这个文件 import 了 SwiftUI，
/// 领域层的标签就必须写全 `GitDuoKit.Label`**；`RepoDetailViewModel` 那种不 import
/// SwiftUI 的文件照旧写 `Label`。改名的方案被否掉：`LabelCreation` / `LabelCatalog` /
/// `LabelLibrary` / `LabelPalette` 是一族同前缀的名字，只改其中一个会拆散它。
struct SelectedLabelRow: View {

    let labels: [GitDuoKit.Label]

    /// 点掉一颗 —— 参数是被点的那一颗。
    let onRemove: (GitDuoKit.Label) -> Void

    /// 点一颗胶囊会做什么（读屏用）。**必传**，理由见类型说明。
    let hint: String

    /// 行长到末尾那颗「＋ 标签 / 新建」按钮的文案。
    ///
    /// `nil` = **不画那颗按钮**（§4.4 的筛选行就是这一档 —— 它的「筛选」在分段条上）。
    ///
    /// ⚠️ 参数是**文案**而不是一个裸闭包：`nil` 与"有文案但点不动"必须是同一件事，
    /// 而两个独立参数（`onAdd` + `addTitle`）会造出"只给了一个"的中间状态。
    let addLabelTitle: String?

    /// 点那颗按钮。⚠️ 只有在 `addLabelTitle` 非空时才会被调用。
    let onAdd: (() -> Void)?

    /// ⚠️ **必须手写**：自动的 memberwise init **不会**给 `let` 可选属性 `nil` 默认值
    /// （只有 `var` 可选属性才会被隐式初始化）⇒ §4.4 那一处（没有末尾按钮的行）
    /// 就得显式写 `addLabelTitle: nil, onAdd: nil`。
    ///
    /// 两个参数都给 `nil` 默认值**不会**造出"只给了一个"的坏状态：
    /// 正文里那句 `if let addLabelTitle, let onAdd` 要求两个都在，
    /// 所以只传其中一个只是白传（画不出按钮），不会画出点不动的按钮。
    /// 同 `CommentRow.init` 的 `approvalTitle`。
    init(
        labels: [GitDuoKit.Label],
        onRemove: @escaping (GitDuoKit.Label) -> Void,
        hint: String,
        addLabelTitle: String? = nil,
        onAdd: (() -> Void)? = nil
    ) {
        self.labels = labels
        self.onRemove = onRemove
        self.hint = hint
        self.addLabelTitle = addLabelTitle
        self.onAdd = onAdd
    }

    var body: some View {
        FlowLayout(spacing: Theme.Spacing.xs, lineSpacing: Theme.Spacing.xs) {
            ForEach(labels) { label in
                Button {
                    onRemove(label)
                } label: {
                    LabelPill(name: label.name, colorHex: label.colorHex)
                }
                .buttonStyle(.plain)
                // 胶囊自身的读屏标签是「标签 bug」（`LabelPill` 给的），
                // 这一句补上"点了会怎样" —— 少了它，读屏用户听到的是一个不知道能干嘛的标签。
                .accessibilityHint(hint)
            }

            if let addLabelTitle, let onAdd {
                LabelAddButton(title: addLabelTitle, action: onAdd)
            }
        }
        // ⚠️ 不加这一句换行会失效（`FlowLayout` 拿到未指定宽度时按"一行放得下"算）。
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
        // §4.4 筛选行：只有胶囊、没有末尾按钮。
        SelectedLabelRow(
            labels: [Label(name: "bug", colorHex: "d73a4a")],
            onRemove: { _ in },
            hint: RepoIssuesSectionCopy.cancelFilterHint
        )
        // §4.10 新建页：多一颗「＋ 标签 / 新建」，提示语也不同。
        SelectedLabelRow(
            labels: [
                Label(name: "good first issue", colorHex: "8250df"),
                Label(name: "help wanted", colorHex: "0e8a16"),
                Label(name: "enhancement", colorHex: "a2eeef"),
            ],
            onRemove: { _ in },
            hint: IssueCopy.removeLabelHint,
            addLabelTitle: IssueCopy.addLabelAction,
            onAdd: {}
        )
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
