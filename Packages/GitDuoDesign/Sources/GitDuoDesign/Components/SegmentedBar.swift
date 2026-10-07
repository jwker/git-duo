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
public struct SegmentedBar: View {

    /// 一个分段。`id` 供选中比对与 `ForEach` 稳定性，`title` 是显示文案。
    public struct Segment: Identifiable, Hashable, Sendable {

        public let id: String
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public let segments: [Segment]
    public let selectedID: String
    public let onSelect: (Segment) -> Void

    public init(
        segments: [Segment],
        selectedID: String,
        onSelect: @escaping (Segment) -> Void
    ) {
        self.segments = segments
        self.selectedID = selectedID
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(segments) { segment in
                    let isSelected = segment.id == selectedID
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
            .padding(.horizontal, Theme.Spacing.page)
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
    }
    .padding(.vertical, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
