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
        // 方案 D：行间 hairline 由行自己画（顶上那条），骨架同样首行不画。
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                card(showsTopSeparator: index > 0)
            }
        }
    }

    private func card(showsTopSeparator: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            // ⚠️ 这两行尺寸**跟着 `RepoCard` 一起改**（2026-10-06：36/r6 浅底 → 34/r9 深底）。
            //    §8.5 要求骨架"尺寸必须匹配真实布局"，否则数据到达时整屏会跳一下，
            //    而"跳一下"这件事单测量不出来（没有布局引擎），只能靠两处一起改。
            SkeletonBar(
                height: RepoAvatar.standard.diameter,
                width: RepoAvatar.standard.diameter,
                // ⚠️ 2026-10-15 起占位块也是**圆的**（走查第 72 条：真实内容换成了 owner 头像）。
                cornerRadius: RepoAvatar.standard.diameter / 2
            )
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SkeletonBar(height: 14, width: 180)
                SkeletonBar(height: 12)
                SkeletonBar(height: 12, width: 120)
            }
            Spacer(minLength: 0)
        }
        // 方案 D（2026-10-15，走查第 73 条）：与 `RepoCard` 的去形内边距逐字对齐。
        .padding(.vertical, 13)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if showsTopSeparator {
                Rectangle()
                    .fill(Theme.Palette.borderSoft)
                    .frame(height: 1)
            }
        }
    }
}

#Preview {
    RepoCardSkeleton()
        .padding(Theme.Spacing.page)
        .background(Theme.Palette.background)
}
