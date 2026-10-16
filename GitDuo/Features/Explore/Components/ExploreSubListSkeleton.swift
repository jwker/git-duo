import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 探索两个二级列表（Issues / PR）与仓库详情 Issues 段的首屏骨架（TECH_SPEC §8.5）。
///
/// ## ⚠️ 2026-10-16 起它**不再自己画灰条**（NATIVE-MIGRATION P1）
///
/// 同 `RepoCardSkeleton`：渲染**真实的 `IssueCard`** + `.redacted(reason: .placeholder)`。
/// 从前它的形状是"照着 `IssueCard` / `PullCard` 抄一份几何"，而现在**那份几何不存在了**。
///
/// 两页的卡片几何是同一个（原型 `10-explore-repo.js:102` 与 `:117` 的骨架一致），
/// 所以一份就够 —— 这条理由不变。
///
/// ⚠️ `now` 用 `Placeholders.date`（**固定时刻**）：占位不该引入"每次渲染都不同"的值
/// （`IssueCard` 的说明写了为什么相对时间必须稳定）。
struct ExploreSubListSkeleton: View {

    /// 画几条。默认 5 —— 首屏能填满一屏又不至于在数据到达时"多出几条凭空消失"。
    var count = 5

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { _ in
                IssueCard(row: .placeholder, now: Placeholders.date)
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

#Preview {
    ExploreSubListSkeleton()
        .padding(.horizontal, Theme.Spacing.page)
        .background(Theme.Palette.background)
}
