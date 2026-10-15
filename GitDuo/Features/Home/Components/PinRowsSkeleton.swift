import SwiftUI
import GitDuoDesign

/// 置顶**行**列表的骨架（TECH_SPEC §8.5）。
///
/// ## 它为什么必须挨着 `PinRow`
///
/// §8.5 的硬要求是"**尺寸必须匹配真实布局**，避免数据到达时跳动"。
/// 而"尺寸匹配"这件事**没法靠断言守住**（Swift 单测没有布局引擎，量不出高度），
/// 只能靠**把两个文件放在一起**：改 `PinRow` 的间距时，眼睛一定能扫到旁边这个文件。
/// 同 `StarRowSkeleton` 与 `StarRow` 的处置。
///
/// ## ⚠️ 2026-10-15 走查第 75 条：它跟着 `PinCard` 一起从**网格**变成**行**
///
/// 名字同步改成 `PinRowsSkeleton`（旧名 `PinGridSkeleton`）—— 它已经不是网格了，
/// 留着旧名字等于让下一个改它的人先读错一次。形状照 `PinRow`：
/// 30pt 圆形头像占位 + 全名条 + 描述条 + 右侧 Star 条。
///
/// ⚠️ 骨架属**内容层** ⇒ 实色、**不加玻璃**（§10.2）。
struct PinRowsSkeleton: View {

    /// 占位的行数。置顶上限 6 ⇒ 默认 4 行，够铺出"还有更多"的样子。
    var rows: Int = 4

    var body: some View {
        // 与 `PinRow` 同一条：hairline 画在**顶上**，首行不画。
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                row(showsTopSeparator: index > 0)
            }
        }
    }

    private func row(showsTopSeparator: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            SkeletonBar(
                height: RepoAvatar.row.diameter,
                width: RepoAvatar.row.diameter,
                // ⚠️ 圆形 —— 真实内容是 owner 头像（走查第 72 条）。
                cornerRadius: RepoAvatar.row.diameter / 2
            )

            VStack(alignment: .leading, spacing: 2) {
                // 高度照 `PinRow` 那两行文字（13pt 全名 / 12pt 描述），宽度全名比描述长。
                SkeletonBar(height: 16, width: 150)
                SkeletonBar(height: 14, width: 96)
            }

            Spacer(minLength: Theme.Spacing.s)

            SkeletonBar(height: 12, width: 36)
        }
        .padding(.vertical, Theme.Spacing.m)
        .padding(.horizontal, Theme.Spacing.xxs)
        .overlay(alignment: .topLeading) {
            if showsTopSeparator {
                Rectangle()
                    .fill(Theme.Palette.borderSoft)
                    .frame(height: 1)
                    // 与 `PinRow` 同一条内嵌缩进（2 + 30 + 12 = 44）。
                    .padding(.leading, Theme.Spacing.xxs + RepoAvatar.row.diameter + Theme.Spacing.m)
            }
        }
    }
}

#Preview {
    PinRowsSkeleton()
        .padding(.horizontal, Theme.Spacing.page)
        .background(Theme.Palette.background)
}
