import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 「我的 Pull Request / 我的 Issue」的查询口径（PRD §4.21、决策 #73）。
///
/// ## 这一套守的是什么
///
/// 与搜索页**有意不同**：那一页的「Issue · PR」范围必须发**两条**查询再合并
/// （决策 #47：App 用户令牌下不带 `is:issue` / `is:pull-request` 直接 422），
/// 而这一页一项**只发一条**、各是一页。两条路都"能出结果"，混了也能跑，
/// 只是屏幕上会多出一批不该在这一页出现的行。
@Suite("我的会话 · 查询口径（单条 part）")
struct MyConversationsQueryTests {

    @Test("PR 项：`author:@me is:pull-request`（两个限定符一个都不能少）")
    func pullRequestQualifiers() {
        #expect(MyConversationsQuery.qualifiers(for: .pullRequest) == "author:@me is:pull-request")
    }

    @Test("Issue 项：`author:@me is:issue`")
    func issueQualifiers() {
        #expect(MyConversationsQuery.qualifiers(for: .issue) == "author:@me is:issue")
    }

    @Test("⚠️ 每一项**只有一条** part：`is:` 恰好出现一次（混排恰恰是这一页不能有的性质）")
    func eachKindCarriesExactlyOneTypeQualifier() {
        for kind in ConversationKind.allCases {
            let qualifiers = MyConversationsQuery.qualifiers(for: kind)
            let occurrences = qualifiers.components(separatedBy: "is:").count - 1

            #expect(occurrences == 1, "每一项都应当是单条 part")
        }
    }

    @Test("⚠️ 少了 `is:` 就是 422，少了 `author:@me` 就变成「全站最近更新的 PR」")
    func bothQualifiersAreRequired() {
        for kind in ConversationKind.allCases {
            let qualifiers = MyConversationsQuery.qualifiers(for: kind)

            #expect(qualifiers.hasPrefix("author:@me "), "`@me` 只能与限定符一起用，不能单独作搜索词")
            #expect(qualifiers.contains(kind == .pullRequest ? "is:pull-request" : "is:issue"))
        }
    }

    @Test("页大小复用搜索页那个常量（上限 100，超了会被服务端**静默**夹到 100）")
    func pageSizeMatchesTheSearchPage() {
        #expect(MyConversationsQuery.pageSize == SearchQueryBuilder.pageSize)
        #expect(MyConversationsQuery.pageSize == 30)
    }

    @Test("⚠️ 排序是**独立查询参数** `sort=updated&order=desc`，不是 `q` 里的限定符")
    func sortIsAQueryParameter() {
        // 当限定符塞进 `q` 不会报错 —— 只会**安静地按相关度排**，
        // 而屏幕上看起来完全正常（列表有内容、条数也对），只有用户会发现"顺序怪"。
        #expect(MyConversationsQuery.sortParameter == "updated")
        #expect(MyConversationsQuery.sortOrder == "desc")
    }
}

/// 这一页的全部可见文案（PRD §4.21 / §7）。
@Suite("我的会话 · 文案")
struct MyConversationsCopyTests {

    @Test("⚠️ 页面标题与「我的」页那两个菜单项**逐字相同**（只留一份定义）")
    func titlesAreSharedWithTheMenu() {
        // 菜单文字与页面标题是同一个字符串 —— 两处各写一遍，
        // 早晚会出现"菜单改了、标题没改"，而两屏不会同屏出现，**看一屏永远发现不了**。
        #expect(MyConversationsCopy.title(for: .pullRequest) == ProfileCopy.menuPullRequests)
        #expect(MyConversationsCopy.title(for: .issue) == ProfileCopy.menuIssues)
        #expect(MyConversationsCopy.title(for: .pullRequest) == "我的 Pull Request")
        #expect(MyConversationsCopy.title(for: .issue) == "我的 Issue")
    }

    @Test("说明行是 `{N} 个结果`，数字**千分位**、且是服务端匹配总数")
    func resultsCountUsesTheServerTotal() {
        #expect(MyConversationsCopy.resultsCount(4) == "4 个结果")
        #expect(MyConversationsCopy.resultsCount(1_234) == "1,234 个结果")
    }

    @Test("空态两行**逐字**（PRD §7 新定，原型没有空态）")
    func emptyStateCopyIsVerbatim() {
        #expect(MyConversationsCopy.emptyTitle(for: .pullRequest) == "还没有创建过 Pull Request")
        #expect(MyConversationsCopy.emptyTitle(for: .issue) == "还没有创建过 Issue")
        #expect(
            MyConversationsCopy.emptyHint(for: .pullRequest)
                == "在任意仓库里发起一个 Pull Request，它就会出现在这里"
        )
        #expect(
            MyConversationsCopy.emptyHint(for: .issue)
                == "在任意仓库里创建一个 Issue，它就会出现在这里"
        )
    }

    @Test("⚠️ 空态第二行说的是「**你**还没有」，不是「这个仓库没有」")
    func emptyHintTalksAboutTheUserNotTheRepository() {
        // 与探索页那两处**有意不同**：那边说的是仓库的状态，这边说的是归属。
        for kind in ConversationKind.allCases {
            #expect(!MyConversationsCopy.emptyHint(for: kind).contains("仓库当前"))
        }
    }

    @Test("续页按钮与「结果可能不完整」都**复用搜索页**那一句")
    func pagingCopyComesFromTheSearchPage() {
        // 两页走**同一个** Search 桶（30 次/分钟），连措辞都不该分叉。
        #expect(MyConversationsCopy.loadMoreAction == SearchCopy.loadMoreAction)
        #expect(MyConversationsCopy.incompleteResults == SearchCopy.incompleteResults)
    }
}

/// 取数与翻页（PRD §4.21、TECH_SPEC §9.14）。
///
/// ## 这一套守的是三道闸门
///
/// 1. **到底了就不再出网**（漏了 ⇒ 每点一次「加载更多」白扣一格格配额）；
/// 2. **失败不动缓存**（动了 ⇒ 一次失败就让用户丢掉已加载的内容与续页入口）；
/// 3. **按 `id` 去重**（漏了 ⇒ `ForEach` 拿到两个相同 id、视觉上是重复行）。
@Suite("我的会话 · 取数与翻页")
struct LoadMyConversationsTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let page2 = URL(string: "https://api.github.com/search/issues?q=me&page=2")!
    private let page3 = URL(string: "https://api.github.com/search/issues?q=me&page=3")!

    private func hit(_ kind: ConversationKind, _ number: Int, title: String = "t") -> ConversationHit {
        ConversationHit(
            kind: kind,
            number: number,
            title: title,
            repoFullName: "a/one",
            state: .open,
            updatedAt: base
        )
    }

    private func page(
        _ kind: ConversationKind,
        _ numbers: [Int],
        total: Int,
        next: URL? = nil,
        incomplete: Bool = false,
        titles: [String] = []
    ) -> MyConversationHitPage {
        MyConversationHitPage(
            hits: numbers.enumerated().map { index, number in
                hit(kind, number, title: titles.indices.contains(index) ? titles[index] : "t\(number)")
            },
            totalCount: total,
            nextCursor: next,
            incompleteResults: incomplete
        )
    }

    // MARK: - 首屏

    @Test("首屏：行 / 总数 / 游标照搬，页大小固定 30")
    func firstPageIsPassedThrough() async throws {
        let source = ScriptedMyConversationsSource(scripts: [
            .pullRequest: [page(.pullRequest, [1, 2], total: 2, next: page2)]
        ])
        let loader = LoadMyConversations(source: source)

        let result = try await loader.load(.pullRequest, reset: true)

        #expect(result.hits.map(\.number) == [1, 2])
        #expect(result.totalCount == 2)
        #expect(result.nextCursor == page2)
        #expect(result.hasMore)
        #expect(!result.incomplete)
        #expect(result.notice == nil)

        let calls = await source.calls
        #expect(calls.count == 1)
        #expect(calls[0].kind == .pullRequest)
        #expect(calls[0].perPage == MyConversationsQuery.pageSize)
        #expect(calls[0].cursor == nil)
    }

    @Test("`hasMore` 由 `nextCursor` **派生**（两份状态必然会不同步）")
    func hasMoreIsDerivedFromTheCursor() async throws {
        let source = ScriptedMyConversationsSource(scripts: [
            .issue: [page(.issue, [1], total: 1)]
        ])
        let loader = LoadMyConversations(source: source)

        let result = try await loader.load(.issue, reset: true)

        #expect(result.nextCursor == nil)
        #expect(!result.hasMore)
    }

    // MARK: - 续页

    @Test("续页：**追加**而不是重排，且把上一页的游标传下去")
    func nextPageAppendsAndPassesTheCursor() async throws {
        let source = ScriptedMyConversationsSource(scripts: [
            .pullRequest: [
                page(.pullRequest, [1, 2], total: 4, next: page2),
                page(.pullRequest, [3, 4], total: 4),
            ]
        ])
        let loader = LoadMyConversations(source: source)

        _ = try await loader.load(.pullRequest, reset: true)
        let result = try await loader.load(.pullRequest)

        // 重排会把新条目插到已渲染列表的中段，用户的滚动位置会当场跳走。
        #expect(result.hits.map(\.number) == [1, 2, 3, 4])
        #expect(!result.hasMore)

        let calls = await source.calls
        #expect(calls.map(\.cursor) == [nil, page2])
    }

    @Test("⚠️ 已经到底 ⇒ 再问一次也**一发请求都不发**（这个桶只有 30 次/分钟）")
    func loadingPastTheEndStopsHittingTheNetwork() async throws {
        let source = ScriptedMyConversationsSource(scripts: [
            .issue: [page(.issue, [1], total: 1)]
        ])
        let loader = LoadMyConversations(source: source)

        _ = try await loader.load(.issue, reset: true)
        let again = try await loader.load(.issue)
        let onceMore = try await loader.load(.issue)

        #expect(again.hits.map(\.number) == [1])
        #expect(onceMore.hits.map(\.number) == [1])

        let calls = await source.calls
        #expect(calls.count == 1, "到底之后每次点击都白扣一格配额")
    }

    @Test("`reset: true` 重新从第一页开始（丢掉旧游标）")
    func resetStartsOver() async throws {
        let source = ScriptedMyConversationsSource(scripts: [
            .pullRequest: [
                page(.pullRequest, [1], total: 3, next: page2),
                page(.pullRequest, [9], total: 1),
            ]
        ])
        let loader = LoadMyConversations(source: source)

        _ = try await loader.load(.pullRequest, reset: true)
        let refreshed = try await loader.load(.pullRequest, reset: true)

        #expect(refreshed.hits.map(\.number) == [9], "刷新是**替换**，不是追加")
        #expect(refreshed.nextCursor == nil)

        let calls = await source.calls
        #expect(calls.map(\.cursor) == [nil, nil])
    }

    // MARK: - 去重

    @Test("⚠️ 按 `id` 去重，**保留先到的**（翻页期间某条被更新 ⇒ 它会从第 2 页挪到第 1 页）")
    func duplicatesAcrossPagesAreDropped() async throws {
        let source = ScriptedMyConversationsSource(scripts: [
            .pullRequest: [
                page(.pullRequest, [1, 2], total: 3, next: page2, titles: ["旧", "b"]),
                // 第 1 页那条 #1 被更新过，于是它又出现在第 2 页（内容已经变了）。
                page(.pullRequest, [1, 3], total: 3, titles: ["新", "c"]),
            ]
        ])
        let loader = LoadMyConversations(source: source)

        _ = try await loader.load(.pullRequest, reset: true)
        let result = try await loader.load(.pullRequest)

        #expect(result.hits.map(\.number) == [1, 2, 3])
        // 保留先到的那份：不让已经渲染过的行在用户眼前被换掉。
        #expect(result.hits[0].title == "旧")
    }

    // MARK: - 失败

    @Test("⚠️ 失败**不动缓存**：已加载的内容与续页入口都留在原处")
    func failureLeavesTheCacheAlone() async throws {
        let source = ScriptedMyConversationsSource(scripts: [
            .issue: [page(.issue, [1, 2], total: 4, next: page2)]
        ])
        let loader = LoadMyConversations(source: source)

        _ = try await loader.load(.issue, reset: true)
        await source.failWith(.transport(URLError(.timedOut)))

        await #expect(throws: GitHubError.self) {
            _ = try await loader.load(.issue)
        }

        let cached = try #require(await loader.cached(.issue))
        #expect(cached.hits.map(\.number) == [1, 2], "§8.5：已加载的内容必须留在屏幕上")
        #expect(cached.nextCursor == page2, "清掉游标等于一次失败就让「加载更多」永远消失")
    }

    @Test("失败之后再试一次仍然能续上（游标没被吃掉）")
    func retryAfterFailureStillContinues() async throws {
        let source = ScriptedMyConversationsSource(scripts: [
            .issue: [
                page(.issue, [1], total: 2, next: page2),
                page(.issue, [2], total: 2),
            ]
        ])
        let loader = LoadMyConversations(source: source)

        _ = try await loader.load(.issue, reset: true)
        await source.failWith(.serverError(status: 503))
        await #expect(throws: GitHubError.self) {
            _ = try await loader.load(.issue)
        }
        await source.clearFailure()

        let result = try await loader.load(.issue)
        #expect(result.hits.map(\.number) == [1, 2])
    }

    // MARK: - 两类互不干扰

    @Test("两类**各自一页**：互不共用缓存（切到「我的 Issue」不该看到 PR 那份）")
    func kindsHaveIndependentCaches() async throws {
        let source = ScriptedMyConversationsSource(scripts: [
            .pullRequest: [page(.pullRequest, [10], total: 1, next: page2)],
            .issue: [page(.issue, [20], total: 1)],
        ])
        let loader = LoadMyConversations(source: source)

        let pullRequests = try await loader.load(.pullRequest, reset: true)
        let issues = try await loader.load(.issue, reset: true)

        #expect(pullRequests.hits.map(\.number) == [10])
        #expect(issues.hits.map(\.number) == [20])
        #expect(await loader.cachedKindCount == 2)

        let calls = await source.calls
        #expect(calls.map(\.kind) == [.pullRequest, .issue])
    }

    @Test("`invalidateAll` 清空（登出时随其余账号数据一并清理 —— 否则换账号会看到上一个人的列表）")
    func invalidateAllClearsBothKinds() async throws {
        let source = ScriptedMyConversationsSource(scripts: [
            .pullRequest: [page(.pullRequest, [1], total: 1)],
            .issue: [page(.issue, [2], total: 1)],
        ])
        let loader = LoadMyConversations(source: source)

        _ = try await loader.load(.pullRequest, reset: true)
        _ = try await loader.load(.issue, reset: true)
        await loader.invalidateAll()

        #expect(await loader.cachedKindCount == 0)
        #expect(await loader.cached(.pullRequest) == nil)
        #expect(await loader.cached(.issue) == nil)
    }

    // MARK: - `incomplete_results`

    @Test("不完整是**累计**的：只要有一页报过，这份列表就谈不上完整")
    func incompleteAccumulates() async throws {
        let source = ScriptedMyConversationsSource(scripts: [
            .pullRequest: [
                page(.pullRequest, [1], total: 2, next: page2, incomplete: true),
                page(.pullRequest, [2], total: 2),
            ]
        ])
        let loader = LoadMyConversations(source: source)

        let first = try await loader.load(.pullRequest, reset: true)
        #expect(first.notice == MyConversationsCopy.incompleteResults)

        let second = try await loader.load(.pullRequest)
        #expect(second.incomplete)
        #expect(second.notice == MyConversationsCopy.incompleteResults)

        // `reset` 之后再从干净的一页开始 ⇒ 说明该忘。
        _ = try await loader.load(.pullRequest, reset: true)
        let refreshed = try #require(await loader.cached(.pullRequest))
        #expect(!refreshed.incomplete)
        #expect(refreshed.notice == nil)
    }

    @Test("`notice` 只说「结果可能不完整」，**不是错误态**（照常渲染已拿到的条目）")
    func incompleteIsNotAnErrorState() async throws {
        let source = ScriptedMyConversationsSource(scripts: [
            .issue: [page(.issue, [1, 2], total: 99, incomplete: true)]
        ])
        let loader = LoadMyConversations(source: source)

        let result = try await loader.load(.issue, reset: true)

        #expect(result.hits.count == 2)
        #expect(result.totalCount == 99)
        #expect(!result.isEmpty)
    }

    @Test("空结果 ⇒ `isEmpty`（界面据此画空态两行，而不是一片空白）")
    func emptyResultReportsEmpty() async throws {
        let source = ScriptedMyConversationsSource(scripts: [.issue: [page(.issue, [], total: 0)]])
        let loader = LoadMyConversations(source: source)

        let result = try await loader.load(.issue, reset: true)

        #expect(result.isEmpty)
        #expect(result.hits.isEmpty)
        #expect(result.notice == nil)
    }
}

// MARK: - 替身

/// 「我的会话」取数的脚本化替身 —— 领域层测试用它，**不碰 HTTP**。
///
/// 理由同 `ScriptedRepositorySource` / `ScriptedSearchSource`：这一层要断言的是
/// 业务规则（发几次、游标传没传下去、失败时缓存动不动），而不是查询串怎么拼
/// （那由 `GitHubAPITests` 用真实 `URLProtocol` 桩件覆盖）。
private actor ScriptedMyConversationsSource: MyConversationsDataSource {

    struct Call: Sendable, Equatable {
        let kind: ConversationKind
        let perPage: Int
        let cursor: URL?
    }

    /// 每一类依次返回的页；**用完最后一页后重复它**。
    ///
    /// ⚠️ 重复而不是"耗尽后返回空页"：这样"到底了"这件事**只由该页的 `nextCursor`
    /// 表达**。否则"脚本用完了"与"服务端没有下一页了"混在同一个表现里，
    /// 测试会以为在验证 A，其实验证的是 B（同 `ScriptedSearchSource`）。
    private var scripts: [ConversationKind: [MyConversationHitPage]]

    private var failure: GitHubError?

    private(set) var calls: [Call] = []

    init(scripts: [ConversationKind: [MyConversationHitPage]] = [:]) {
        self.scripts = scripts
    }

    func failWith(_ error: GitHubError) { failure = error }
    func clearFailure() { failure = nil }

    func search(
        kind: ConversationKind,
        perPage: Int,
        cursor: URL?
    ) async throws -> MyConversationHitPage {
        calls.append(Call(kind: kind, perPage: perPage, cursor: cursor))

        if let failure { throw failure }

        guard var pages = scripts[kind], !pages.isEmpty else {
            return MyConversationHitPage(
                hits: [], totalCount: 0, nextCursor: nil, incompleteResults: false
            )
        }
        let page = pages.count > 1 ? pages.removeFirst() : pages[0]
        scripts[kind] = pages
        return page
    }
}
