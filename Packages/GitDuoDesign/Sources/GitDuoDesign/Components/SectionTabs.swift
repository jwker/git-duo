import SwiftUI

/// 等宽分段切换条 —— 原型 `styles/04-screens.css` 的 `.prtabs`（PRD §4.4 第 2 条）。
///
/// ```css
/// .prtabs{display:flex;background:var(--chip);border-radius:9px;padding:3px;margin-bottom:12px}
/// .prtabs button{flex:1;border:none;background:transparent;border-radius:7px;
///                padding:7px 0;font-size:13px;font-weight:600;color:var(--text2)}
/// .prtabs button.on{background:#fff;color:var(--text);box-shadow:0 1px 3px rgba(0,0,0,.1)}
/// ```
///
/// ## ⚠️ 它与 `SegmentedBar` 是**两个不同的控件**，不是同一样东西的两种样式
///
/// | | `.prtabs`（本件） | `.segbar`（`SegmentedBar`） |
/// |---|---|---|
/// | 容器 | **有**底色（`--chip`）、3pt 内边距 | **没有**底色 |
/// | 选中项 | **白底** + 一点投影、字色转深 | **深底白字** |
/// | 宽度 | 4 项**等分**整行（`flex:1`） | 按文字宽度、**横滑** |
/// | 用在哪 | 仓库详情的四分区 | 仓库 Tab 的筛选段、探索榜、搜索范围 |
///
/// 把两者合成一个"带样式的 `SegmentedBar`"会让两种视觉里总有一种是错的，
/// 而错的那一种看起来仍然"像个分段控件" ⇒ 不会有人报上来。
///
/// ## 为什么它进设计包（判据 #43）
///
/// 入参只有 `[Item]`（`id` + `title` 两个基础类型）与一个回执闭包，
/// **不认识** `RepoSection` 或任何领域模型 ⇒ 满足"只收基础类型且与业务无关"。
///
/// ## ⚠️ 字号会为了塞进一行而缩一点（「规格未给，待评审」）
///
/// 原型是浏览器排版：`.prtabs button` 的 `flex:1` 在 393px 的机身上给每项约 90px，
/// 而 `Pull Requests` 在 13px semibold 下**正好卡在那个宽度上** ——
/// 浏览器会把它折成两行（原型的分段条因此比其余各页高一截），或者换个字体就刚好放得下。
/// SwiftUI 里折行会让四等分的胶囊**高度不一**（选中态的白底会变成两块高），
/// 比缩一号字难看得多，所以这里取 `lineLimit(1)` + `minimumScaleFactor`：
/// 只有放不下的那一项会缩小，其余各项仍按 13pt 画。
///
/// 已登记待评审：若评审要求"必须逐字 13pt、宁可折行"，去掉这两行即可。
///
/// ## 它是内容层
///
/// 分段条嵌在页面滚动内容里，**实色，不得加 Liquid Glass**（§10.2）。
public struct SectionTabs: View {

    /// 一项。`id` 供选中比对与 `ForEach` 稳定性，`title` 是显示文案。
    public struct Item: Identifiable, Hashable, Sendable {

        public let id: String
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public let items: [Item]
    public let selectedID: String
    public let onSelect: (Item) -> Void

    public init(
        items: [Item],
        selectedID: String,
        onSelect: @escaping (Item) -> Void
    ) {
        self.items = items
        self.selectedID = selectedID
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isSelected = item.id == selectedID
                Button {
                    onSelect(item)
                } label: {
                    Text(item.title)
                        .font(Theme.Font.footnote.weight(.semibold))
                        .foregroundStyle(
                            isSelected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        // 原型 `padding:7px 0`（纵向 7 不在 4pt 阶里 ⇒ 写原值并注明出处，
                        // 与 `SegmentedBar` 的 `7 / 14` 同一做法）。
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(
                            // 原型 `border-radius:7px` 用的是 7 —— 令牌里只有
                            // `Radius.branchChip`(7) 是这一档，沿用同一个值。
                            RoundedRectangle(cornerRadius: Theme.Radius.branchChip, style: .continuous)
                                .fill(isSelected ? Theme.Palette.surface : .clear)
                                // 原型 `box-shadow:0 1px 3px rgba(0,0,0,.1)` —— 只加在
                                // **选中的那一项**上（加在整条分段条上会把它画成一个浮起的板子，
                                // 而原型里浮起的是那一格白底）。
                                // 设计令牌里没有阴影档，故照原型写一次。
                                .shadow(
                                    color: isSelected ? .black.opacity(0.1) : .clear,
                                    radius: 1.5,
                                    y: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                // 读屏要能听出"当前选的是哪一段"—— 只靠底色变化，读屏用户收不到。
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        // 原型 `padding:3px`（3 不在 4pt 阶里 ⇒ 写原值）。
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.Palette.surfaceSunken)
        )
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    @Previewable @State var selection = "code"

    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
        SectionTabs(
            items: [
                .init(id: "code", title: "代码"),
                .init(id: "issues", title: "Issues"),
                .init(id: "prs", title: "Pull Requests"),
                .init(id: "commits", title: "Commits")
            ],
            selectedID: selection
        ) { selection = $0.id }

        SectionTabs(
            items: [.init(id: "open", title: "开放"), .init(id: "closed", title: "已关闭")],
            selectedID: selection
        ) { selection = $0.id }
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
