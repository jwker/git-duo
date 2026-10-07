import GitDuoKit
import SwiftUI

/// `Route` → 具体页面。
///
/// 骨架期：**每个 case 都必须出现在 switch 中**（穷尽枚举），未落地的分支显示占位屏。
/// 这样做的好处：切片推进时**编译器的穷尽性检查会盯住每一处**——
/// 新增一个 `Route` case 而忘记接线，构建即失败，不会静默漏页。
///
/// ⚠️ 每条的 `reference` 引用 **PRD §4.x 的现行编号**。2026-10-06 一次性校正过：
///    此前有 9 条引用的是**改版前的旧编号**（例如把「仓库详情」标成 §4.16，
///    而 §4.16 其实是「通知」）—— 评审时照着编号翻文档会翻到完全不相干的页面。
struct RouteView: View {

    let route: Route

    /// 推入页的依赖由本视图从组合根取（同 `MainTabView` 对根页的做法）。
    ///
    /// ⚠️ 只在**用得到的那几个分支**里访问它 —— `@Environment` 对未注入的对象
    /// 是"访问才崩"，所以 `.settings` 这类骨架分支不会因为没装环境而炸掉预览。
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        switch route {
        case .search:
            // 三个入口（首页 / 仓库 / 探索右上角的放大镜）都推到这一处（PRD §4.2、§6.3）。
            // 本视图只负责把组合根的两件依赖传下去；页面自己不认识"是谁推的它"。
            SearchView(loader: env.search, history: env.searchHistory)
        case let .repoDetail(fullName, section, path):
            // PRD §4.4（**自己的仓库**）。⚠️ 分片归属曾一度错标成「切片 4 落地」——
            //    PRD §4.4 与施工图 4.4「表现层」撞了名。2026-10-07 裁定：归**切片 6**。
            //
            // ⚠️ `path` 此前被写成 `_`（骨架期不用它）。接真件时**必须接上**：
            //    它是"从面包屑某层推入的深层目录"，丢了它表现为**每次点面包屑都回到仓库根**，
            //    而源码里看不出任何异常。
            //
            // 依赖在这里逐条列全 —— 页面自己不碰组合根（AGENTS.md §3 的铁律）；
            // 它只从 `@Environment` 拿 `router` / `toast` 这类**UI 通道**（同 §4.13）。
            RepoDetailView(
                fullName: fullName,
                section: section,
                path: RepoPath(path: path ?? ""),
                detail: env.repoDetail,
                treeLoader: env.repoTree,
                commits: env.repoCommits,
                branches: env.branches,
                starToggle: env.starToggle,
                memory: env.branchMemory,
                visits: env.recentVisits,
                toast: env.toast
            )
        case let .exploreRepoDetail(fullName, path):
            // ⚠️ `path` 是**子目录**（原型 `push('exploreRepoDetail',{repo, sub})`）——
            //    它非空时这一页渲染的是同一套内容、只是目录停在那层。
            //    `Route` 里它是 `String?`，`nil` = 根目录（`RepoPath` 拿空串表示根）。
            ExploreRepoDetailView(
                fullName: fullName,
                path: RepoPath(path: path ?? ""),
                insights: env.repoInsights,
                treeLoader: env.repoTree,
                branches: env.branches,
                starToggle: env.starToggle,
                memory: env.branchMemory,
                visits: env.recentVisits,
                toast: env.toast
            )
        case let .fileView(fullName, path, readOnly):
            // PRD §4.5。⚠️ `detail` 与 `memory` 是**为分支解析**要的，不是为文件内容：
            //    路由只带 `fullName` / `path` / `readOnly`（§8.2 正本），而"这个文件属于
            //    哪个分支"要靠决策 #55 的两段式解析拿到（先读记忆、再回落默认分支）。
            FileView(
                fullName: fullName,
                path: RepoPath(path: path),
                readOnly: readOnly,
                loader: env.fileContent,
                detail: env.repoDetail,
                memory: env.branchMemory,
                toast: env.toast
            )
        case let .editor(fullName, path, mode):
            SkeletonScreen(title: "编辑器 · \(path ?? "新文件")", slice: "切片 8 落地", reference: "PRD §4.6 · \(fullName) · 模式=\(mode)")
        case let .commitDetail(fullName, sha, readOnly):
            // PRD §4.7。`sha` 是**全哈希**（列表行上显示的短哈希只是显示形态）——
            // 路由里存全的、显示时才截，否则"从提交详情再点进去"就没有更细的地址可用了。
            CommitDetailView(
                fullName: fullName,
                sha: sha,
                readOnly: readOnly,
                loader: env.repoCommits,
                toast: env.toast
            )
        case let .branches(fullName):
            // PRD §4.8 / TECH_SPEC §9.7.1。
            // ⚠️ 三条写操作（删 / 建 / 合）**必须传组合根里那三个实例**：
            //    `CreateBranch` 建完要写分支记忆，而 `RepoDetailViewModel` 切分支时读的是
            //    同一个 `branchMemory`；这里若各 new 一个，表现为"建完分支，回到仓库还是旧分支"。
            BranchesView(
                fullName: fullName,
                detail: env.repoDetail,
                branches: env.branches,
                deleteBranch: env.deleteBranch,
                createBranch: env.createBranch,
                mergeBranch: env.mergeBranch,
                memory: env.branchMemory,
                toast: env.toast
            )
        case let .issueDetail(fullName, number):
            SkeletonScreen(title: "Issue #\(number)", slice: "切片 7 落地", reference: "PRD §4.9 · \(fullName)")
        case let .newIssue(fullName):
            SkeletonScreen(title: "新建 Issue", slice: "切片 7 落地", reference: "PRD §4.10 · \(fullName)")
        case let .prDetail(fullName, number, readOnly):
            SkeletonScreen(title: "PR #\(number)", slice: "切片 7 落地", reference: "PRD §4.11 · \(fullName) · 只读=\(readOnly)")
        case let .exploreIssueList(fullName):
            ExploreIssueListView(fullName: fullName, issues: env.repoIssues)
        case let .explorePRList(fullName):
            ExplorePRListView(fullName: fullName, pulls: env.repoPulls)
        case .stars:
            SkeletonScreen(title: "我的 Star", slice: "切片 9 落地", reference: "PRD §4.18")
        case .folders:
            SkeletonScreen(title: "我的收藏", slice: "切片 9 落地", reference: "PRD §4.19 · 纯本地，零请求")
        case .settings:
            SkeletonScreen(title: "设置", slice: "切片 9 落地", reference: "PRD §4.20")
        }
    }
}

#Preview {
    NavigationStack {
        RouteView(route: .settings)
    }
    .environment(AppEnvironment())
}
