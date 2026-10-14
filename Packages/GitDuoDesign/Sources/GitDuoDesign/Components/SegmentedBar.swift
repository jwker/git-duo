import SwiftUI

/// 分段控件 —— 原型 `styles/03-components.css` 的 `.segbar` / `.seg`（PRD §4.3、§4.12）。
///
/// ## 外观逐字取自原型
///
/// ```css
/// .segbar{display:flex;gap:6px;overflow-x:auto}
/// .seg{flex-shrink:0;background:var(--chip);border-radius:8px;padding:7px 14px;
///      font-size:13px;font-weight:600;color:var(--text2)}
/// .seg.on{background:var(--text);color:#fff}
/// ```
///
/// ⇒ 容器**没有**底色（每个分段自己带 `surfaceSunken` 底），选中项是**深底白字**
/// （`textPrimary`，不是强调绿）。字号 13pt semibold 正好是系统 `.footnote` 那一档。
///
/// ## ⚠️ 它修掉了一处偏差
///
/// 切片 3 的仓库 Tab 曾自行做成"绿色胶囊"（`accentStrong` + `Capsule`）——
/// 与原型不符，且形状（胶囊 vs 8pt 圆角）与配色（绿 vs 深灰）两处都不同。
/// 2026-10-06 用户拍板：**两处都改回原型**，故本节收起为组件，仓库 Tab 与探索页共用。
///
/// ## 为什么横滑
///
/// 原型 `.segbar{overflow-x:auto}`：分段项多起来（搜索页有 4 个范围）时宁可横滑，
/// 也不换行 —— 换行会让"这一屏有几个分段"随文字长度变化，看起来像布局坏了。
///
/// ## 它是内容层
///
/// 分段控件嵌在页面滚动内容里，**实色，不得加 Liquid Glass**（§10.2）。
///
/// ## 切片 7 补的两个能力（PRD §4.4 分区二）
///
/// 上面那三处调用点**一个字都没改**（两个新参数都有保持原行为的默认值）：
///
/// | 参数 | 默认 | 给谁用 |
/// |---|---|---|
/// | `Segment.isAction` | `false` | §4.4 分区二的第三格「筛选」—— 长得像分段、行为是按钮、永不高亮 |
/// | `padsHorizontally` | `true` | `false` 给"已经在内容区里"的分段条（§4.4 两段），免得边距叠成两倍 |
///
/// ⚠️ 这两条都是"同一个组件在两处的差别"，不是两个组件：形状（字号 / 内边距 / 圆角 /
/// 选中配色 / 横滑）**只有这一份实现**。
public struct SegmentedBar: View {

    /// 一个分段。`id` 供选中比对与 `ForEach` 稳定性，`title` 是显示文案。
    public struct Segment: Identifiable, Hashable, Sendable {

        public let id: String
        public let title: String

        /// 这一格是**动作按钮**而不是分段（切片 7 新增，PRD §4.4 分区二的「筛选」）。
        ///
        /// ## 为什么把它收进 `Segment`，而不是另开一个"尾随视图"参数
        ///
        /// 它在**外观上就是同一格**：原型 `05-repo.js:234-236` 那三个 `.seg` 是并列等宽的，
        /// 「筛选」也是其中之一（`<button class="seg" onclick="segPick(this)">筛选</button>`）。
        /// 差别只在**行为** —— 点它不改变选中项，而是打开一个弹层；
        /// 于是它**永远不该显示选中态**。
        ///
        /// 做成尾随视图会让"它长什么样"与分段条分家（自己排的宽度与其它格对不齐、
        /// 字号与内边距要各写一遍），而把这点差别收进一个布尔量，形状仍然只有一份实现。
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
    /// ## 默认 `true` 是给"页面顶部"那种用法
    ///
    /// 仓库 Tab / 探索页 / 搜索页三处的分段条都在**页面顶部**：它贴边横滑，
    /// 靠这一层 padding 与下面的大标题左对齐。
    ///
    /// ## `false` 是给"已经内缩的内容区"
    ///
    /// §4.4 两段（分区二 / 分区三）的分段条在 `.content` 里面，而 `.content` 自带
    /// 水平边距 —— 再套一层就成了 32pt 的缩进，与同屏的卡片左边缘对不齐。
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(segments) { segment in
                    // ⚠️ 动作格**永远不高亮**：它没有"被选中"这个状态
                    //    （选中态是"这一档正在显示"的意思，而它不切任何东西）。
                    //    少了后面那半句，`selectedID` 与它的 `id` 相同时它会亮起来
                    //    —— 而那看起来完全正常（用户以为自己筛上了）。
                    let isSelected = segment.id == selectedID && !segment.isAction
                    Button {
                        onSelect(segment)
                    } label: {
                        Text(segment.title)
                            .font(Theme.Font.footnote.weight(.semibold))
                            .foregroundStyle(
                                isSelected ? Theme.Palette.surface : Theme.Palette.textSecondary
                            )
                            // 原型 `.seg{padding:7px 14px}` —— 7 / 14 是原型原值，
                            // 4pt 间距阶里没有这两档，故写原值并注明出处（与 `RepoCard`
                            // 的 `.padding(.horizontal, 14)` 同一做法）。
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.segment, style: .continuous)
                                    .fill(isSelected ? Theme.Palette.textPrimary : Theme.Palette.surfaceSunken)
                            )
                    }
                    .buttonStyle(.plain)
                    // 读屏要能听出"当前选的是哪个"—— 只靠底色变化，读屏用户是收不到的。
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, padsHorizontally ? Theme.Spacing.page : 0)
        }
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

        // §4.4 分区二那一档：两段 + 一格**动作**（「筛选」永不显示选中态），
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
    }
    .padding(.vertical, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
