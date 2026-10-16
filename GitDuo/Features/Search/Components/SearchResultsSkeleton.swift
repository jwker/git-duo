import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 搜索结果的首屏骨架（TECH_SPEC §8.5 第 1 档）。
///
/// ## ⚠️ 2026-10-16 起它是**行**，不是一个 `CardBox`（NATIVE-MIGRATION P3）
///
/// 同 `RepoCardSkeleton`：一行就是一个 `List` 行，卡面与分隔线由 `List` 给
/// （`body` 因此从"`CardBox` + `VStack`"变成 `ForEach`）。
///
/// ## ⚠️ 2026-10-16（P1）它不再自己画灰条
///
/// 渲染**真实的搜索结果行** + `.redacted(reason: .placeholder)`。
///
/// ⚠️ 四种结果行（仓库 / 用户 / 代码 / 会话）的几何并不一样，而骨架**只铺其中一种**
/// —— 取 `RepositoryHit`（最宽的那一档），于是切换范围时那一片占位的**左边界不会跳**
/// （这条理由与从前"取 32 那个图标块"是同一条，只是现在宽度由真实行自己决定）。
///
/// ⚠️ 它也是**不可点**的：整片 `allowsHitTesting(false)`（P3 起行本身不再带 action）。
struct SearchResultsSkeleton: View {

    /// 画几条。默认 6 —— 首屏（30 条一页）里能填满一屏，又不至于在数据到达时
    /// "多出几条凭空消失"。
    var count = 6

    var body: some View {
        ForEach(0..<count, id: \.self) { _ in
            SearchRowView(
                row: .repository(.placeholder),
                now: Placeholders.date
            )
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    List {
        SearchResultsSkeleton()
    }
}
