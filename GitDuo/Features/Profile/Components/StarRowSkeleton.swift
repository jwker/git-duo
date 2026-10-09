import SwiftUI
import GitDuoDesign

/// 「我的 Star」列表的骨架（TECH_SPEC §8.5）。
///
/// ## 它为什么必须挨着 `StarRow`
///
/// §8.5 的硬要求是"**尺寸必须匹配真实布局**，避免数据到达时跳动"。
/// 而"尺寸匹配"这件事**没法靠断言守住**（Swift 单测没有布局引擎，量不出高度），
/// 只能靠**把两个文件放在一起**：改 `StarRow` 的间距时，眼睛一定能扫到旁边这个文件。
/// 同 `RepoCardSkeleton` 与 `RepoCard` 的处置。
///
/// ⚠️ 骨架属**内容层** ⇒ 实色、**不加玻璃**（§10.2）。
struct StarRowSkeleton: View {

    /// 占位的行数。默认 4 行 —— 首屏大约一屏多一点，够铺出"还有更多"的样子。
    var rows: Int = 4

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            ForEach(0..<rows, id: \.self) { _ in
                card
            }
        }
    }

    private var card: some View {
        // 原型 `.card{padding:14px}` ⇒ 与 `StarRow` 的 `CardBox(vertical: 14)` 逐字对齐。
        CardBox(vertical: 14) {
            HStack(spacing: 10) {
                SkeletonBar(
                    height: RepoAvatar.standard.diameter,
                    width: RepoAvatar.standard.diameter,
                    cornerRadius: RepoAvatar.standard.cornerRadius
                )
                VStack(alignment: .leading, spacing: 3) {
                    // 两行的宽度都照着 `StarRow`：全名那一行比副标题长。
                    SkeletonBar(height: 15, width: 168)
                    SkeletonBar(height: 11, width: 84)
                }
                Spacer(minLength: 0)
                // 右侧那颗按钮（`ActionButton` ghost，`padding:7px 12px`）。
                SkeletonBar(height: 27, width: 62, cornerRadius: Theme.Radius.control)
            }
        }
    }
}

#Preview {
    StarRowSkeleton()
        .padding(Theme.Spacing.page)
        .background(Theme.Palette.background)
}
