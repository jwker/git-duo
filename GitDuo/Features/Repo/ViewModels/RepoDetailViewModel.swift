import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 仓库详情页（**自己的仓库**，PRD §4.4）的状态。
///
/// ## 四条取数各有各的节奏，别把它们揉成一个 `isLoading`
///
/// | 数据 | 何时取 | 失败 |
/// |---|---|---|
/// | 头部（`GET /repos`）+ Star 基准 | 进页一次 | **整页失败** + 重试出口 |
/// | 目录 + README | 头部到手之后（它要 `defaultBranch`） | 代码分区内失败 |
/// | 提交列表（`GET /commits`） | **切到 Commits 分段才取**（懒加载） | 列表内失败 + 加载更多 |
/// | 分支列表（`GET /branches`） | **打开切换弹层时取** —— 届时取目录刚问过，命中 304 | 弹层内失败 |
/// | Issues 两档（`GET /issues`，切片 7） | **切到 Issues 分区才取**，且**每档首次才取** | 分区内失败 + 加载更多 |
/// | PR 两档（`GET /pulls`，切片 7） | 同上 | 同上 |
///
/// 后四条**有意懒加载**：主桶配额虽然宽（5,000/小时），但"进一个仓库就发六个请求"
/// 会让每次点开的等待都变成最慢那条链路的长度 —— 而其中四条用户可能整次访问都不看
/// （§4.4 的默认分区是「代码」）。
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
/// ## ⚠️ 目录那一条**不在本类型里**
///
/// 它在 `RepoTreeSession`（§4.13 的「文件浏览」分区用的是**同一个**会话）——
/// 分支两段式解析、记忆失效回落、副标题逐条补填那几条规则只有一个落点。
/// 本类型只做三件与它有关的事：**把 `defaultBranch` 交下去**、
/// 切分支后清掉自己的提交列表、以及在弹层里转发一次重试。
@MainActor
@Observable
final class RepoDetailViewModel {

    // MARK: - 状态

    private(set) var snapshot: LoadState<RepoDetailSnapshot> = .idle

    /// 目录浏览的会话（当前分支 + 目录页 + 分支列表 + 副标题补填）。
    let tree: RepoTreeSession

    /// 提交列表 —— 子列表，**与目录那一块各有各的骨架屏**。
    private(set) var commits = PagedListState<CommitSummary>()

    private(set) var isTogglingStar = false

    /// 当前分段。初值由路由给（`.repoDetail(fullName:section:path:)` 的 `section`）。
    var section: RepoSection

    // MARK: - 切片 7：Issues / PR 两段（PRD §4.4 分区二·三、决策 #56 / #61）

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

    private let detailLoader: LoadRepoDetail
    private let commitsLoader: LoadRepoCommits

    /// 两段的取数用例。⚠️ 留着它们是因为**标签一变就要重建实例**
    /// （`rebuildIssueModels` 需要重新捕获一组标签）。
    private let issuesLoader: LoadRepoIssues
    private let pullsLoader: LoadRepoPulls

    private let starToggle: ToggleStar
    private let visits: any RecentVisitStore
    private let toast: ToastCenter

    /// 上传出口的写通道（§5.8 的后两行 —— 切片 8.4）。
    private let saver: SaveFile

    let fullName: String

    init(
        fullName: String,
        section: RepoSection,
        path: RepoPath,
        detail: LoadRepoDetail,
        treeLoader: LoadRepoTree,
        commits: LoadRepoCommits,
        branches: LoadBranches,
        issues: LoadRepoIssues,
        pulls: LoadRepoPulls,
        starToggle: ToggleStar,
        saver: SaveFile,
        memory: any BranchMemoryStore,
        visits: any RecentVisitStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.section = section
        self.detailLoader = detail
        self.commitsLoader = commits
        self.issuesLoader = issues
        self.pullsLoader = pulls
        self.starToggle = starToggle
        self.saver = saver
        self.visits = visits
        self.toast = toast
        self.tree = RepoTreeSession(
            fullName: fullName,
            path: path,
            loader: treeLoader,
            branches: branches,
            memory: memory
        )

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

    /// 进页：**先记访问，再取数**（理由同 `ExploreRepoViewModel.start`）。
    ///
    /// ⚠️ `canWrite: true` 是事实而不是猜测：能走到本页，只可能是因为路由在进入前
    /// 就把它判成了自己的仓库（`HomeView` / `ReposView` 二选一推入）
    /// —— 这正是 `RecentVisitStore.record(fullName:canWrite:at:)` 要调用方显式传参的原因。
    func start() async {
        await visits.record(fullName: fullName, canWrite: true, at: Date())

        guard !snapshot.hasFinished else { return }
        await loadDetail()
        // ⚠️ 头部到手之后再按当前分段取数：路由可能**直接落在** Issues / PR 段上
        //    （`.repoDetail(fullName:section:path:)` 的 `section`）。
        //    切片 6 时这里只处理了 Commits —— 那一段只能从分段条点进来，所以没暴露；
        //    改成统一入口之后顺带对齐了（两段的"首次才取"由状态机自己保证）。
        await loadCurrentSectionIfNeeded()
    }

    /// 下拉刷新：头部（连带 Star 基准）+ 当前目录，一起重取。
    ///
    /// ⚠️ **不刷新已加载的提交列表**：它有自己的"加载更多"与游标，
    /// 从头部那一侧重置它会丢掉用户已经翻过的页（§8.5 的"刷新不遮挡已有内容"
    /// 说的是别把内容清掉，而这里连语义都不该变）。
    ///
    /// ⚠️ **切片 7 的两段沿同一条口径**（下拉刷新只重新拉头部与目录）。
    /// 它们各有自己的加载与重试出口：切档会（在首次时）取数、失败时有分区内的重试。
    ///
    /// ⚠️ 这条**已裁定**（2026-10-08，用户拍板**保持现状**）：在 Issues 段下拉而列表
    /// 纹丝不动，确实可能被读成"刷新没生效"，但改它会让本页与切片 6 的 Commits 段
    /// 口径**相反** —— 同一页两种下拉语义，比"这一段没刷新"更难解释。
    /// 要改的话只需在这里补一句 `await currentIssues.refresh()`（两段各自有 `refresh`），
    /// 改动很小 —— **已登记为有意偏差，不擅自改**。
    func refresh() async {
        await loadDetail(keepContent: true)
    }

    /// 切分区。切过去之后**首次**才去取（懒加载，见类型说明）。
    func select(section: RepoSection) async {
        self.section = section
        await loadCurrentSectionIfNeeded()
    }

    // MARK: - Star

    func toggleStar() async {
        guard let current = snapshot.value?.star, !isTogglingStar else { return }

        isTogglingStar = true
        defer { isTogglingStar = false }

        do {
            let (next, action) = try await starToggle.toggle(current)
            // ⚠️ 只换 `star`，头部那份详情**原样保留** —— 它是上一句 `guard` 已经
            //    确认过存在的那一份。重新取一次头部是白花一个请求。
            if let currentDetail = snapshot.value?.detail {
                snapshot.succeed(RepoDetailSnapshot(detail: currentDetail, star: next))
            }
            toast.show(StarCopy.toast(for: action))
        } catch {
            // 失败**不改动任何计数**（`ToggleStar.toggle` 保证），按钮恢复可点。
            toast.show(ActionCopy.failed)
        }
    }

    // MARK: - 提交列表

    func loadMoreCommits() async {
        guard commits.canLoadMore, !commits.isLoading else { return }
        await loadCommits(reset: false)
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

    // MARK: - 分支弹层（转发给会话 + 本页特有的联动）

    /// 切到另一条分支 —— 会话负责写记忆与重取目录，本页负责清掉提交列表与提示。
    ///
    /// ⚠️ 提交列表**必须重取**：它带着 `sha=` 参数，不重取的话列表还是旧分支的提交，
    ///    而面包屑已经写着新分支 —— 两者对不上时用户会以为"分支切错了"。
    func switchBranch(to name: String) async {
        guard let defaultBranch = snapshot.value?.detail.defaultBranch else { return }
        guard await tree.switchBranch(to: name, defaultBranch: defaultBranch) else { return }
        if commits.hasLoaded { await loadCommits(reset: true) }
        toast.show(BranchCopy.switchedToast(branch: name))
    }

    // MARK: - 内部：取数

    private func loadDetail(keepContent: Bool = false) async {
        if !keepContent { snapshot.begin() }
        do {
            snapshot.succeed(try await detailLoader.load(fullName: fullName))
        } catch {
            if keepContent, snapshot.value != nil {
                // ⚠️ 正本在 `GitDuoKit.RefreshCopy`（切片 7.4 收口）。
                toast.show(RefreshCopy.failed)
            } else {
                snapshot.fail(Self.failure(from: error))
            }
            return
        }
        // ⚠️ 头部到手才有 `defaultBranch` ⇒ 目录必须排在它后面。
        guard let defaultBranch = snapshot.value?.detail.defaultBranch else { return }
        await tree.load(defaultBranch: defaultBranch)
    }

    private func loadCommits(reset: Bool) async {
        commits.beginLoad(reset: reset)
        do {
            let page = try await commitsLoader.page(
                fullName: fullName,
                // ⚠️ 必须传当前分支：不传时服务端用默认分支，于是列表与面包屑对不上。
                branch: tree.branch ?? snapshot.value?.detail.defaultBranch,
                cursor: reset ? nil : commits.nextCursor
            )
            commits.received(page)
        } catch {
            commits.failed(Self.failure(from: error))
        }
    }

    /// 按**当前分段**取数 —— 每一支都只在"还没取过"时发请求。
    ///
    /// 两个调用点：`start()`（进页时路由可能直接落在某一段上）与
    /// `select(section:)`（点分区条）。切**档**不走这里（那由
    /// `selectIssueSegment` / `selectPullSegment` 直接叫对应档的状态机）。
    private func loadCurrentSectionIfNeeded() async {
        switch section {
        case .code:
            // 目录由 `loadDetail` 里的 `tree.load` 负责（它要 `defaultBranch`）。
            break
        case .issues:
            await currentIssues.start(fullName: fullName)
        case .pullRequests:
            await currentPulls.start(fullName: fullName)
        case .commits:
            // ⚠️ 这两条判断与切片 6 的 `select(section:)` **逐字等价** ——
            //    那次只是把同一段逻辑挪进了一个函数，好让 `start()` 也能用它。
            guard !commits.hasLoaded else { return }
            await loadCommits(reset: true)
        }
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

    // MARK: - 切片 8.4：上传文件 / 图片（§5.8 的后两个出口）

    /// 把一份**已经在手上**的字节提交到仓库根（`sha` 恒为 `nil` —— 这是一次新建）。
    ///
    /// - Parameters:
    ///   - draft: 选中那一刻拿到的文件名与原始字节（`UploadDraft`，§5.8）。
    ///   - commit: 提交弹层里那一份草稿（提交信息 + 目标两档）。
    ///
    /// - Returns: 与编辑器共用同一个 `CommitAttempt`（提交弹层只认它）。
    ///
    /// ## ⚠️ 它**不复用** `EditorViewModel.submit`
    ///
    /// 两处的差别不是"路径从哪来"这一件事：那里是**文本**（要 UTF-8 编码、
    /// 要判 1MB）、这里是**原始字节**（§5.8 明写不重编码）；那里有"编辑模式 ⇒ 带 sha"
    /// 那一档、这里恒为新建。合成一处要加两三个开关，而每一个开关在两个调用点里
    /// 总有一处是错的。
    ///
    /// ⚠️ 与 `EditorViewModel.submit` **可能撞上同一条 409**：上传不带 `sha`，
    /// 失败只可能是 422（同名已存在）—— 而那一档的文案由 `FileWriteFailure` 给
    ///（`CommitSheetCopy.destinationExistsHint`，§5.8 明写"重名不静默覆盖"）。
    func upload(_ draft: UploadDraft, commit: CommitDraft) async -> CommitAttempt {
        // 这一屏取内容时一定解析过分支（`tree.load` 先定 ref、再取目录）——
        // 拿不到时说明目录还没加载出来，而那时也不该有「＋ 添加」可点。
        guard let branch = tree.branch else { return .rejected(ActionCopy.failed) }

        // ⚠️ 文件名虽然来自系统选择器，仍然过一遍**与新建文件同一套**判据：
        //    它是一串会变成路径的字节，而"界面看起来正常、路径不对"正是那套判据拦的东西。
        let path: RepoPath
        switch RepoPath.resolveNewFile(input: draft.fileName) {
        case let .acceptable(resolved): path = resolved
        case .rejected: return .rejected(ActionCopy.failed)
        }

        do {
            let outcome = try await saver.run(
                fullName: fullName,
                path: path,
                content: draft.data,
                draft: commit,
                // 新建：**不带 `sha`**（决策 #70⑤：路径已存在时服务端回 422，不静默覆盖）。
                sha: nil,
                currentBranch: branch
            )
            // 完全成功 ⇒ 目录与提交列表都变了（多了一个文件、多了一次提交）。
            // ⚠️ 两档"做到一半"**不刷新**：那一刻用户还在结果屏上读那句话，
            //    而列表在他背后换一次内容只会让人怀疑"我到底提交成功没有"。
            if outcome.isComplete {
                await tree.reload()
                if commits.hasLoaded { await loadCommits(reset: true) }
            }
            return .settled(outcome)
        } catch let error as BranchCreationError {
            // 新分支名不合法 —— 与编辑器同一条处置（表单校验，不是网络错误）。
            return .rejected(error.message)
        } catch {
            let failure = FileWriteFailure(Self.failure(from: error))
            return .rejected(failure.message ?? ActionCopy.failed)
        }
    }

    // MARK: - 错误归一化 / 文案

    /// 把任意错误收敛成 `GitHubError`（同其余 ViewModel：映射失败归 `.decoding`，
    /// **不是** `.transport` —— 后者会让界面给出"检查网络"的错误引导）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }

    /// PRD §7 没有给"Star 操作失败"那一句（同 `ExploreRepoViewModel`）。
    /// 那一句现在在 `GitDuoKit.ActionCopy.failed`（切片 7.4 收口 —— 本文件原有一份
    /// 同值副本 `actionFailedToast`，标签弹层的新建失败当时也借用了它）。
    /// 决策缺口本身**没有关闭**：仍登记在 `REVIEW-CHECKLIST §5`。
}
