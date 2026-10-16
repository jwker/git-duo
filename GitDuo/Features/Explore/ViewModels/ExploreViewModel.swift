import Foundation
import GitHubAPI
import GitDuoKit

/// 探索页的状态（PRD §4.12 / TECH_SPEC §9.10.3、§9.10.5）。
///
/// ## 它把三件事管住
///
/// 1. **组合**：当前榜单 + 两个筛选（`ExploreCacheKey` 就是这个三元组）；
/// 2. **防抖与取消**：用户连点分段 / 筛选时，只让**最后那一次**真的出网
///    （TECH_SPEC §9.10.3 + §9.2 同一纪律：Search 配额独立且只有 30/min）；
/// 3. **缓存优先**：切回老组合**秒开、不出网**（PRD §4.12 把这条列为交互要求）。
///
/// ## 它不实现缓存本身
///
/// 缓存在 `LoadTrendingBoard`（actor，LRU 12，**不落盘**）里 —— 那是"取数"的一部分，
/// 而且它要跟"算增幅、拼行"在同一个类型里才不会出现"数字好看但含义是假的"。
/// 本类型只负责**问它有没有**、以及把用户动作翻成对它的调用。
///
/// ## 防抖为什么在 ViewModel 而不在取数层
///
/// 防抖是"用户还在点，先别发"的**交互策略** —— 只有这里才知道有没有新的点击到来。
/// `LoadTrendingBoard` 的保证是"被调一次就正确一次"（其类型说明也这么写了）。
@MainActor
@Observable
final class ExploreViewModel {

    // MARK: - 组合

    private(set) var board: TrendingBoard = .rising

    /// 初始 `日期范围 = 本周`、`语言 = 未选`（PRD §3.12；`ExploreFilters.default`）。
    private(set) var filters: ExploreFilters = .default

    // MARK: - 内容

    private var state = PagedListState<TrendingRow>()

    /// `incomplete_results` 的说明行（`nil` = 不显示）。**不是错误态**（PRD §4.12）。
    private(set) var notice: String?

    /// 空态文案 —— ⚠️ 结果不完整时**不能说"没有符合条件的仓库"**（`ExploreBoardNotice`）。
    private(set) var emptyText: String = ExploreBoardNotice.noResults

    private let loader: LoadTrendingBoard

    /// 在途的那一次（防抖 + 取消用它）。
    private var pending: Task<Void, Never>?

    init(loader: LoadTrendingBoard) {
        self.loader = loader
    }

    // MARK: - 供视图读取

    var rows: [TrendingRow] { state.items }

    var content: PagedListContent { state.content() }

    var isLoading: Bool { state.isLoading }

    var hasMore: Bool { state.canLoadMore }

    /// 最近一次失败。**与 `rows` 并存** —— 有内容时它只驱动底部的重试行（§8.5）。
    var error: GitHubError? { state.error }

    // MARK: - 生命周期

    func loadIfNeeded() async {
        guard !state.hasLoaded else { return }
        schedule(reset: false)
    }

    /// 下拉刷新：重取第一页。
    ///
    /// ⚠️ `reset: true` 在 `LoadTrendingBoard` 里是"**只失效当前组合**"（§9.10.5）——
    /// 整表失效会让一次下拉打光 Search 配额。
    ///
    /// 先取消在途的那一次：刷新与"防抖后即将发出的那一次"是同一个组合的两发请求，
    /// 让它们都发出去不但白花配额，返回顺序还可能让**先发的后到**而覆盖掉新结果。
    func refresh() async {
        pending?.cancel()
        pending = nil
        await perform(board: board, filters: filters, reset: true)
    }

    /// 滚到底自动加载 / 底部「重试」。
    func loadMore() async {
        guard state.canLoadMore, !state.isLoading else { return }
        schedule(reset: false)
    }

    // MARK: - 用户动作

    /// 切榜单。**不影响已选筛选项**（PRD §4.12）。
    func select(board newBoard: TrendingBoard) {
        guard newBoard != board else { return }
        board = newBoard
        schedule(reset: false)
    }

    /// 切日期范围。返回值由视图转成提示（`日期范围：本周` / `…：已取消，显示全部`）。
    ///
    /// 提示文案由 `ExploreFilterChange.toastText` 生成（领域层）——
    /// 那两句是"再点当前项 = 取消"这条规则的**唯一可见证据**，散进视图就没人守得住。
    @discardableResult
    func select(range value: ExploreDateRange) -> ExploreFilterChange {
        let change = filters.select(range: value)
        schedule(reset: false)
        return change
    }

    @discardableResult
    func select(language value: String) -> ExploreFilterChange {
        let change = filters.select(language: value)
        schedule(reset: false)
        return change
    }

    // MARK: - 内部

    /// 调度一次加载：**取消在途 → 缓存命中即秒开 → 否则防抖后取数**。
    private func schedule(reset: Bool) {
        pending?.cancel()

        let board = self.board
        let filters = self.filters

        pending = Task { [weak self] in
            guard let self else { return }

            // ① 缓存命中：直接上屏，**不出网、不花配额**（PRD §4.12「来回切换直接命中」）。
            //    这一步**不做防抖** —— 它本来就不花代价，"等 300ms 再显示已有内容"只是平白发顿。
            if !reset, let cached = await loader.cached(board: board, filters: filters) {
                guard !Task.isCancelled else { return }
                self.apply(cached, replacing: true)
                return
            }

            // ② 没命中：先把旧的整块换掉（否则用户会对着上一个组合的列表等新结果，然后看到它跳一下）。
            if !reset { self.beginNewCombo() }

            // ③ 防抖：用户还在点，先别发。
            try? await Task.sleep(for: ExploreBoardPolicy.switchDebounce)
            guard !Task.isCancelled else { return }

            await self.perform(board: board, filters: filters, reset: reset)
        }
    }

    /// 真的出一趟网。
    ///
    /// - Parameter board: 这次请求**属于哪个组合**（调用时就固定下来）。
    private func perform(board: TrendingBoard, filters: ExploreFilters, reset: Bool) async {
        // ⚠️ 组合已经变了 ⇒ 这次结果作废。
        //    漏掉这道守卫的表现是"数据不对"：用户切到活跃榜，屏幕上却是新星榜的结果，
        //    而且它看起来完全正常（有内容、有标题、不报错）。
        guard board == self.board, filters == self.filters else { return }
        guard !state.isLoading || reset else { return }

        var working = state
        working.beginLoad(reset: reset)
        state = working

        do {
            let result = try await loader.load(board: board, filters: filters, reset: reset, now: Date())
            // 回来后**再确认一次**：`await` 期间用户可能已经切走了。
            guard board == self.board, filters == self.filters else { return }
            apply(result, replacing: reset)
        } catch is CancellationError {
            // 取消不是失败（用户自己切走了），**不要**把它渲染成"加载失败"。
        } catch {
            guard board == self.board, filters == self.filters else { return }
            var latest = state
            latest.failed(Self.failure(from: error))
            state = latest
        }
    }

    private func beginNewCombo() {
        state = PagedListState()
        notice = nil
    }

    private func apply(_ result: LoadTrendingBoard.Result, replacing: Bool) {
        var working = state
        if replacing { working.beginLoad(reset: true) }
        working.received(Page(items: result.rows, nextCursor: result.nextCursor))
        state = working
        notice = result.notice
        emptyText = result.emptyText
    }

    /// 把任意错误收敛成 `GitHubError`（同 `RepoListViewModel.failure(from:)` 的口径：
    /// 映射失败归 `.decoding`，**不是** `.transport`）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}
