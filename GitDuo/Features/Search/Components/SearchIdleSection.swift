import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 搜索页的**空闲态** —— 未输入关键词时结果区显示的东西：最近搜索 + 热门关键词
/// （PRD §4.2「空闲态」；原型 `searchIdleHTML`）。
///
/// ## 它为什么不是"空态"
///
/// 空态说的是"搜了，但一条都没匹配上"（`EmptyBox` + `没有匹配「…」的…`）。
/// 这里说的是"还没开始搜"，而它给出的东西是**行动入口**（点一条历史直接复用关键词）。
/// 两者混用会让"我刚进页面就被告诉没结果"。
///
/// ## ⚠️ 2026-10-16 起它是**两个 `Section`**（NATIVE-MIGRATION P3）
///
/// 从前的形状是"一个 `VStack`：`SectionHeader` + `CardBox` 包一组历史行 + `SectionHeader`
/// + `FlowLayout` 一排热词"。主干换 `List` 之后，标题归 `Section` 的 header、
/// 历史行归 `Section` 的行（分隔线由系统画）、热词那一排是一行不坐白卡的"工具行"。
///
/// ⚠️ 一个自定义 `View` 的 `body` 是 `Section`，放进 `List` 会被**正常摊开**
/// （2026-10-16 宿主机探针实证：3 行 + 表头 ⇒ 4 个 `ListTableRowView`）。
///
/// ## ⚠️ 「清除」不弹确认层（PRD §4.2 明写）
///
/// 与「最近访问」的「清除全部记录」**有意不同**：那是浏览足迹（用户没打算留），
/// 这是用户**显式输入**的关键词 —— 意图明确，再问一次只是拦路。
/// 原型 `clearSearchHistory` 也是直接清 + toast。
struct SearchIdleSection: View {

    /// 最近搜索，**最新在前**（顺序由 `SearchHistoryStore` 保证）。
    let history: [String]

    let hotKeywords: [String]

    /// 点一条历史 / 一个热词 —— 直接复用关键词（原型 `useHistory` / `useHot`）。
    let onUse: (String) -> Void

    /// 点「清除」。
    let onClear: () -> Void

    var body: some View {
        historySection
        hotSection
    }

    // MARK: - 最近搜索

    @ViewBuilder
    private var historySection: some View {
        // ⚠️ 「清除」按钮**只在有记录时给**（原型就是如此：无记录那一支没有 `linkbtn`）。
        //    空列表上挂一个"清除"是给用户一件没有作用的东西点。
        Section {
            if history.isEmpty {
                EmptyBox(title: SearchCopy.emptyHistory, systemImage: "clock")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(history, id: \.self) { term in
                    // ⚠️ 这里**有意用默认按钮样式**（不带 `.buttonStyle(.plain)`）：
                    //    它在 `List` 行里 ⇒ 整行可点 + 按下高亮是系统给的，
                    //    而 `plain` 会把那份反馈一起删掉（P2 那条"plain 是正确选择"说的是
                    //    **不在列表里**的自绘行件）。
                    Button {
                        onUse(term)
                    } label: {
                        SearchRowBox {
                            Image(systemName: "clock")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.Palette.textTertiary)
                                .frame(width: 20)
                                .accessibilityHidden(true)

                            // 原型 `.t1` 在这里被覆写成 `font-size:14px;font-weight:500`
                            // ⇒ 取本仓最近的一档（`rowTitle` = `.subheadline`）再压一档字重。
                            Text(term)
                                .font(Theme.Font.rowTitle.weight(.medium))
                                .foregroundStyle(Theme.Palette.textPrimary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .listRowBackground(Theme.Palette.surface)
            }
        } header: {
            SectionHeader(
                title: SearchCopy.recentSectionTitle,
                actionTitle: history.isEmpty ? nil : SearchCopy.clearHistoryAction,
                action: history.isEmpty ? nil : onClear,
                margins: .none
            )
        }
    }

    // MARK: - 热门关键词

    @ViewBuilder
    private var hotSection: some View {
        Section {
            // 原型 `display:flex;flex-wrap:wrap;gap:8px` ⇒ `FlowLayout`。
            // chip 复用 `FilterChip`（原型这里用的就是 `.fchip` 那个类），
            // 但**不给尖角**（热词点了直接填，不打开任何弹层）也不高亮。
            FlowLayout(spacing: Theme.Spacing.s) {
                ForEach(hotKeywords, id: \.self) { keyword in
                    FilterChip(title: keyword, isHighlighted: false, showsChevron: false) {
                        onUse(keyword)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 一排 chip 不是"列表内容" ⇒ 不坐白卡、不画分隔线（同 `ExploreView` 的 chips 行）。
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            SectionHeader(title: SearchCopy.hotSectionTitle, margins: .none)
        }
    }
}

#Preview {
    NavigationStack {
        List {
            SearchIdleSection(
                history: ["swiftui", "next.js", "头像降采样", "Issues 标签"],
                hotKeywords: SearchHotKeywords.all,
                onUse: { _ in },
                onClear: {}
            )
            SearchIdleSection(
                history: [],
                hotKeywords: SearchHotKeywords.all,
                onUse: { _ in },
                onClear: {}
            )
        }
    }
}
