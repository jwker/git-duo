import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 置顶**行**列表的骨架（TECH_SPEC §8.5）。
///
/// ## ⚠️ 2026-10-16 起它**不再自己画灰条**（NATIVE-MIGRATION P1）
///
/// 同 `RepoCardSkeleton` 那次改法：渲染**真实的 `PinRow`** + `.redacted(reason: .placeholder)`，
/// 而不是照着它抄一份几何再用自绘灰条画（那个件已随本批删除）。理由与收益都写在那边
/// （"第二份几何"不存在 ⇒ 骨架永远不可能与真实行失配）。
///
/// 于是"30pt 圆形头像 + 全名 + 描述 + 右侧 Star"这份形状**只剩 `PinRow` 一处**，
/// 本文件不再重复它。同 `StarRowSkeleton` 与 `StarRow` 的处置。
struct PinRowsSkeleton: View {

    /// 占位的行数。置顶上限 6 ⇒ 默认 4 行，够铺出"还有更多"的样子。
    var rows: Int = 4

    var body: some View {
        // 与真实态同构 —— 一组行 = 一张白卡（`HomeView` 那两处也是这么包的），
        // 否则数据到达时会"卡突然出现"跳一下。
        CardBox(vertical: 0, horizontal: 0) {
            // 与 `PinRow` 同一条：hairline 画在**顶上**，首行不画。
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { index in
                    PinRow(summary: .placeholder, showsSeparator: index > 0)
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

#Preview {
    PinRowsSkeleton()
        .padding(.horizontal, Theme.Spacing.page)
        .background(Theme.Palette.background)
}
