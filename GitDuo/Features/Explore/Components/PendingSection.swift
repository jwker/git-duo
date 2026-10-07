import SwiftUI
import GitDuoDesign

/// 页内占位块 —— 标注"这个分区属于另一个切片"（TECH_SPEC §9.11、PRD §4.13 的分片表）。
///
/// ## 它为什么不是"什么都不画"
///
/// 探索仓库详情有 8 个分区，其中 3 个（我的收藏 / 文件浏览 / README）**不属本切片**。
/// 整块不渲染的后果是评审者**看不出还差什么** —— 页面看起来是完整的，
/// 而"看起来完整"正是一个半成品最会造成的误判。
///
/// ## 它为什么不是假数据
///
/// 与 `SkeletonScreen` 同一条哲学（`AGENTS.md §0`：「没有假数据冒充成品」）：
/// 占位块明说归属与出处，一眼可辨。假数据的坏处不是"不好看"，
/// 而是它**会被当成已完成**，于是真做的时候没人再回来看。
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
        PendingSection(title: "文件浏览", note: "切片 6 落地 · 代码浏览")
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
