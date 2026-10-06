import SwiftUI
import GitDuoDesign

/// 仓库卡片的骨架形态（TECH_SPEC §8.5）。
///
/// ## 它为什么必须挨着 `RepoCard`
///
/// §8.5 的硬要求是"**尺寸必须匹配真实布局**，避免数据到达时跳动"。
/// 而"尺寸匹配"这件事**没法靠断言守住**（Swift 单测没有布局引擎，量不出高度），
/// 只能靠**把两个文件放在一起**：改 `RepoCard` 的间距时，眼睛一定能扫到旁边这个文件。
/// 把它挪进设计包，就等于把这份对应关系藏起来了。
///
/// ⚠️ 骨架属**内容层** ⇒ 实色、**不加玻璃**（§10.2）。
struct RepoCardSkeleton: View {

    /// 每张卡片的占位行数。默认 3 行（图标行 / 描述 / 标签行），与真实卡片一致。
    var rows: Int = 4

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(0..<rows, id: \.self) { _ in
                card
            }
        }
    }

    private var card: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            SkeletonBar(height: 36, width: 36, cornerRadius: Theme.Radius.chip)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SkeletonBar(height: 14, width: 180)
                SkeletonBar(height: 12)
                SkeletonBar(height: 12, width: 120)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Palette.borderSoft, lineWidth: 1)
        )
    }
}

#Preview {
    RepoCardSkeleton()
        .padding(Theme.Spacing.page)
        .background(Theme.Palette.background)
}
