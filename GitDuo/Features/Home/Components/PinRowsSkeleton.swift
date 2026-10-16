import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 置顶**行**列表的骨架（TECH_SPEC §8.5）。
///
/// ## ⚠️ 2026-10-16 起它是**行**，不是一个框（NATIVE-MIGRATION P3）
///
/// P1 已经把它从"自绘灰条"改成"真实的 `PinRow` + `.redacted`"，但那时它自己还套着
/// 一层 `CardBox` 与 `VStack` —— 因为当时的列表主干是 `ScrollView + LazyVStack`。
/// 主干换 `List` 之后，**一行就是一个 `List` 行**，本件只负责把 N 行吐出去，
/// 容器（卡片底 / 分隔线 / 内边距）由 `List` 给。
///
/// ⚠️ 于是它变成一个 `ForEach` 而不是一个"装着几行的框" ——
/// 调用方直接把它放进 `Section` 的内容位。`.redacted` 与 `.allowsHitTesting(false)`
/// 逐行加（而不是加在 `ForEach` 上）：`List` 对"带修饰符的 `ForEach`"识别得不如
/// 逐行稳，而这两件事本来也是**每一行自己的属性**。
///
/// 同 `RepoCardSkeleton` / `StarRowSkeleton` 的思路：渲染真实的 `PinRow`，
/// "30pt 圆形头像 + 全名 + 描述 + 右侧 Star"这份形状**只剩 `PinRow` 一处**。
struct PinRowsSkeleton: View {

    /// 占位的行数。置顶上限 6 ⇒ 默认 4 行，够铺出"还有更多"的样子。
    var rows: Int = 4

    var body: some View {
        ForEach(0..<rows, id: \.self) { _ in
            PinRow(summary: .placeholder)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
        }
    }
}

#Preview {
    List {
        Section {
            PinRowsSkeleton()
        } header: {
            Text("置顶仓库")
        }
    }
}
