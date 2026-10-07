import Foundation
import GitHubAPI

/// 仓库搜索的数据来源 —— 领域层与网络层之间的**接缝**（同 `RepositoryDataSource`）。
///
/// 之所以要这层：探索榜的取数里有一堆**业务规则**（限定符怎么拼、基线怎么算、组合怎么复用、
/// 续页怎么追加），而"HTTP 头带没带版本号""`Link` 头怎么解"已经由 `GitHubAPITests`
/// 用真实 `URLProtocol` 桩件覆盖过了。有了接缝，本包的测试直接喂一页结果进去就行。
public protocol RepositorySearchDataSource: Sendable {

    /// `GET /search/repositories` 的一页。
    ///
    /// ⚠️ 参数名与标签必须与 `GitHubSearchRepositoriesEndpoint.search` **逐字一致**：
    ///    协议要求的实参标签与实现不符时，Swift 不会给出"差一个标签"这种提示，
    ///    而是报"类型不满足协议"，排查时很容易绕远路。
    ///
    /// ⚠️ `sort` 是**可选**的：探索榜两种榜各带各的（`stars` / `updated`），
    ///    而搜索页要的是服务端的 best match —— 那只能靠**不带** `sort` 表达
    ///    （`sort=best+match` 不是合法取值）。这条"可选"是 2026-10-07 切片 5.2 补的。
    func search(
        query: String,
        sort: String?,
        order: String,
        perPage: Int,
        cursor: URL?
    ) async throws -> SearchRepositoriesResult
}

/// 让真实端点满足上面的接缝（协议是我们自己声明的，不是追溯适配）。
extension GitHubSearchRepositoriesEndpoint: RepositorySearchDataSource {}

/// 探索榜的取数用例（TECH_SPEC §9.10.1 / §9.10.2 / §9.10.5、决策 #36 / #37）。
///
/// ## 它把四件事钉在一处
///
/// 1. **拼查询**（`ExploreQueryBuilder`，纯逻辑、已单测）；
/// 2. **算增幅**（读旧快照 → 写新快照 → 相减，顺序反了增量恒为 0）；
/// 3. **拼行**（`TrendingRowBuilder`，含排序与角标）；
/// 4. **按组合复用**（`ExploreBoardCache`，LRU 12、不落盘）。
///
/// 四件事必须同时成立才不会出现"数字好看但含义是假的"—— 所以它们在一个类型里，
/// 而不是散在 ViewModel 中（App target 没有测试 target，散过去就等于没人守）。
///
/// ## 它是 actor：并发保护只做一处
///
/// `ExploreBoardCache` 是值类型（见其注释），互斥由本 actor 提供。这样"两个连点同时到达"
/// 不会让同一条缓存被写两次、也不会让 LRU 顺序错乱。
///
/// ⚠️ **它不做防抖**：防抖是"用户还在点，先别发"的**交互策略**，
/// 属于 ViewModel（那里才知道有没有新的点击到来）。本类型只保证"被调一次就正确一次"。
public actor LoadTrendingBoard {

    /// 一个组合下**累计**的榜单内容。
    public struct Result: Sendable, Hashable {

        public let rows: [TrendingRow]
        public let nextCursor: URL?
        public let incompleteResults: Bool

        public var hasMore: Bool { nextCursor != nil }
        public var isEmpty: Bool { rows.isEmpty }

        /// 列表说明行（`nil` = 不显示）。
        public var notice: String? {
            incompleteResults ? ExploreBoardNotice.incompleteResults : nil
        }

        /// 空态文案 —— ⚠️ 结果不完整时**不能说"没有符合条件的仓库"**（见 `ExploreBoardNotice`）。
        public var emptyText: String {
            ExploreBoardNotice.emptyStateText(isIncomplete: incompleteResults)
        }
    }

    private let source: any RepositorySearchDataSource
    private let mapper: RepoSummaryMapper
    private let snapshots: any StarSnapshotStore
    private var cache: ExploreBoardCache

    public init(
        source: any RepositorySearchDataSource,
        snapshots: any StarSnapshotStore,
        cache: ExploreBoardCache = ExploreBoardCache(),
        mapper: RepoSummaryMapper = RepoSummaryMapper()
    ) {
        self.source = source
        self.snapshots = snapshots
        self.cache = cache
        self.mapper = mapper
    }

    // MARK: - 读缓存

    /// 该组合已缓存的内容（**命中即可直接上屏，不出网、不花配额**）；`nil` = 这个组合没拉过。
    ///
    /// ViewModel 用它区分"切到一个新组合 ⇒ 先上骨架屏"与"切回老组合 ⇒ 秒开"。
    public func cached(board: TrendingBoard, filters: ExploreFilters) -> Result? {
        cache.entry(for: ExploreCacheKey(board: board, filters: filters)).map(Self.result(from:))
    }

    // MARK: - 取数

    /// 取该组合的下一页。
    ///
    /// - Parameter reset: 下拉刷新 —— 从头取第一页并**只失效当前组合**（§9.10.5）。
    /// - Parameter now: 显式传入，不内部取 `Date()`（限定符与相对文案都要它，且必须可测）。
    ///
    /// - Returns: 该组合**累计**的内容（含本次新增的部分）。
    ///
    /// ## 续页是"追加"而不是"重排"
    ///
    /// §9.10.5 明写"续页结果**追加在当前组合**下"。所以第 2 页之后不再对整份列表重排 ——
    /// 重排会把刚加载进来的高增幅仓库插到已渲染列表的中段，用户的滚动位置会当场跳走。
    /// 代价是"整份列表并非全局严格降序"，收益是滚动时列表不抖。
    ///
    /// ## 已经到底就不再出网
    ///
    /// 缓存里有内容、且 `nextCursor == nil` ⇒ 直接返回，**不打这一发空请求**。
    /// 漏掉这道闸门，"滚到底自动加载"会在到底之后每滚动一次扣一格 Search 配额。
    ///
    /// ⚠️ 续页失败时**不改动缓存**（`try` 抛在写回之前）：已加载的内容必须留在屏幕上（§8.5），
    /// 而清掉游标等于一次失败就让用户彻底失去"加载更多"的入口 —— 与 `PagedListState`
    /// 的 `failed(_:)` 同一取向。
    public func load(
        board: TrendingBoard,
        filters: ExploreFilters,
        reset: Bool = false,
        now: Date
    ) async throws -> Result {
        let key = ExploreCacheKey(board: board, filters: filters)
        let existing = reset ? nil : cache.entry(for: key)

        if let existing, !existing.hasMore {
            return Self.result(from: existing)
        }

        let query = ExploreQueryBuilder.query(board: board, filters: filters, now: now)
        let response = try await source.search(
            query: query.qualifiers,
            sort: query.sort,
            order: query.order,
            perPage: query.perPage,
            cursor: existing?.nextCursor
        )
        let mapped = try mapper.map(response)

        // ⚠️ **先读旧快照、再写新快照** —— 顺序反了增量恒为 0（§9.10.2）。
        //    两者都在 `snapshots` 这个 actor 上，所以这里逐个 await；一页 30 条，
        //    是内存字典读写，不是网络往返。
        var sources: [TrendingRowBuilder.Source] = []
        sources.reserveCapacity(mapped.items.count)
        for (summary, dto) in zip(mapped.items, response.items) {
            let previous = await snapshots.snapshot(for: summary.fullName)
            await snapshots.record(fullName: summary.fullName, stars: summary.starCount, at: now)
            sources.append(TrendingRowBuilder.Source(
                summary: summary,
                createdAt: dto.createdAt,
                pushedAt: dto.pushedAt,
                // `nil` 表示"没基线"（首次见到）——**不是** 0。
                weeklyDelta: previous.map { summary.starCount - $0.stars }
            ))
        }

        let page = TrendingRowBuilder.rows(board: board, filters: filters, sources: sources, now: now)
        let rows = reset ? page : Self.merged(existing?.rows ?? [], page)

        let result = Result(
            rows: rows,
            // 游标取**这一页**给的：`nil` 就是真的到底了。
            nextCursor: mapped.nextCursor,
            // 累计口径：只要有任何一页报过不完整，整份列表就谈不上完整。
            incompleteResults: mapped.incompleteResults || (reset ? false : existing?.incompleteResults ?? false)
        )

        cache.store(
            ExploreBoardCache.Entry(
                rows: result.rows,
                nextCursor: result.nextCursor,
                incompleteResults: result.incompleteResults
            ),
            for: key
        )
        return result
    }

    // MARK: - 失效

    /// 清空全部组合（登出时随其余账号数据一并清理，§9.10.5）。
    public func invalidateAll() {
        cache.removeAll()
    }

    /// 当前缓存的组合数（仅供排查与测试）。
    public var cachedKeyCount: Int { cache.count }

    // MARK: - 内部

    private static func result(from entry: ExploreBoardCache.Entry) -> Result {
        Result(rows: entry.rows, nextCursor: entry.nextCursor, incompleteResults: entry.incompleteResults)
    }

    /// 追加并按仓库全名去重，**保留已在列表里的那份**。
    ///
    /// 去重不是洁癖：榜单按 `pushed` / `stars` 排序，翻页期间有人推了一次提交或涨了星，
    /// 就会让某一条从第 2 页挪到第 1 页 —— 于是它在两页里各出现一次。
    /// 不去重的话 `ForEach` 会拿到两个相同的 id（渲染告警 + 视觉上是重复行）。
    /// 保留旧的那份，是为了不替换已经渲染出来的行（与 `PagedListState.merged` 同一取舍）。
    private static func merged(_ existing: [TrendingRow], _ incoming: [TrendingRow]) -> [TrendingRow] {
        var seen = Set(existing.map(\.id))
        var result = existing
        for row in incoming where seen.insert(row.id).inserted {
            result.append(row)
        }
        return result
    }
}
