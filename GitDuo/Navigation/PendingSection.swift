import SwiftUI
import GitDuoDesign

/// 页内占位块 —— 标注"这个分区属于另一个切片"（TECH_SPEC §9.11、§9.4 决策 #50、PRD §4.13 的分片表）。
///
/// ## 它为什么不是"什么都不画"
///
/// 两个页面都有"本片不做"的分区，**且这份名单会随切片推进变短** ——
/// 用它的地方必须跟着改，留着过期的一行就是"页面看着完整、其实少一块"：
/// - 探索仓库详情（§4.13）8 个分区里，切片 4 只交了 5 个；6.4d 把「文件浏览」「README」
///   两处换成了真件（与 §4.4 共用 `RepoTreeSection`），现在只剩 **1 个**（我的收藏，切片 9）；
/// - 「我的仓库」详情（§4.4）4 个分区里有 2 个（Issues / Pull Requests）归切片 7（决策 #50）。
///
/// 整块不渲染的后果是评审者**看不出还差什么** —— 页面看起来是完整的，
/// 而"看起来完整"正是一个半成品最会造成的误判。
///
/// ## 它为什么不是假数据
///
/// 与 `SkeletonScreen` 同一条哲学（`AGENTS.md §0`：「没有假数据冒充成品」）：
/// 占位块明说归属与出处，一眼可辨。假数据的坏处不是"不好看"，
/// 而是它**会被当成已完成**，于是真做的时候没人再回来看。
///
/// ## 为什么它住在 `Navigation/` 而不是某个 Feature 里
///
/// 6.1–6.3 期间它住在 `Features/Explore/Components/`（当时只有 §4.13 用它）。
/// 6.4 起 §4.4 也要用 —— 两个互不相干的 Feature 共用一个类型时，
/// 它必须搬到两者之上；而它与 `SkeletonScreen` 是**同一类东西**
/// （施工进度标注），所以放在同一层。
///
/// ## 它是内容层
///
/// **实色、虚线边，不加 Liquid Glass**（§10.2）。
struct PendingSection: View {

    /// 分区标题（与真实分区同名 —— 这样对照 PRD 时能一一对上）。
    let title: String

    /// 落地切片的说明（`切片 9 落地 · 我的收藏属纯本地能力`）。
    let note: String

    var body: some View {
        SectionHeader(title: title)

        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "hammer")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.textTertiary)

            Text(note)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.m)
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .strokeBorder(
                    Theme.Palette.border,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        PendingSection(title: "我的收藏（私人整理 · 仅自己可见）", note: "切片 9 落地 · 收藏属纯本地能力")
        PendingSection(title: "编辑器", note: "切片 8 落地 · 新建 / 编辑单文件（PRD §4.6）")
        PendingSection(title: "Issues", note: "切片 7 落地 · 开放 / 已关闭筛选与新建 Issue（PRD §4.4 分区二）")
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
