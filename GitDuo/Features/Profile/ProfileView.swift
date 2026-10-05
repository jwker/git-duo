import SwiftUI

/// 我的 Tab 根页。
/// 依据：PRD §4.12。入口：我的 Star / 我的收藏 / 设置。
struct ProfileView: View {

    var body: some View {
        SkeletonScreen(
            title: "我的",
            slice: "骨架占位 · 切片 9 落地",
            reference: "PRD §4.12 · 入口：我的 Star / 我的收藏 / 设置"
        )
        .navigationTitle("我的")
    }
}

#Preview {
    NavigationStack { ProfileView() }
}
