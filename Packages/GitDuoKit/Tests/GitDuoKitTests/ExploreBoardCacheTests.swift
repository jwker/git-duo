import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 探索榜的**按组合复用缓存**（决策 #37、TECH_SPEC §9.10.5）。
///
/// ## 为什么这组断言重要
///
/// Search 配额**独立且只有 30 次/分钟**，而且与搜索页**共用同一个桶**。
/// 用户在新星 / 活跃 × 4 档日期 × 6 种语言之间来回点几下，一分钟内就能撞配额 ——
/// 而后果不是"探索页慢一点"，是**搜索页一起 403**。
///
/// 所以这里守的是三件事：
/// 1. **缓存键必须含全部筛选维度** —— 少一个 ⇒ "切回来却看到上一组筛选的结果"，
///    那比不缓存更糟；
/// 2. **LRU 的"最近用过"要真的重排** —— 漏了它，一个天天在用的组合会因"很久以前写过"
///    被淘汰，缓存退化成"随机命中"，而它看起来仍在工作；
/// 3. **到底之后不再出网** —— 漏了这道闸门，"滚到底自动加载"每滚一次扣一格配额。
@Suite("探索榜缓存 · LRU 与按组合复用")
struct ExploreBoardCacheTests {

    private let now = Date(timeIntervalSince1970: 1_786_000_000)
    private let offline = GitHubError.transport(URLError(.notConnectedToInternet))

    // MARK: - 替身

    private actor ScriptedSearchSource: RepositorySearchDataSource {

        private var pages: [SearchRepositoriesResult]
        private var failure: GitHubError?

        private(set) var callCount = 0
        private(set) var cursors: [URL?] = []

        init(pages: [SearchRepositoriesResult]) { self.pages = pages }

        func failWith(_ error: GitHubError) { failure = error }

        func search(
            query: String,
            sort: String,
            order: String,
            perPage: Int,
            cursor: URL?
        ) async throws -> SearchRepositoriesResult {
            callCount += 1
            cursors.append(cursor)
            if let failure { throw failure }
            guard let first = pages.first else {
                return SearchRepositoriesResult(items: [], nextCursor: nil, incompleteResults: false)
            }
            return pages.count > 1 ? pages.removeFirst() : first
        }
    }

    private func searchPage(
        _ names: [String],
        stars: Int = 100,
        next: String? = nil,
        incomplete: Bool = false
    ) -> SearchRepositoriesResult {
        SearchRepositoriesResult(
            items: names.map {
                SearchRepositoryDTO(
                    fullName: $0,
                    language: "Swift",
                    starCount: stars,
                    createdAt: Date(timeIntervalSince1970: 1_754_352_000),   // 2025-08-05 UTC
                    pushedAt: now.addingTimeInterval(-600)
                )
            },
            nextCursor: next.flatMap(URL.init(string:)),
            incompleteResults: incomplete
        )
    }

    private func row(_ name: String) -> TrendingRow {
        TrendingRow(
            summary: RepoSummary(fullName: name, starCount: 1),
            weeklyDelta: nil,
            createdAt: now,
            pushedAt: nil,
            indicators: []
        )
    }

    private func entry(_ name: String) -> ExploreBoardCache.Entry {
        ExploreBoardCache.Entry(rows: [row(name)], nextCursor: nil, incompleteResults: false)
    }

    private func key(
        board: TrendingBoard = .rising,
        range: ExploreDateRange? = .thisWeek,
        language: String? = nil
    ) -> ExploreCacheKey {
        ExploreCacheKey(board: board, filters: ExploreFilters(range: range, language: language))
    }

    // MARK: - LRU（纯值类型，可以同步断言）

    @Test("⚠️ 超过上限 ⇒ 淘汰**最久未用**的那个")
    func evictsLeastRecentlyUsed() {
        var cache = ExploreBoardCache(capacity: 2)
        cache.store(entry("a"), for: key(language: "Swift"))
        cache.store(entry("b"), for: key(language: "Rust"))
        cache.store(entry("c"), for: key(language: "Go"))

        #expect(cache.count == 2)
        #expect(cache.entry(for: key(language: "Swift")) == nil, "第一个进来的最久未用")
        #expect(cache.entry(for: key(language: "Rust")) != nil)
        #expect(cache.entry(for: key(language: "Go")) != nil)
    }

    @Test("⚠️ **读一次就算用过** ⇒ 它免于被淘汰（漏了这步，缓存会退化成随机命中）")
    func readingRefreshesRecency() {
        var cache = ExploreBoardCache(capacity: 2)
        cache.store(entry("a"), for: key(language: "Swift"))
        cache.store(entry("b"), for: key(language: "Rust"))

        _ = cache.entry(for: key(language: "Swift"))       // 命中 ⇒ Swift 变成"最近"
        cache.store(entry("c"), for: key(language: "Go"))  // 该淘汰的是 Rust

        #expect(cache.entry(for: key(language: "Rust")) == nil)
        #expect(cache.entry(for: key(language: "Swift")) != nil)
    }

    @Test("覆盖同一个组合**不会**把条目数撑大")
    func storingSameKeyDoesNotGrow() {
        var cache = ExploreBoardCache(capacity: 12)
        cache.store(entry("a"), for: key())
        cache.store(entry("b"), for: key())

        #expect(cache.count == 1)
        #expect(cache.entry(for: key())?.rows.first?.fullName == "b")
    }

    @Test("`invalidate` **只**移除那一个组合（下拉刷新只失效当前组合，不做整表失效）")
    func invalidateRemovesOnlyThatKey() {
        var cache = ExploreBoardCache()
        cache.store(entry("a"), for: key(language: "Swift"))
        cache.store(entry("b"), for: key(language: "Rust"))

        cache.invalidate(key(language: "Swift"))

        #expect(cache.count == 1)
        #expect(cache.entry(for: key(language: "Swift")) == nil)
        #expect(cache.entry(for: key(language: "Rust")) != nil)
    }

    @Test("`removeAll` 清干净（登出时随其余账号数据一并清理）")
    func removeAllClears() {
        var cache = ExploreBoardCache()
        cache.store(entry("a"), for: key(language: "Swift"))
        cache.store(entry("b"), for: key(language: "Rust"))

        cache.removeAll()

        #expect(cache.count == 0)
        #expect(cache.keys.isEmpty)
        #expect(cache.entry(for: key(language: "Swift")) == nil)
    }

    @Test("⚠️ 上限传 0 ⇒ 夹到 1（否则每次 `store` 都立刻淘汰自己 = 缓存永不命中）")
    func capacityIsClampedToAtLeastOne() {
        #expect(ExploreBoardCache(capacity: 0).capacity == 1)
        #expect(ExploreBoardCache(capacity: -5).capacity == 1)
        #expect(ExploreBoardCache().capacity == ExploreBoardPolicy.cacheCapacity)
        #expect(ExploreBoardPolicy.cacheCapacity == 12)
    }

    @Test("⚠️ 缓存键含**三个**维度：换任一维度都是不同的键")
    func cacheKeyCoversEveryFilterDimension() {
        // 少一个维度 ⇒ "切回来却看到上一组筛选的结果"，那比不缓存更糟。
        let base = key()
        #expect(key() != key(board: .active))
        #expect(key() != key(range: .today))
        #expect(key() != key(language: "Swift"))
        #expect(base == ExploreCacheKey(board: .rising, filters: .default))
    }

    @Test("`keys` 的顺序是「最久未用在前、最近用在后」")
    func keysExposeRecencyOrder() {
        var cache = ExploreBoardCache(capacity: 3)
        cache.store(entry("a"), for: key(language: "Swift"))
        cache.store(entry("b"), for: key(language: "Rust"))
        _ = cache.entry(for: key(language: "Swift"))

        #expect(cache.keys.last == key(language: "Swift"), "刚读过 ⇒ 在末尾")
    }

    // MARK: - 取数用例（actor）

    @Test("没拉过的组合 ⇒ `cached` 是 `nil`（视图据此先上骨架屏）；拉过之后有值")
    func cachedIsNilBeforeFirstLoad() async throws {
        let board = LoadTrendingBoard(
            source: ScriptedSearchSource(pages: [searchPage(["a/b"])]),
            snapshots: InMemoryStarSnapshotStore()
        )

        #expect(await board.cached(board: .rising, filters: .default) == nil)

        _ = try await board.load(board: .rising, filters: .default, now: now)

        #expect(await board.cached(board: .rising, filters: .default) != nil)
        #expect(await board.cachedKeyCount == 1)
    }

    @Test("⚠️ **已经到底就不再出网** —— 漏了这道闸门，滚到底每滚一次扣一格配额")
    func doesNotRefetchWhenExhausted() async throws {
        let source = ScriptedSearchSource(pages: [searchPage(["a/b"], next: nil)])
        let board = LoadTrendingBoard(source: source, snapshots: InMemoryStarSnapshotStore())

        _ = try await board.load(board: .rising, filters: .default, now: now)
        let afterFirst = await source.callCount

        _ = try await board.load(board: .rising, filters: .default, now: now)
        _ = try await board.load(board: .rising, filters: .default, now: now)

        #expect(await source.callCount == afterFirst, "游标为 nil 就说明后面没有了")
    }

    @Test("续页把缓存的游标传下去，并**追加去重**（同一条从第 2 页挪到第 1 页时不该出现两次）")
    func continuationAppendsAndDeduplicates() async throws {
        let next = "https://api.github.com/search/repositories?page=2"
        let source = ScriptedSearchSource(pages: [
            searchPage(["a/one"], next: next),
            searchPage(["a/one", "b/two"], next: nil),
        ])
        let board = LoadTrendingBoard(source: source, snapshots: InMemoryStarSnapshotStore())

        let first = try await board.load(board: .rising, filters: .default, now: now)
        #expect(first.rows.map(\.fullName) == ["a/one"])

        let second = try await board.load(board: .rising, filters: .default, now: now)

        #expect(second.rows.map(\.fullName) == ["a/one", "b/two"], "去重后只留一份 a/one")
        #expect(await source.cursors == [nil, URL(string: next)])
    }

    @Test("⚠️ `reset: true` **只失效当前组合** —— 整表失效会让一次下拉打光 Search 配额")
    func resetOnlyInvalidatesTheCurrentCombination() async throws {
        let source = ScriptedSearchSource(pages: [searchPage(["a/one"])])
        let board = LoadTrendingBoard(source: source, snapshots: InMemoryStarSnapshotStore())

        _ = try await board.load(board: .rising, filters: .default, now: now)
        _ = try await board.load(board: .active, filters: .default, now: now)
        #expect(await board.cachedKeyCount == 2)

        _ = try await board.load(board: .rising, filters: .default, reset: true, now: now)

        #expect(await board.cached(board: .active, filters: .default) != nil,
                "另一个组合的缓存必须还在")
        #expect(await board.cachedKeyCount == 2)
    }

    @Test("⚠️ 续页失败**不改动缓存** —— 已加载的内容必须留在屏幕上（§8.5）")
    func continuationFailureKeepsTheCache() async throws {
        let next = "https://api.github.com/search/repositories?page=2"
        let source = ScriptedSearchSource(pages: [searchPage(["a/one"], next: next)])
        let board = LoadTrendingBoard(source: source, snapshots: InMemoryStarSnapshotStore())

        _ = try await board.load(board: .rising, filters: .default, now: now)

        await source.failWith(offline)
        var threw = false
        do {
            _ = try await board.load(board: .rising, filters: .default, now: now)
        } catch {
            threw = true
        }

        #expect(threw)
        let cached = await board.cached(board: .rising, filters: .default)
        #expect(cached != nil, "清掉缓存等于一次失败就让用户彻底失去已加载的内容")
        #expect(cached?.nextCursor != nil, "游标也要留着，否则重试入口没了")
        #expect(cached?.rows.map(\.fullName) == ["a/one"])
    }

    @Test("`invalidateAll` 清空（登出）")
    func invalidateAllClearsEverything() async throws {
        let board = LoadTrendingBoard(
            source: ScriptedSearchSource(pages: [searchPage(["a/one"])]),
            snapshots: InMemoryStarSnapshotStore()
        )

        _ = try await board.load(board: .rising, filters: .default, now: now)
        _ = try await board.load(board: .active, filters: .default, now: now)
        #expect(await board.cachedKeyCount == 2)

        await board.invalidateAll()

        #expect(await board.cachedKeyCount == 0)
        #expect(await board.cached(board: .rising, filters: .default) == nil)
    }

    // MARK: - 基线与增幅

    @Test("⚠️ 首次见到某仓库**只记基线**（无增幅）；第二次差值算得出来（星数没变 ⇒ 0）")
    func firstSightOnlyRecordsTheBaseline() async throws {
        let source = ScriptedSearchSource(pages: [searchPage(["a/one"], stars: 100)])
        let board = LoadTrendingBoard(source: source, snapshots: InMemoryStarSnapshotStore())
        let filters = ExploreFilters(range: .thisWeek, language: nil)

        let first = try await board.load(board: .rising, filters: filters, now: now)
        #expect(first.rows.first?.weeklyDelta == nil, "首次见到没有基线可减 —— 那是「没问过」，不是 0")
        #expect(first.rows.first?.indicators.count == 1, "只剩创建日那一条")

        let second = try await board.load(board: .rising, filters: filters, reset: true, now: now)
        #expect(second.rows.first?.weeklyDelta == 0, "星数没变 ⇒ 差值就是 0（不是 nil）")
        #expect(second.rows.first?.indicators.count == 1, "0 被闸门挡住，仍然不显示增幅")
    }

    @Test("基线记的是**上一次看到的星数**，两次之间涨了就能算出增量")
    func baselineProducesAGainOnTheNextVisit() async throws {
        let snapshots = InMemoryStarSnapshotStore(seed: [
            StarSnapshot(fullName: "a/one", stars: 90, fetchedAt: now.addingTimeInterval(-3_600))
        ])
        let source = ScriptedSearchSource(pages: [searchPage(["a/one"], stars: 100)])
        let board = LoadTrendingBoard(source: source, snapshots: snapshots)

        let result = try await board.load(
            board: .rising,
            filters: ExploreFilters(range: .thisWeek, language: nil),
            now: now
        )

        #expect(result.rows.first?.weeklyDelta == 10)
        #expect(result.rows.first?.indicators.first?.text == "+10 本周")
    }

    // MARK: - `incomplete_results` 的两个出口

    @Test("⚠️ 结果不完整 ⇒ 说明行出现，且空态文案**不能说「没有符合条件的仓库」**")
    func incompleteResultsDrivesBothNoticeAndEmptyText() async throws {
        let source = ScriptedSearchSource(pages: [searchPage([], incomplete: true)])
        let board = LoadTrendingBoard(source: source, snapshots: InMemoryStarSnapshotStore())

        let result = try await board.load(board: .rising, filters: .default, now: now)

        #expect(result.rows.isEmpty)
        #expect(result.notice == ExploreBoardNotice.incompleteResults)
        #expect(result.emptyText == ExploreBoardNotice.incompleteResults,
                "GitHub 刚说过「我的回答不完整」，那一刻说「没有符合条件的仓库」是编造结论")
    }

    @Test("结果完整 ⇒ 不显示说明行，空态走正常的「没有符合条件的仓库」")
    func completeResultsUseTheNormalEmptyText() async throws {
        let source = ScriptedSearchSource(pages: [searchPage([])])
        let board = LoadTrendingBoard(source: source, snapshots: InMemoryStarSnapshotStore())

        let result = try await board.load(board: .rising, filters: .default, now: now)

        #expect(result.notice == nil)
        #expect(result.emptyText == ExploreBoardNotice.noResults)
        #expect(result.emptyText == "没有符合条件的仓库，试试放宽筛选")
    }

    @Test("⚠️ 累计口径：**只要有一页报过不完整，整份列表就不完整**")
    func incompleteIsStickyAcrossPages() async throws {
        let next = "https://api.github.com/search/repositories?page=2"
        let source = ScriptedSearchSource(pages: [
            searchPage(["a/one"], next: next, incomplete: true),
            searchPage(["b/two"], next: nil, incomplete: false),
        ])
        let board = LoadTrendingBoard(source: source, snapshots: InMemoryStarSnapshotStore())

        _ = try await board.load(board: .rising, filters: .default, now: now)
        let second = try await board.load(board: .rising, filters: .default, now: now)

        #expect(second.incompleteResults, "第二页完整不代表整份完整")
        #expect(second.notice != nil)
    }

    @Test("⚠️ 下拉刷新（`reset: true`）重新开始累计 —— 上一轮的不完整标记不该跟着留下")
    func resetClearsTheIncompleteFlag() async throws {
        let source = ScriptedSearchSource(pages: [
            searchPage(["a/one"], next: nil, incomplete: true),
            searchPage(["a/one"], next: nil, incomplete: false),
        ])
        let board = LoadTrendingBoard(source: source, snapshots: InMemoryStarSnapshotStore())

        let first = try await board.load(board: .rising, filters: .default, now: now)
        #expect(first.incompleteResults)

        let second = try await board.load(board: .rising, filters: .default, reset: true, now: now)
        #expect(!second.incompleteResults, "刷新拿到的是一份新的结果")
    }

    @Test("`Result` 的派生：`hasMore` / `isEmpty`")
    func resultDerivations() {
        let cursor = URL(string: "https://api.github.com/x?page=2")!
        let withMore = LoadTrendingBoard.Result(rows: [row("a/b")], nextCursor: cursor, incompleteResults: false)
        #expect(withMore.hasMore)
        #expect(!withMore.isEmpty)

        let done = LoadTrendingBoard.Result(rows: [], nextCursor: nil, incompleteResults: false)
        #expect(!done.hasMore)
        #expect(done.isEmpty)
    }
}
