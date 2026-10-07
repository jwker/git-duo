import SwiftUI
import GitDuoDesign

/// 置顶网格的骨架形态（TECH_SPEC §8.5）。
///
/// ## 为什么必须挨着 `PinCard`
///
/// 同 `RepoCardSkeleton` 的理由：§8.5 的硬要求是"尺寸必须匹配真实布局，
/// 避免数据到达时跳动"，而"尺寸匹配"**没法靠断言守住**（Swift 单测没有布局引擎），
/// 只能把两个文件放得足够近 —— 改 `PinCard` 的间距时眼睛一定扫得到这里。
///
/// ⚠️ 骨架属**内容层** ⇒ 实色、**不加玻璃**（§10.2）。
struct PinGridSkeleton: View {

    /// 占位几张卡。置顶上限 6 ⇒ 默认铺满一屏能见到的 4 张。
    var count: Int = 4

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: Self.spacing) {
            ForEach(0..<count, id: \.self) { _ in
                card
            }
        }
    }

    /// 与 `HomeView.pinGrid` **共用同一组列定义** —— 列宽不一致会让数据到达时左右跳动。
    static let columns = [
        GridItem(.flexible(), spacing: spacing),
        GridItem(.flexible(), spacing: spacing),
    ]
    static let spacing: CGFloat = 10

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 名字行 —— `PinCard` 在这一行是 15pt 字形 + 13pt 粗体文字。
            SkeletonBar(height: 14, width: 96)
            // 描述：固定两行高（`PinCard` 用的是 `lineLimit(2, reservesSpace: true)`）。
            SkeletonBar(height: 11, width: 132).padding(.top, 9)
            SkeletonBar(height: 11, width: 84).padding(.top, 4)
            // 指标行（语言 / Star / Fork）。
            SkeletonBar(height: 11, width: 110).padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .stroke(Theme.Palette.borderSoft, lineWidth: 1)
        )
    }
}

#Preview {
    PinGridSkeleton()
        .padding(Theme.Spacing.page)
        .background(Theme.Palette.background)
}
