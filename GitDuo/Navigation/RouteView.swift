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
                // 切片 7 的两段（§4.4 分区二 / 三）。
                issues: env.repoIssues,
                pulls: env.repoPulls,
                starToggle: env.starToggle,
                // 决策 #80：头部那颗星"写不写得动"的判定来源（§3.5.5）。
                // ⚠️ 传组合根那**同一个**缓存 —— 那里在冷启动 / 换账号时就预热过。
                starScope: env.starWriteScope,
                // 切片 8.4：§5.8 后两个上传出口的写通道（§4.4 的「＋ 添加」）。
                saver: env.saveFile,
                // 切片 8.7 / 8.8：选中之后、写之前的那一步
                //（>1MB 的图片先压缩 #71；显示不出来的格式一律转码 #72）。
                intake: env.uploadIntake,
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
                // 决策 #80：**本页几乎每一条都是别人的仓库** ⇒ 这一档在这里是常态。
                starScope: env.starWriteScope,
                memory: env.branchMemory,
                visits: env.recentVisits,
                // 切片 9：② 「我的收藏」分区（§5.5 / §5.6）。
                // ⚠️ 与「我的收藏」管理页共用组合根那一个 `FolderStore`（§9.12 末段）。
                folders: env.folders,
                toast: env.toast
            )
        case let .fileView(fullName, path, readOnly):
            // PRD §4.5。⚠️ `detail` 与 `memory` 是**为分支解析**要的，不是为文件内容：
            //    路由只带 `fullName` / `path` / `readOnly`（§8.2 正本），而"这个文件属于
            //    哪个分支"要靠决策 #55 的两段式解析拿到（先读记忆、再回落默认分支）。
            //
            // ⚠️ `renameFile` / `deleteFile` 是切片 8.4 的「更多」那条路（§5.15–§5.17）——
            //    两条写通道传组合根里那**同一个**端点实例（见 `AppEnvironment` 的说明）。
            FileView(
                fullName: fullName,
                path: RepoPath(path: path),
                readOnly: readOnly,
                loader: env.fileContent,
                detail: env.repoDetail,
                memory: env.branchMemory,
                renameFile: env.renameFile,
                deleteFile: env.deleteFile,
                toast: env.toast
            )
        case let .editor(fullName, path, mode):
            // PRD §4.6。**切片 8.4 起是真页面**（此前是骨架屏）。
            //
            // ⚠️ `path` 是 `String?`，`nil` = 新建模式（§8.2 正本）——
            //    这里转成 `RepoPath?` 而不是给个空路径：`RepoPath.root` 是一个**真实的
            //    根目录路径**，而"新建文件"没有当前路径这回事，两者不能互相顶替。
            EditorView(
                fullName: fullName,
                mode: mode,
                path: path.map { RepoPath(path: $0) },
                loader: env.fileContent,
                detail: env.repoDetail,
                memory: env.branchMemory,
                saver: env.saveFile,
                toast: env.toast
            )
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
        case let .issueDetail(fullName, number, readOnly):
            // PRD §4.9、TECH_SPEC §9.8、决策 #79。
            // ⚠️ 两个参数都**显式传**：
            //    · `readOnly` —— 入口给的可写性（铁律 #7），同 PR 那一处；
            //    · `viewerLogin` —— 判"这条 Issue 是不是我提的"要用它（GitHub 的规则：
            //      谁提的谁可关，所以作者身份本身就是权限的一半）。
            //      ⚠️ 取自 `authState`，**不再打一次 `/user`**（同 §9.15 给设置页那一条口径）。
            //      已认证分支里它必然有值，但类型上是 Optional ⇒ 取不到时详情页取保守侧。
            IssueDetailView(
                fullName: fullName,
                number: number,
                readOnly: readOnly,
                viewerLogin: env.authState.login,
                loader: env.issueDetail,
                sender: env.postIssueComment,
                actions: env.issueAction,
                drafts: env.commentDrafts,
                toast: env.toast
            )
        case let .newIssue(fullName):
            // PRD §4.10。
            // ⚠️ 标签弹层用的是**组合根里那一个** `labelCatalog`（决策 #56）——
            //    §4.4 分区二的「筛选」是同一个实例，所以"新建的标签"在两个地方都立刻可选。
            NewIssueView(
                fullName: fullName,
                creator: env.createIssue,
                catalog: env.labelCatalog,
                toast: env.toast
            )
        case let .prDetail(fullName, number, readOnly):
            // PRD §4.11。
            // ⚠️ `readOnly` 是**路由带进来的**（`ExplorePRListView` 传 `true`、
            //    `RepoDetailView` 传 `false`），一路透传给操作区与提交详情 ——
            //    铁律 #7：这条链上没有任何一处去"推断仓库归属"。
            PullDetailView(
                fullName: fullName,
                number: number,
                readOnly: readOnly,
                loader: env.pullDetail,
                actions: env.pullAction,
                sender: env.postIssueComment,
                drafts: env.commentDrafts,
                toast: env.toast
            )
        case let .exploreIssueList(fullName):
            ExploreIssueListView(fullName: fullName, issues: env.repoIssues)
        case let .explorePRList(fullName):
            ExplorePRListView(fullName: fullName, pulls: env.repoPulls)
        case .stars:
            // PRD §4.18。切片 9.4 起是真页面（此前是骨架屏）。
            // ⚠️ `starToggle` 传组合根里那**同一个** `ToggleStar` ——
            //    Star 的「先确认基准、再幂等切换」只有一处实现（决策 #41）。
            //
            // ⚠️ 这一页复用 `LoadRepositoriesPage` + `.starred` 这个来源（切片 3 就有），
            //    **没有**新写一个 Star 列表用例（7.1a 的说明里记着这条核实结论）。
            MyStarsView(
                loader: env.repositories,
                starToggle: env.starToggle,
                toast: env.toast
            )
        case .folders:
            // PRD §4.19。⚠️ 传的是组合根那**唯一一个** `FolderStore` ——
            //    仓库详情页的「选择收藏列表」弹层读的是同一份数据；
            //    这里若 new 一个，表现是"在一边建了夹、另一边看不见"（§9.12 末段）。
            FoldersView(store: env.folders, toast: env.toast)
        case let .myConversations(kind):
            // PRD §4.21 / 决策 #73。⚠️ 两页共用**同一个** `LoadMyConversations`
            //    （它缓存里按 `kind` 分键）⇒ 切到「我的 Issue」再切回来不重发一轮
            //    —— 那个桶只有 30 次/分钟。
            MyConversationsView(kind: kind, loader: env.conversations)
        case .settings:
            // PRD §4.20。⚠️ `login` 取自 `authState`（本机就有），**不再打一次 `/user`**
            //    （§9.15 逐字）。它在这里**一定非空** —— `RouteView` 只活在 `MainTabView` 里，
            //    而后者由 `RootView` 在 `.authenticated` 那支才构建
            //    （铁律：未认证时不构建 `TabView`，§3.8）。
            //    写成 `?? ""` 只为少一层 `if let`：真出现空串（理论上不可达）时，
            //    那一行会显示成 `GitHub App · `，是个显眼的瑕疵而不是静默的错误。
            //
            //    `cache` 必须是组合根里那一份接口缓存 —— 在设置页里另建一个，
            //    「清除缓存」清掉的是一个空目录，而界面上照旧显示已释放多少（决策 #75）。
            SettingsView(
                login: env.authState.login ?? "",
                cache: env.responseCache,
                toast: env.toast
            )
        }
    }
}

#Preview {
    NavigationStack {
        RouteView(route: .settings)
    }
    .environment(AppEnvironment())
}
