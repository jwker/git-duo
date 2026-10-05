import SwiftUI

/// 仓库 Tab 根页。
/// 依据：PRD §4.15。分区：我的仓库 / 已 Star / 组织。
/// ⚠️ 可写性判定唯一来源 = `Repository.permissions.push`（TECH_SPEC §8.1），不按名称前缀或静态名单。
struct ReposView: View {

    var body: some View {
        SkeletonScreen(
            title: "仓库",
            slice: "骨架占位 · 切片 3 落地",
            reference: "PRD §4.15 · 可写性判定见 TECH_SPEC §8.1 / §6.2"
        )
        .navigationTitle("仓库")
    }
}

#Preview {
    NavigationStack { ReposView() }
}
