import SwiftUI

/// 首页 —— Tab 根页。
/// 依据：PRD §4.1。内容：置顶仓库（**只读**同步 GitHub 个人主页，上限 6）+ 我的仓库 + 最近访问（本机记录）。
struct HomeView: View {

    let login: String

    var body: some View {
        SkeletonScreen(
            title: "首页",
            slice: "骨架占位 · 切片 4 落地",
            reference: "PRD §4.1 · 当前账号 @\(login)"
        )
        .navigationTitle("首页")
    }
}

#Preview {
    NavigationStack { HomeView(login: "jiangjiang") }
}
