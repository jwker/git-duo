import SwiftUI
import GitDuoDesign

/// 骨架期占位屏 —— 明确显示"这一屏属于哪个切片"，而不是空白或假数据。
///
/// 设计意图：骨架阶段最大的风险是**假数据被误当成已完成**。
/// 因此占位屏一律显示切片归属 + 对应文档章节，评审时一眼可辨。
struct SkeletonScreen: View {

    let title: String
    /// 该屏将在哪个切片落地
    let slice: String
    /// 对应文档出处（PRD / TECH_SPEC 章节）
    let reference: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(title)
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Palette.textPrimary)

            Label(slice, systemImage: "hammer")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)

            Text(reference)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.page)
        .background(Theme.Palette.background)
    }
}

#Preview {
    SkeletonScreen(
        title: "搜索",
        slice: "切片 5 落地",
        reference: "PRD §4.2 / TECH_SPEC §9.2"
    )
}
