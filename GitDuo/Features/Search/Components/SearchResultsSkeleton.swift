import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 搜索结果（与「我的会话」两个二级列表）的首屏骨架（TECH_SPEC §8.5 第 1 档）。
///
/// ## ⚠️ 2026-10-16 起它**不再自己画灰条**（NATIVE-MIGRATION P1）
///
/// 同 `RepoCardSkeleton`：渲染**真实的搜索结果行** + `.redacted(reason: .placeholder)`。
///
/// ⚠️ 四种结果行（仓库 / 用户 / 代码 / 会话）的几何并不一样，而骨架**只铺其中一种**
/// —— 取 `RepositoryHit`（最宽的那一档），于是切换范围时那一片占位的**左边界不会跳**
/// （这条理由与从前"取 32 那个图标块"是同一条，只是现在宽度由真实行自己决定）。
///
/// ⚠️ 它也是**不可点**的：`action` 给空闭包 + 整片 `allowsHitTesting(false)`。
struct SearchResultsSkeleton: View {

    /// 画几条。默认 6 —— 首屏（30 条一页）里能填满一屏，又不至于在数据到达时
    /// "多出几条凭空消失"。
    var count = 6

    var body: some View {
        // 与真实结果同构 —— 一组行 = 一张白卡（`SearchView` 那处也这么包）。
        CardBox(vertical: 0, horizontal: 0) {
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    SearchRowView(
                        row: .repository(.placeholder),
                        now: Placeholders.date,
                        // 与真实列表同一条：hairline 画在顶上 ⇒ 首行不画。
                        showsSeparator: index > 0,
                        action: {}
                    )
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    SearchResultsSkeleton()
        .padding(.horizontal, Theme.Spacing.page)
        .background(Theme.Palette.background)
}
