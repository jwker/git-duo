import SwiftUI

/// 探索 Tab 根页。
/// 依据：PRD §4.14 / TECH_SPEC §9.10。
/// 要点：**双榜**（新星榜 / 活跃榜，各一次 Search 请求）；筛选只有**日期范围 + 编程语言**；
/// ⚠️ 与搜索页**共用 Search 配额桶**（30/min）→ 切榜需防抖 300ms + 取消在途请求 + 缓存键含全部筛选维度（§13.2）。
struct ExploreView: View {

    var body: some View {
        SkeletonScreen(
            title: "探索",
            slice: "骨架占位 · 切片 4 落地",
            reference: "PRD §4.14 · 配额纪律见 TECH_SPEC §13.2"
        )
        .navigationTitle("探索")
    }
}

#Preview {
    NavigationStack { ExploreView() }
}
