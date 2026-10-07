import SwiftUI
import GitDuoDesign

/// 探索两个二级列表（Issues / PR）的首屏骨架屏（TECH_SPEC §8.5）。
///
/// 形状照着 `IssueCard` / `PullCard` 写：一行 = 卡片，卡片里是
/// **状态图标方块 + 标题条 + 副标题条**。两页的卡片几何是同一个
/// （原型 `10-explore-repo.js:120` 与 `:135` 的骨架一致），所以一份就够。
///
/// ⚠️ 尺寸必须跟着真实卡片的改动一起改（§8.5 第 1 条）：卡片里
/// `Theme.Spacing.s` 的间距与 `Theme.Font.rowTitle` 那一档字号一旦变了，
/// 这里的数字不跟，数据到达时整屏就会跳一下。
///
/// ⚠️ 它是内容层 ⇒ **只用实色**，绝不加 Liquid Glass（§10.2）。
struct ExploreSubListSkeleton: View {

    /// 画几条。默认 5 —— 首屏能填满一屏又不至于在数据到达时"多出几条凭空消失"。
    var count = 5

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            ForEach(0..<count, id: \.self) { _ in
                CardBox {
                    HStack(alignment: .top, spacing: Theme.Spacing.s) {
                        // 16pt 的正方形 —— 它对着的是 `Theme.Font.body` 那一档的
                        // SF Symbol，图标视觉高度大约就是这个数。
                        SkeletonBar(height: 16, width: 16, cornerRadius: Theme.Radius.chip)

                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            SkeletonBar(height: 14)
                            SkeletonBar(height: 11, width: 170)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ExploreSubListSkeleton()
        .padding(.horizontal, Theme.Spacing.page)
        .background(Theme.Palette.background)
}
