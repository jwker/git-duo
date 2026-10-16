import SwiftUI

/// 分段控件 —— PRD §4.3、§4.12。
///
/// ## ⚠️ 2026-10-16（P2）：内胆换成官方的 `Picker` + `.pickerStyle(.segmented)`
///
/// 口径见 `NATIVE-MIGRATION.md`：**「按原型」= 功能按原型，视觉正本 = Apple HIG**。
/// 原型 `styles/03-components.css` 的 `.segbar` / `.seg`（容器无底色、选中项深底白字、
/// 按文字宽度横滑）已经作废 —— 白拿的是系统分段控件的等宽分格、滑动指示条、
/// 按下反馈、动态类型、以及"这是一组互斥选项"的读屏语义。
///
/// ⇒ **调用点的入参一个都没变**（`segments` / `selectedID` / `onSelect` 保持原样）。
///
/// ## ⚠️ 「动作格」不再是一格，而是右侧的一颗按钮
///
/// 原型里 `isAction` 那一格**长得和别的格一样**（`<button class="seg">筛选</button>`），
/// 只在行为上不同：点它不切档、而是打开弹层，且永不高亮。
///
/// `Picker` 里放不进"点不选中"的格 —— 它的每一项都是一个 `tag`，选中即切换
/// ⇒ 硬塞进去会导致"点了筛选，分段跳到筛选格"。所以那一格**移出 Picker**，
/// 画成右侧一颗独立的次要按钮（同 `ActionButton` 的 `.ghost` 那一档的观感）。
///
/// 这是**有意的形状变更**：从"长得像分段的一格"变成"分段条旁边的一个操作"。
/// HIG 里"分段 + 右侧动作"正是这个布局，而原型那种"一格里混两种行为"
/// 反而是自定控件才做的事。
///
/// ## ⚠️ 为什么长标签给 `minimumScaleFactor`
///
/// 系统分段控件**等分**整行（不再是原型的按内容宽横滑）。`CommitSheet` 那两档里有
/// 「提交到 {分支名}」，分支名一长就会顶破一格 ⇒ 给 `Text` 加
/// `lineLimit(1)` + `minimumScaleFactor`，只有放不下的那一格会缩字号
/// （折行会让等分的胶囊高度不一，比缩一号字难看得多）。
///
/// ## 它是内容层
///
/// 分段控件嵌在页面滚动内容里，**实色，不得加 Liquid Glass**（§10.2）。
public struct SegmentedBar: View {

    /// 一个分段。`id` 供选中比对与 `ForEach` 稳定性，`title` 是显示文案。
    public struct Segment: Identifiable, Hashable, Sendable {

        public let id: String
        public let title: String

        /// 这一格是**动作按钮**而不是分段（PRD §4.4 分区二的「筛选」）。
        ///
        /// ⚠️ 2026-10-16（P2）起它由 `Picker` **右侧的一颗独立按钮**承载，
        /// 不再是分段里的一格（理由见类型说明）。语义没变：
        /// **点它不改变选中项，它是一个打开弹层的入口**。
        ///
        /// ⚠️ 名字是 `isAction` 而不是 `isFilter`：分段条不认识"筛选"这个业务词 ——
        /// 判据 #43，设计包里只有与业务无关的视觉件。
        public let isAction: Bool

        public init(id: String, title: String, isAction: Bool = false) {
            self.id = id
            self.title = title
            self.isAction = isAction
        }
    }

    public let segments: [Segment]
    public let selectedID: String

    /// 是否自带页面水平边距（`Theme.Spacing.page`）。
    ///
    /// - `true`（默认）：分段条在**页面顶部**，靠这一层 padding 与下面的大标题左对齐
    ///   （仓库 Tab / 探索页 / 搜索页）。
    /// - `false`：分段条在**已经内缩的内容区**里（§4.4 两段、弹层），
    ///   再套一层会缩成 32pt、与同屏卡片的左边缘对不齐。
    ///
    /// ⚠️ 不把它做成"让调用方用负 padding 抵消"：那要求每个调用方都知道
    /// 这个组件内部藏了多少边距，而那个数字会随组件改版而变（错位的表现是
    /// 分段条比卡片宽出去一截，看起来像布局坏了）。
    public let padsHorizontally: Bool

    public let onSelect: (Segment) -> Void

    public init(
        segments: [Segment],
        selectedID: String,
        padsHorizontally: Bool = true,
        onSelect: @escaping (Segment) -> Void
    ) {
        self.segments = segments
        self.selectedID = selectedID
        self.padsHorizontally = padsHorizontally
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Picker("", selection: selection) {
                ForEach(selectableSegments) { segment in
                    Text(segment.title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .tag(segment.id)
                }
            }
            .pickerStyle(.segmented)
            // 标题是空的（`""`）⇒ 不隐藏会在控件上方留一行空白。
            .labelsHidden()

            // 「动作格」：一颗独立的次要按钮（见类型说明）。
            if let actionSegment {
                Button(actionSegment.title) {
                    onSelect(actionSegment)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, padsHorizontally ? Theme.Spacing.page : 0)
    }

    /// 参与 `Picker` 的分段（动作格不在其中）。
    private var selectableSegments: [Segment] {
        segments.filter { !$0.isAction }
    }

    /// 动作格（至多一个；多了只取第一个 —— 一个分段条上没有第二个"点开弹层"的位置）。
    private var actionSegment: Segment? {
        segments.first { $0.isAction }
    }

    /// 把只读的 `selectedID` + 回执闭包，翻成 `Picker` 要的 `Binding`。
    ///
    /// ⚠️ 只转发、**不落地本地状态** —— 选中项的唯一真相在调用方的 ViewModel 里。
    /// （这几处的 `select` 都是"先同步改 `segment`、再 await 取数"，所以点下去当帧就重绘。）
    private var selection: Binding<String> {
        Binding(
            get: { selectedID },
            set: { newValue in
                guard let picked = selectableSegments.first(where: { $0.id == newValue }) else {
                    return
                }
                onSelect(picked)
            }
        )
    }
}

#Preview {
    @Previewable @State var selection = "rising"

    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
        SegmentedBar(
            segments: [.init(id: "rising", title: "新星榜"), .init(id: "active", title: "活跃榜")],
            selectedID: selection
        ) { selection = $0.id }

        SegmentedBar(
            segments: ["全部", "公开", "私有", "Starred"].map { .init(id: $0, title: $0) },
            selectedID: selection
        ) { selection = $0.id }

        // §4.4 分区二那一档：两段 + 一格**动作**（「筛选」移到分段条右侧），
        // 且内容区已经内缩 ⇒ `padsHorizontally: false`。
        SegmentedBar(
            segments: [
                .init(id: "open", title: "开放 (12)"),
                .init(id: "closed", title: "已关闭"),
                .init(id: "filter", title: "筛选", isAction: true),
            ],
            selectedID: selection,
            padsHorizontally: false
        ) { picked in
            guard !picked.isAction else { return }
            selection = picked.id
        }

        // 长标签（`CommitSheet` 那一档）：只有放不下的那一格会缩字号。
        SegmentedBar(
            segments: [
                .init(id: "current", title: "提交到 feature/auth-refresh"),
                .init(id: "new-branch", title: "新分支 + PR"),
            ],
            selectedID: selection,
            padsHorizontally: false
        ) { selection = $0.id }
    }
    .padding(.vertical, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
