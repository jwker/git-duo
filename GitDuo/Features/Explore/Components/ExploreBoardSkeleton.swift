import SwiftUI
import GitDuoDesign

/// 探索榜列表的骨架形态（TECH_SPEC §8.5）。
///
/// ## 它为什么必须挨着 `TrendCard`
///
/// 同 `RepoCardSkeleton` / `PinRowsSkeleton` 的理由：§8.5 的硬要求是
/// "**尺寸必须匹配真实布局**，避免数据到达时跳动"，而"尺寸匹配"**没法靠断言守住**
/// （Swift 单测没有布局引擎），只能把两个文件放得足够近。
///
/// ⚠️ 骨架属**内容层** ⇒ 实色、**不加玻璃**（§10.2）。
struct ExploreBoardSkeleton: View {

    /// 占位几张卡。一屏大约放得下 4 张。
    var count: Int = 4

    var body: some View {
        // 方案 D：行间 hairline 由行自己画（顶上那条），骨架同样首行不画。
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                card(showsTopSeparator: index > 0)
            }
        }
    }

    private func card(showsTopSeparator: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            // 尺寸跟着 `TrendCard` 一起改（那里用的是 `RepoAvatar.standard`）。
            SkeletonBar(
                height: RepoAvatar.standard.diameter,
                width: RepoAvatar.standard.diameter,
                // ⚠️ 2026-10-15 起占位块也是**圆的**（走查第 72 条：真实内容换成了 owner 头像）。
                cornerRadius: RepoAvatar.standard.diameter / 2
            )
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SkeletonBar(height: 14, width: 168)   // 仓库全名
                SkeletonBar(height: 12)               // 描述
                SkeletonBar(height: 12, width: 120)   // 描述第二行 / 角标行
            }
            Spacer(minLength: 0)
        }
        // 方案 D（2026-10-15，走查第 73 条）：与 `TrendCard` 的去形内边距逐字对齐。
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
    ExploreBoardSkeleton()
        .padding(Theme.Spacing.page)
        .background(Theme.Palette.background)
}
