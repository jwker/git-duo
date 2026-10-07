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
///
/// 后两条**有意懒加载**：主桶配额虽然宽（5,000/小时），但"进一个仓库就发四个请求"
/// 会让每次点开的等待都变成最慢那条链路的长度 —— 而 Commits 与分支列表
/// 用户可能整次访问都不看（§4.4 的默认分区是「代码」）。
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

    // MARK: - 依赖

    private let detailLoader: LoadRepoDetail
    private let commitsLoader: LoadRepoCommits
    private let starToggle: ToggleStar
    private let visits: any RecentVisitStore
    private let toast: ToastCenter

    let fullName: String

    init(
        fullName: String,
        section: RepoSection,
        path: RepoPath,
        detail: LoadRepoDetail,
        treeLoader: LoadRepoTree,
        commits: LoadRepoCommits,
        branches: LoadBranches,
        starToggle: ToggleStar,
        memory: any BranchMemoryStore,
        visits: any RecentVisitStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.section = section
        self.detailLoader = detail
        self.commitsLoader = commits
        self.starToggle = starToggle
        self.visits = visits
        self.toast = toast
        self.tree = RepoTreeSession(
            fullName: fullName,
            path: path,
            loader: treeLoader,
            branches: branches,
            memory: memory
        )
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
    }

    /// 下拉刷新：头部（连带 Star 基准）+ 当前目录，一起重取。
    ///
    /// ⚠️ **不刷新已加载的提交列表**：它有自己的"加载更多"与游标，
    /// 从头部那一侧重置它会丢掉用户已经翻过的页（§8.5 的"刷新不遮挡已有内容"
    /// 说的是别把内容清掉，而这里连语义都不该变）。
    func refresh() async {
        await loadDetail(keepContent: true)
    }

    /// 切分段。切到 Commits 时**首次**才去取列表（懒加载，见类型说明）。
    func select(section: RepoSection) async {
        self.section = section
        guard section == .commits else { return }
        guard !commits.hasLoaded else { return }
        await loadCommits(reset: true)
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
            toast.show(Self.actionFailedToast)
        }
    }

    // MARK: - 提交列表

    func loadMoreCommits() async {
        guard commits.canLoadMore, !commits.isLoading else { return }
        await loadCommits(reset: false)
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
                toast.show(Self.refreshFailedToast)
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

    // MARK: - 错误归一化 / 文案

    /// 把任意错误收敛成 `GitHubError`（同其余 ViewModel：映射失败归 `.decoding`，
    /// **不是** `.transport` —— 后者会让界面给出"检查网络"的错误引导）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }

    /// PRD §7 没有给"Star 操作失败"那一句（同 `ExploreRepoViewModel`）。
    /// 已登记在 `REVIEW-CHECKLIST §5`。
    static let actionFailedToast = "操作失败 · 请重试"

    /// 同 `ExploreRepoCopy.refreshFailed`：§7 假定刷新失败时整屏变失败态，
    /// 而**已有内容时**不能那样做（§8.5）。
    static let refreshFailedToast = "刷新失败 · 下拉可重试"
}
