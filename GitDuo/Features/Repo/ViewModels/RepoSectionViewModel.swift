import Foundation
import GitHubAPI
import GitDuoKit

/// **列表分区页**（Issues / Pull Requests / Commits）的状态 —— 2026-10-14 新增（走查第 63 条）。
///
/// ## 它是从 `RepoDetailViewModel` 里**搬出来**的，不是新写的
///
/// 用户要求把仓库页改成枢纽（头部大卡 + 四行入口），于是原来"一页四个分区"里
/// 除代码之外的三个各自成页。本类型接的正是原来住在 `RepoDetailViewModel` 里的
/// 那一整套（四个 `RepoSubListViewModel` + 提交列表 + 标签筛选），
/// **规则一条没改**，只是换了宿主：
///
/// | 数据 | 何时取 | 失败 |
/// |---|---|---|
/// | 提交列表（`GET /commits`）| **进页即取**（这一页除了它没别的）| 列表内失败 + 加载更多 |
/// | Issues 两档（`GET /issues`）| 进页取当前档，且**每档首次才取** | 分区内失败 + 加载更多 |
/// | PR 两档（`GET /pulls`）| 同上 | 同上 |
///
/// ⚠️ 分区那一页**没有分段条**（它自己就是"某一段"）⇒ 进来的那一档由 `section` 定死。
/// Issues / PR 内部的"开放 / 已关闭（已合并）"两档仍是页内的，见 `selectIssueSegment`。
///
/// ## ⚠️ 切片 7 的两段：**每档各持一份状态机**
///
/// Issues / PR 两段各有两档（`RepoSectionSegment`），而**每档有自己的游标与失败态**
/// （TECH_SPEC §9.8.1）⇒ 四个 `RepoSubListViewModel` 实例，而不是一个"当前档"的实例。
/// 切回来看到的是刚才那一份（不重发请求），切到没取过的那一档才取。
///
/// ⚠️ 但**换一组标签筛选时四个里有两个要重建**（Issues 那两个）：
/// 旧结果是用旧标签取的，留着它切档就会出现两组标签混在一起的数据（见 `applyIssueLabels`）。
///
/// ## ⚠️ 提交列表要自己解析一次分支（原来不用）
///
/// 原来这一条读的是 `tree.branch` —— 那个值由代码分区的会话解析出来
/// （两段式：记忆值 → 分支列表校正 → 失效则静默回落）。
/// 现在提交列表与代码页**不在同一页**、也没有共享的会话 ⇒ 它必须自己解析一次。
/// 口径与 `FileViewModel.currentRef()` **逐字相同**（先记忆值、回报默认分支），
/// 而那三条规则本身仍只有一处实现：领域层的 `BranchResolver`（有单测）。
@MainActor
@Observable
final class RepoSectionViewModel {

    // MARK: - 状态

    /// 这一页是哪一个分区。**由路由定，进页后不变。**
    let section: RepoSection

    /// 提交列表 —— 与另外两段各有各的骨架屏。
    private(set) var commits = PagedListState<CommitSummary>()

    /// Issues 段的两档 —— **各持一份状态机**（每档自己的游标与失败态，§9.8.1）。
    ///
    /// ⚠️ 它们是 `var` 而不是 `let`：换标签筛选时要**重建**（见 `rebuildIssueModels`）。
    private(set) var issueOpen: RepoSubListViewModel<IssueRow>
    private(set) var issueClosed: RepoSubListViewModel<IssueRow>

    /// PR 段的两档。`closed` 那一档界面上叫「已合并」—— 它取回的是服务端的
    /// `state=closed`，之后由 `LoadRepoPulls` 滤掉"关闭但没合并"（决策 #39 / #61）。
    private(set) var pullOpen: RepoSubListViewModel<PullRow>
    private(set) var pullMerged: RepoSubListViewModel<PullRow>

    /// 两段各自选中的档。默认都是「开放」（原型两处都是 `class="seg on"`）。
    private(set) var issueSegment: RepoSectionSegment = .open
    private(set) var pullSegment: RepoSectionSegment = .open

    /// Issues 段的标签筛选（决策 #56：**走服务端**）。
    ///
    /// ⚠️ 存 `[Label]` 而不是 `[String]`：视图要用它的**颜色**画已选标签行，
    /// 只留名字的话还得再查一次标签库。
    private(set) var issueLabels: [Label] = []

    // MARK: - 依赖

    private let commitsLoader: LoadRepoCommits

    /// 两段的取数用例。⚠️ 留着它们是因为**标签一变就要重建实例**
    /// （`rebuildIssueModels` 需要重新捕获一组标签）。
    private let issuesLoader: LoadRepoIssues
    private let pullsLoader: LoadRepoPulls

    /// 提交列表要的那两样（只为解析 `ref`，见类型说明）。
    private let detailLoader: LoadRepoDetail
    private let memory: any BranchMemoryStore

    let fullName: String

    /// ⚠️ 这里**没有** `toast`：搬过来的那一摊里没有任何一处会弹提示
    /// （原来那两处 —— 下拉刷新失败、切分支成功 —— 一处随头部留在首页、
    /// 一处随目录去了代码页）。标签弹层的两句提示由**视图**用 `env.toast` 发
    /// （那两句在 `LabelPickerSheet` 的 `onCreation` 那一侧，见 `RepoSectionListView`）。
    init(
        fullName: String,
        section: RepoSection,
        commits: LoadRepoCommits,
        issues: LoadRepoIssues,
        pulls: LoadRepoPulls,
        detail: LoadRepoDetail,
        memory: any BranchMemoryStore
    ) {
        self.fullName = fullName
        self.section = section
        self.commitsLoader = commits
        self.issuesLoader = issues
        self.pullsLoader = pulls
        self.detailLoader = detail
        self.memory = memory

        // ⚠️ 四个实例在这里直接建出来（而不是延后到 `start()`）：
        //    视图随时可能读到它们，而"可能还没建"会让每一个调用点都要处理可空。
        //
        // ⚠️ 闭包**只捕获局部常量**（loader 与档位），不捕获 `self` ——
        //    在 `init` 里捕获 `self` 会撞上"所有存储属性都还没初始化完"这条规则，
        //    而那正是下面这两行要写成独立局部变量的唯一理由。
        let issuesLoader = issues
        let pullsLoader = pulls

        self.issueOpen = RepoSubListViewModel { fullName, cursor in
            try await issuesLoader.load(
                fullName: fullName, state: .open, labels: [], cursor: cursor
            )
        }
        self.issueClosed = RepoSubListViewModel { fullName, cursor in
            try await issuesLoader.load(
                fullName: fullName, state: .closed, labels: [], cursor: cursor
            )
        }
        self.pullOpen = RepoSubListViewModel { fullName, cursor in
            try await pullsLoader.load(fullName: fullName, state: .open, cursor: cursor)
        }
        self.pullMerged = RepoSubListViewModel { fullName, cursor in
            // ⚠️ 要「已合并」就得取 `.closed` 再本地滤（GitHub 没有"只看已合并"这一档）。
            try await pullsLoader.load(fullName: fullName, state: .closed, cursor: cursor)
        }
    }

    // MARK: - 生命周期

    /// 进页取数 —— 只取**这一页那一段**（另外两段的数据这一页根本不画）。
    ///
    /// ⚠️ 「每档首次才取」由状态机自己保证（`RepoSubListViewModel.start` 的
    /// `guard !state.hasLoaded`），所以这里不必再判一次。
    func start() async {
        switch section {
        case .issues:
            await currentIssues.start(fullName: fullName)

        case .pullRequests:
            await currentPulls.start(fullName: fullName)

        case .commits:
            guard !commits.hasLoaded else { return }
            await loadCommits(reset: true)
        }
    }

    // MARK: - 提交列表

    func loadMoreCommits() async {
        guard commits.canLoadMore, !commits.isLoading else { return }
        await loadCommits(reset: false)
    }

    /// 取一页提交。
    ///
    /// ## ⚠️ `ref` 的解析是这里的**第二件事**，不是重点
    ///
    /// 它与 `FileViewModel.currentRef()` 同一条口径（记忆值优先、回报默认分支），
    /// 而"记忆值那条分支已经不存在了"这一档由领域层的
    /// `BranchResolver.shouldSilentlyRetry` 判 —— 那一档**静默回落并重发一次**，
    /// 不向用户报错（§9.4.1 表第三行）。不这么做的话，删掉一条分支之后
    /// 这一页会稳定报错，而它本该自愈。
    private func loadCommits(reset: Bool) async {
        commits.beginLoad(reset: reset)
        do {
            // ⚠️ 与首页走同一条路由 ⇒ 那一次通常命中 304，不计配额
            //   （`LoadRepoDetail.repository(fullName:)` 的说明）。
            let head = try await detailLoader.repository(fullName: fullName)
            let remembered = await memory.branch(for: fullName)
            let ref = BranchResolver.initial(
                remembered: remembered, defaultBranch: head.defaultBranch
            )

            do {
                commits.received(try await fetchCommits(ref: ref, reset: reset))
            } catch {
                guard let gitHubError = error as? GitHubError,
                      BranchResolver.shouldSilentlyRetry(
                          after: gitHubError,
                          attemptedBranch: ref,
                          defaultBranch: head.defaultBranch
                      )
                else { throw error }

                // 记忆值失效 ⇒ 清掉它（写盘，不会自愈的那一次），再按默认分支重发一次。
                await memory.forget(fullName: fullName)
                commits.received(try await fetchCommits(ref: head.defaultBranch, reset: reset))
            }
        } catch {
            commits.failed(Self.failure(from: error))
        }
    }

    /// 真正发那一次请求。
    ///
    /// ⚠️ `cursor` 只从 `commits` 上读（**不参数化**）：两处各算一次的那天，
    /// "静默回落那次重发"会拿着上一页的游标去要第一页。
    private func fetchCommits(ref: String, reset: Bool) async throws -> Page<CommitSummary> {
        try await commitsLoader.page(
            fullName: fullName,
            branch: ref,
            cursor: reset ? nil : commits.nextCursor
        )
    }

    // MARK: - 切片 7：两段（PRD §4.4 分区二·三、决策 #56 / #61）

    /// 当前选中的 Issues 档的状态机。
    ///
    /// ⚠️ 写成 `switch`（而不是 `issueSegment == .closed ? … : …`）：
    /// `RepoSectionSegment` 只有两档，于是"漏了一档"是编译错误。
    var currentIssues: RepoSubListViewModel<IssueRow> {
        switch issueSegment {
        case .open: issueOpen
        case .closed: issueClosed
        }
    }

    /// 当前选中的 PR 档的状态机。
    var currentPulls: RepoSubListViewModel<PullRow> {
        switch pullSegment {
        case .open: pullOpen
        case .closed: pullMerged
        }
    }

    /// 分段条第一格：`开放 (N)`；**这一档还没加载过**时只有 `开放`。
    ///
    /// ⚠️ 问的是**「开放」这一档自己**的加载状态，而不是当前档 ——
    /// 用户切到「已关闭」时，那一格上的数字仍然是"开放档加载到哪了"。
    var openIssuesTitle: String {
        RepoIssuesSectionCopy.openSegment(
            loadedCount: Self.countIfLoaded(issueOpen),
            hasMore: issueOpen.hasMore
        )
    }

    /// 第二格的文案（**不带计数** —— 原型两处都只给「开放」那格计数）。
    var closedIssuesTitle: String { RepoIssuesSectionCopy.closedSegment }

    var openPullsTitle: String {
        RepoPullsSectionCopy.openSegment(
            loadedCount: Self.countIfLoaded(pullOpen),
            hasMore: pullOpen.hasMore
        )
    }

    var mergedPullsTitle: String { RepoPullsSectionCopy.mergedSegment }

    /// 切 Issues 段的档。
    ///
    /// ## ⚠️ 切换分档要**重新取数**，不是拿已加载的那一页本地过滤
    ///
    /// （TECH_SPEC §9.8.1）本地过滤只会筛出"碰巧已经加载出来的"那几条，
    /// 于是分段条上的数字与实际能看到的条数对不上 —— 而这看起来完全正常。
    ///
    /// ## ⚠️ 但"切回去"不重取
    ///
    /// 两档各自持有自己的游标与失败态（同一条 §9.8.1）⇒ 目标档已经加载过时，
    /// 状态机会直接跳过（`RepoSubListViewModel.start` 的 `guard !state.hasLoaded`），
    /// 用户看到的是刚才翻到的那一页。
    func selectIssueSegment(_ segment: RepoSectionSegment) async {
        guard segment != issueSegment else { return }
        issueSegment = segment
        await currentIssues.start(fullName: fullName)
    }

    /// 切 PR 段的档（同 Issues：`.closed` 那一档界面上叫「已合并」）。
    func selectPullSegment(_ segment: RepoSectionSegment) async {
        guard segment != pullSegment else { return }
        pullSegment = segment
        await currentPulls.start(fullName: fullName)
    }

    /// 应用一组标签筛选（决策 #56：**走服务端**，不做本地过滤）。
    ///
    /// ## ⚠️ 换一组标签 ⇒ **两档的状态机都要重建**
    ///
    /// 不只是当前档：旧结果是用旧标签取的，切到另一档时若还留着它，
    /// 屏幕上会出现"两组标签混在一起"的数据 —— 而那看起来完全正常
    /// （有内容、不报错、分页行也在）。
    ///
    /// ⚠️ 比较用 `[Label]`（`id` 就是名字）**含顺序**：顺序变了说明用户重新点过一遍，
    /// 重取一次是无害的（命中 304 时连配额都不计）。
    func applyIssueLabels(_ labels: [Label]) async {
        guard labels != issueLabels else { return }
        issueLabels = labels
        rebuildIssueModels()
        await currentIssues.start(fullName: fullName)
    }

    /// 点掉一颗已选标签（已选标签行）。
    func removeIssueLabel(_ label: Label) async {
        await applyIssueLabels(issueLabels.filter { $0.name != label.name })
    }

    /// 把一颗标签**加进**筛选（弹层里点了一行、或新建/已存在时顺手选中）。
    ///
    /// ⚠️ 已经在里面时**什么都不做**。这条守卫必须在这里而不是在两个调用点：
    /// 直接写 `applyIssueLabels(issueLabels + [label])` 会在重复时造出一个
    /// **多了一项的数组** —— `applyIssueLabels` 的顺序比对于是判定"变了"，
    /// 白白重建两个状态机并发一次请求，而屏幕上一点变化都没有。
    func selectIssueLabel(_ label: Label) async {
        guard !issueLabels.contains(where: { $0.name == label.name }) else { return }
        await applyIssueLabels(issueLabels + [label])
    }

    /// 按当前的标签筛选**重建** Issues 两档的状态机。
    ///
    /// ⚠️ 为什么是"重建实例"而不是"清空已有实例"：`RepoSubListViewModel` 把
    /// `PagedListState` 私有化了，而它的取数闭包在 `init` 时就捕获了标签 ——
    /// 换标签唯一的干净做法就是换一个实例。
    /// 这也顺带保证了"重建即清空"：不会有旧游标或旧失败态残留下来。
    private func rebuildIssueModels() {
        let loader = issuesLoader
        let names = issueLabels.map(\.name)

        issueOpen = RepoSubListViewModel { fullName, cursor in
            try await loader.load(fullName: fullName, state: .open, labels: names, cursor: cursor)
        }
        issueClosed = RepoSubListViewModel { fullName, cursor in
            try await loader.load(fullName: fullName, state: .closed, labels: names, cursor: cursor)
        }
    }

    /// 分段的计数：**没加载过就是 `nil`**（不是 0）。
    ///
    /// ⚠️ 两者的区别正是 §8.5 末条："还没加载出来"与"确实一条都没有"。
    /// 折成 0 会让分段条写着 `开放 (0)` —— 那是在告诉用户
    /// "这个仓库没有开放的 Issue"，而事实是"还没问过服务端"。
    private static func countIfLoaded<Item: Identifiable & Sendable>(
        _ list: RepoSubListViewModel<Item>
    ) -> Int? {
        list.hasLoaded ? list.loadedCount : nil
    }

    // MARK: - 错误归一化

    /// 把任意错误收敛成 `GitHubError`（同其余 ViewModel：映射失败归 `.decoding`，
    /// **不是** `.transport` —— 后者会让界面给出"检查网络"的错误引导）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}
