import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 搜索取数（PRD §4.2、TECH_SPEC §9.2、决策 #44）。
///
/// 这里守的是四件**错了也照样跑**的事：
/// 1. 「Issue · PR」真的发了两条（少一条不报错，只是那个类型永远搜不到）；
/// 2. 已经到底的那条 part 不再重发（漏了 ⇒ 每点一次「加载更多」白扣一格配额）；
/// 3. 续页是**追加**不是重排（重排会让列表在用户眼前跳走）；
/// 4. 失败**不改动缓存**（改了就一次失败丢掉用户已加载的内容）。
@Suite("LoadSearch · 分发 / 合并 / 缓存")
struct LoadSearchTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let reposNext = URL(string: "https://api.github.com/search/repositories?page=2")!
    private let issuesNext = URL(string: "https://api.github.com/search/issues?q=x&page=2")!

    // MARK: - 小工具

    private func query(_ scope: SearchScope, _ keyword: String) throws -> SearchQuery {
        try #require(SearchQueryBuilder.readiness(scope: scope, keyword: keyword).query)
    }

    private func repoPage(
        _ names: [String],
        total: Int,
        next: URL? = nil,
        incomplete: Bool = false
    ) -> SearchHitPage {
        SearchHitPage(
            rows: names.map { .repository(RepositoryHit(fullName: $0, starCount: 1)) },
            totalCount: total,
            nextCursor: next,
            incompleteResults: incomplete
        )
    }

    private func convPage(
        _ items: [(String, Int, ConversationKind)],
        total: Int,
        next: URL? = nil,
        incomplete: Bool = false
    ) -> SearchHitPage {
        SearchHitPage(
            rows: items.map { repo, number, kind in
                .conversation(ConversationHit(
                    kind: kind, number: number, title: "t",
                    repoFullName: repo, state: .open, updatedAt: base
                ))
            },
            totalCount: total,
            nextCursor: next,
            incompleteResults: incomplete
        )
    }

    // MARK: - 分发

    @Test("仓库范围：发**一条**查询，行 / 总数 / 页大小照搬")
    func repositoriesLoadsOneQuery() async throws {
        let source = ScriptedSearchSource(scripts: ["swiftui": [repoPage(["a/one", "b/two"], total: 2)]])
        let loader = LoadSearch(source: source)

        let result = try await loader.load(try query(.repositories, "swiftui"))

        #expect(result.rows.map(\.id) == ["repo:a/one", "repo:b/two"])
        #expect(result.totalCount == 2)
        #expect(!result.hasMore)
        #expect(result.notice == nil)

        let calls = await source.calls
        #expect(calls.count == 1)
        #expect(calls[0].qualifiers == "swiftui")
        #expect(calls[0].perPage == 30)
        #expect(calls[0].cursor == nil)
    }

    @Test("⚠️「Issue · PR」发**两条**（官方限制：不带 is: 直接 422），且 Issue 在前")
    func issuesLoadsTwoQueries() async throws {
        let source = ScriptedSearchSource(scripts: [
            "登录 is:issue": [convPage([("o/r", 42, .issue), ("o/r", 39, .issue)], total: 40)],
            "登录 is:pull-request": [convPage([("o/r", 57, .pullRequest)], total: 12)]
        ])
        let loader = LoadSearch(source: source)

        let result = try await loader.load(try query(.issues, "登录"))

        // 顺序 = parts 顺序（Issue 在前、PR 在后），与原型 `ISSUES.concat(PRS)` 同序。
        #expect(result.rows.map(\.id) == [
            "issue:o/r#42",
            "issue:o/r#39",
            "pr:o/r#57"
        ])
        #expect(result.totalCount == 52, "40 + 12 —— 两个不相交集合，相加才是屏幕上的那个数")
        #expect(!result.hasMore)

        let calls = await source.calls
        #expect(calls.map(\.qualifiers) == ["登录 is:issue", "登录 is:pull-request"])
        #expect(calls.map(\.scope) == [.issues, .issues])
    }

    // MARK: - 续页

    @Test("续页把**上一页的 nextCursor** 传回同一条 part")
    func nextPagePassesCursor() async throws {
        let source = ScriptedSearchSource(scripts: [
            "swiftui": [
                repoPage(["a/one"], total: 2, next: reposNext),
                repoPage(["b/two"], total: 2)
            ]
        ])
        let loader = LoadSearch(source: source)
        let q = try query(.repositories, "swiftui")

        let first = try await loader.load(q)
        #expect(first.hasMore)

        let second = try await loader.load(q)
        #expect(second.rows.map(\.id) == ["repo:a/one", "repo:b/two"])
        #expect(!second.hasMore)

        let calls = await source.calls
        #expect(calls.map(\.cursor).count == 2)
        #expect(calls[0].cursor == nil)
        #expect(calls[1].cursor == reposNext, "游标没传下去，「加载更多」会永远拿回第一页")
    }

    @Test("续页是**追加**：已渲染的行留在原位，新行接到后面")
    func nextPageAppends() async throws {
        let source = ScriptedSearchSource(scripts: [
            "swiftui": [
                repoPage(["a/one", "b/two"], total: 3, next: reposNext),
                repoPage(["c/three"], total: 3)
            ]
        ])
        let loader = LoadSearch(source: source)
        let q = try query(.repositories, "swiftui")

        _ = try await loader.load(q)
        let second = try await loader.load(q)

        #expect(second.rows.map(\.id) == ["repo:a/one", "repo:b/two", "repo:c/three"])
    }

    @Test("⚠️ 到底之后**一发请求都不发**（漏了这道闸门，每点一次「加载更多」白扣一格配额）")
    func exhaustedScopeStopsRequesting() async throws {
        let source = ScriptedSearchSource(scripts: ["swiftui": [repoPage(["a/one"], total: 1)]])
        let loader = LoadSearch(source: source)
        let q = try query(.repositories, "swiftui")

        _ = try await loader.load(q)
        _ = try await loader.load(q)
        _ = try await loader.load(q)

        #expect(await source.calls.count == 1)
    }

    @Test("⚠️ 两条 part 深度不同：到底的那条**跳过**，还剩下的那条继续发")
    func exhaustedPartIsSkipped() async throws {
        let source = ScriptedSearchSource(scripts: [
            // Issue 还有下一页；PR 一次到底。
            "登录 is:issue": [
                convPage([("o/r", 1, .issue)], total: 2, next: issuesNext),
                convPage([("o/r", 2, .issue)], total: 2)
            ],
            "登录 is:pull-request": [convPage([("o/r", 9, .pullRequest)], total: 1)]
        ])
        let loader = LoadSearch(source: source)
        let q = try query(.issues, "登录")

        _ = try await loader.load(q)
        #expect(await source.calls.count == 2)

        let second = try await loader.load(q)

        let calls = await source.calls
        #expect(calls.count == 3, "PR 那条到底了，不该再问一次（问一次就是白扣一格）")
        #expect(calls.last?.qualifiers == "登录 is:issue")
        #expect(calls.last?.cursor == issuesNext)
        // 跳到的那条 PR 行仍在（用上一次的结果），且排在 Issue 后面。
        #expect(second.rows.map(\.id) == [
            "issue:o/r#1",
            "issue:o/r#2",
            "pr:o/r#9"
        ])
        #expect(!second.hasMore)
    }

    @Test("⚠️ 重复 id 只留**先到的那一份**（翻页期间内容变动会让同一条出现在两页里）")
    func duplicateRowsAreDeduplicated() async throws {
        let source = ScriptedSearchSource(scripts: [
            "swiftui": [
                repoPage(["a/one"], total: 2, next: reposNext),
                repoPage(["a/one", "b/two"], total: 2)
            ]
        ])
        let loader = LoadSearch(source: source)
        let q = try query(.repositories, "swiftui")

        _ = try await loader.load(q)
        let second = try await loader.load(q)

        #expect(second.rows.map(\.id) == ["repo:a/one", "repo:b/two"])
        #expect(second.rows.count == Set(second.rows.map(\.id)).count)
    }

    // MARK: - 首次与重搜

    @Test("第一次 `load(reset: false)` 也从头取（没有缓存时 `reset` 无从谈起）")
    func firstLoadAlwaysFetchesFirstPage() async throws {
        let source = ScriptedSearchSource(scripts: ["swiftui": [repoPage(["a/one"], total: 1)]])
        let loader = LoadSearch(source: source)

        _ = try await loader.load(try query(.repositories, "swiftui"), reset: false)

        #expect(await source.calls.map(\.cursor) == [nil])
    }

    @Test("`reset: true` 重取第一页，并**整体替换**（改关键词后不该留着上一个词的行）")
    func resetReplacesEverything() async throws {
        let source = ScriptedSearchSource(scripts: [
            "swiftui": [
                repoPage(["a/one"], total: 2, next: reposNext),
                repoPage(["z/nine"], total: 1)
            ]
        ])
        let loader = LoadSearch(source: source)
        let q = try query(.repositories, "swiftui")

        _ = try await loader.load(q)
        let again = try await loader.load(q, reset: true)

        #expect(again.rows.map(\.id) == ["repo:z/nine"])
        #expect(!again.hasMore)
        #expect(await source.calls.map(\.cursor) == [nil, nil], "重搜必须从第一页开始")
    }

    // MARK: - 说明行与不完整

    @Test("说明行：只要任何一页报过 `incomplete_results`，整份列表就带那句提示")
    func incompleteAccumulates() async throws {
        let source = ScriptedSearchSource(scripts: [
            "swiftui": [
                repoPage(["a/one"], total: 2, next: reposNext, incomplete: true),
                repoPage(["b/two"], total: 2)
            ]
        ])
        let loader = LoadSearch(source: source)
        let q = try query(.repositories, "swiftui")

        let first = try await loader.load(q)
        #expect(first.notice == SearchCopy.incompleteResults)

        let second = try await loader.load(q)
        #expect(second.notice == SearchCopy.incompleteResults, "第二页完整 ≠ 整份列表完整")
    }

    @Test("⚠️「Issue · PR」两条里任一条不完整 ⇒ 也要提示")
    func incompleteFromEitherPart() async throws {
        let source = ScriptedSearchSource(scripts: [
            "登录 is:issue": [convPage([("o/r", 1, .issue)], total: 1)],
            "登录 is:pull-request": [convPage([], total: 0, incomplete: true)]
        ])
        let loader = LoadSearch(source: source)

        let result = try await loader.load(try query(.issues, "登录"))

        #expect(result.rows.count == 1)
        #expect(result.notice == SearchCopy.incompleteResults)
    }

    @Test("没有匹配 ⇒ 空行 + 总数为 0（空态文案由视图按 `SearchCopy` 决定）")
    func emptyResults() async throws {
        let source = ScriptedSearchSource(scripts: ["zzz": [repoPage([], total: 0)]])
        let loader = LoadSearch(source: source)

        let result = try await loader.load(try query(.repositories, "zzz"))

        #expect(result.isEmpty)
        #expect(result.totalCount == 0)
        #expect(!result.hasMore)
        #expect(result.notice == nil)
    }

    // MARK: - 失败

    @Test("⚠️ 失败**不改动缓存**：已经加载的内容必须留在屏幕上（§8.5）")
    func failureKeepsPreviousContent() async throws {
        let source = ScriptedSearchSource(scripts: [
            "swiftui": [
                repoPage(["a/one"], total: 2, next: reposNext),
                repoPage(["b/two"], total: 2)
            ]
        ])
        let loader = LoadSearch(source: source)
        let q = try query(.repositories, "swiftui")

        _ = try await loader.load(q)
        await source.failWith(.serverError(status: 500))

        await #expect(throws: GitHubError.self) { _ = try await loader.load(q) }

        let refreshed = await loader.cached(q)
        let cached = try #require(refreshed)
        #expect(cached.rows.map(\.id) == ["repo:a/one"], "失败不该把已加载的行擦掉")
        #expect(cached.hasMore, "也不该清掉游标 —— 清了用户就永远没有重试入口")
    }

    @Test("⚠️「Issue · PR」其中一条失败 ⇒ **整次失败**（不做「哪条成功写哪条」）")
    func anyPartFailureFailsTheWholeLoad() async throws {
        let source = ScriptedSearchSource(scripts: [
            "登录 is:issue": [convPage([("o/r", 1, .issue)], total: 1)]
        ])
        await source.failWith(.serverError(status: 502))
        let loader = LoadSearch(source: source)

        await #expect(throws: GitHubError.self) {
            _ = try await loader.load(try query(.issues, "登录"))
        }
        #expect(
            await loader.cachedKeyCount == 0,
            "整次失败 ⇒ 不该在缓存里留下「一半新一半旧」的结果"
        )
    }

    // MARK: - 缓存

    @Test("切范围再切回来 ⇒ 命中缓存，**一发请求都不补**（配额只有 30/min）")
    func switchingBackHitsCache() async throws {
        // ⚠️ 用户范围的 `q=` 与仓库范围**长得一样**（都是用户输入），
        //    所以这里两份脚本共用同一个键 —— 而缓存键里含范围，两者仍是两个组合。
        let source = ScriptedSearchSource(scripts: ["swiftui": [repoPage(["a/one"], total: 1)]])
        let loader = LoadSearch(source: source)
        let repos = try query(.repositories, "swiftui")
        let users = try query(.users, "swiftui")

        _ = try await loader.load(repos)
        _ = try await loader.load(users)
        #expect(await source.calls.count == 2)

        let back = try await loader.load(repos)

        #expect(back.rows.map(\.id) == ["repo:a/one"])
        #expect(await source.calls.count == 2, "切回老组合不该重发")
    }

    @Test("关键词变了就**不是**命中缓存（键含关键词）")
    func differentKeywordIsNotACacheHit() async throws {
        let source = ScriptedSearchSource(scripts: [
            "swiftui": [repoPage(["a/one"], total: 1)],
            "markdown": [repoPage(["b/two"], total: 1)]
        ])
        let loader = LoadSearch(source: source)

        _ = try await loader.load(try query(.repositories, "swiftui"))
        let other = try await loader.load(try query(.repositories, "markdown"))

        #expect(other.rows.map(\.id) == ["repo:b/two"])
        #expect(await source.calls.count == 2)
    }

    @Test("缓存键把关键词两端去空白（否则「`swiftui `」与「`swiftui`」会各占一格缓存）")
    func cacheKeyUsesTrimmedKeyword() async throws {
        let source = ScriptedSearchSource(scripts: ["swiftui": [repoPage(["a/one"], total: 1)]])
        let loader = LoadSearch(source: source)

        _ = try await loader.load(try query(.repositories, "swiftui"))
        _ = try await loader.load(try query(.repositories, "  swiftui  "))

        #expect(await source.calls.count == 1)
    }

    @Test("LRU 淘汰最久未用的那个组合")
    func evictsLeastRecentlyUsed() async throws {
        let source = ScriptedSearchSource(scripts: [
            "a": [repoPage(["a/one"], total: 1)],
            "b": [repoPage(["b/two"], total: 1)],
            "c": [repoPage(["c/three"], total: 1)]
        ])
        let loader = LoadSearch(source: source, capacity: 2)
        let first = try query(.repositories, "a")
        let second = try query(.repositories, "b")
        let third = try query(.repositories, "c")

        _ = try await loader.load(first)
        _ = try await loader.load(second)
        // 读一次 `a` ⇒ 它变成"最近使用"，于是被淘汰的应该是 `b`。
        _ = await loader.cached(first)
        _ = try await loader.load(third)

        #expect(await loader.cachedKeyCount == 2)
        #expect(await loader.cached(first) != nil, "刚读过的不该被淘汰")
        #expect(await loader.cached(second) == nil, "被淘汰的应该是更久未用的那个")
        #expect(await loader.cached(third) != nil)
    }

    @Test("容量至少是 1（传 0 或负数不该让缓存彻底失灵）")
    func capacityIsClamped() async throws {
        let source = ScriptedSearchSource(scripts: ["a": [repoPage(["a/one"], total: 1)]])
        let loader = LoadSearch(source: source, capacity: 0)

        _ = try await loader.load(try query(.repositories, "a"))

        #expect(await loader.cachedKeyCount == 1)
    }

    @Test("`invalidateAll` 清空全部组合（登出时随其余账号数据一并清理）")
    func invalidateAllClearsCache() async throws {
        let source = ScriptedSearchSource(scripts: ["a": [repoPage(["a/one"], total: 1)]])
        let loader = LoadSearch(source: source)
        let q = try query(.repositories, "a")

        _ = try await loader.load(q)
        await loader.invalidateAll()

        #expect(await loader.cachedKeyCount == 0)
        #expect(await loader.cached(q) == nil)
    }
}

/// 搜索的脚本化替身 —— 领域层测试用它，**不碰 HTTP**。
///
/// 理由同 `ScriptedRepositorySource`：这一层要断言的是业务规则（发几条、什么顺序、
/// 游标传没传下去、失败时缓存动不动），而不是"请求头带没带版本号"
/// （那由 `GitHubAPITests` 用真实 `URLProtocol` 桩件覆盖）。
private actor ScriptedSearchSource: SearchDataSource {

    struct Call: Sendable, Equatable {
        let qualifiers: String
        let scope: SearchScope
        let perPage: Int
        let cursor: URL?
    }

    /// 每条查询依次返回的页；**用完最后一页后重复它**。
    ///
    /// ⚠️ 重复而不是"耗尽后返回空页"是有意的：这样"到底了"这件事**只由该页的
    /// `nextCursor` 表达**。否则"脚本用完了"与"服务端没有下一页了"两件事混在一个表现里，
    /// 测试会以为在验证 A，其实验证的是 B。
    private var scripts: [String: [SearchHitPage]]

    private var failure: GitHubError?

    private(set) var calls: [Call] = []

    init(scripts: [String: [SearchHitPage]] = [:]) {
        self.scripts = scripts
    }

    func failWith(_ error: GitHubError) { failure = error }
    func clearFailure() { failure = nil }

    func search(_ part: SearchQueryPart, perPage: Int, cursor: URL?) async throws -> SearchHitPage {
        calls.append(Call(
            qualifiers: part.qualifiers,
            scope: part.scope,
            perPage: perPage,
            cursor: cursor
        ))

        if let failure { throw failure }

        guard var pages = scripts[part.qualifiers], !pages.isEmpty else {
            return SearchHitPage(rows: [], totalCount: 0, nextCursor: nil, incompleteResults: false)
        }
        let page = pages.count > 1 ? pages.removeFirst() : pages[0]
        scripts[part.qualifiers] = pages
        return page
    }
}
