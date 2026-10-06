import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 取数动作 + 展示层分段过滤（TECH_SPEC §9.3）。
@Suite("LoadRepositoriesPage · 取数 / 分段展示")
struct LoadRepositoriesPageTests {

    private let cursor2 = URL(string: "https://api.github.com/user/repos?page=2")!

    /// 一份混合数据：可写的公开、可写的私有、只读的公开（他人仓库）。
    private var mixed: [RepositoryDTO] {
        [
            Fixtures.dto("my-git/gitduo", isPrivate: false, push: true),
            Fixtures.dto("my-git/notes", isPrivate: true, push: true),
            Fixtures.dto("rust-lang/rust", isPrivate: false, push: false)
        ]
    }

    private func makeLoader(_ source: ScriptedRepositorySource) -> LoadRepositoriesPage {
        LoadRepositoriesPage(source: source)
    }

    // MARK: - 取数

    @Test("取数**不过滤**：一页拿走全部条目（过滤在展示层做，见下方「切段不丢数据」）")
    func loadDoesNotFilter() async throws {
        let source = ScriptedRepositorySource(repos: [Fixtures.page(mixed)])

        let page = try await makeLoader(source).load(source: .repos)

        #expect(page.items.map(\.fullName) == ["my-git/gitduo", "my-git/notes", "rust-lang/rust"])
        #expect(page.items.map(\.canWrite) == [true, true, false])
    }

    @Test("`.starred` 走 `user/starred`，且**不碰** `user/repos`（另一份数据源）")
    func starredUsesStarredSource() async throws {
        let source = ScriptedRepositorySource(
            repos: [Fixtures.page(mixed)],
            starred: [Fixtures.page([Fixtures.dto("vercel/next.js", push: false)])]
        )

        let page = try await makeLoader(source).load(source: .starred)

        #expect(page.items.map(\.fullName) == ["vercel/next.js"])
        #expect(await source.starredCursors.count == 1)
        #expect(await source.reposCursors.isEmpty, "Starred 段不该去打 user/repos")
    }

    @Test("`.repos` 走 `user/repos`，且**不碰** `user/starred`")
    func reposUsesReposSource() async throws {
        let source = ScriptedRepositorySource(
            repos: [Fixtures.page(mixed)],
            starred: [Fixtures.page([])]
        )

        _ = try await makeLoader(source).load(source: .repos)

        #expect(await source.reposCursors.count == 1)
        #expect(await source.starredCursors.isEmpty)
    }

    @Test("续页：把上一页的 nextCursor **原样**交给数据源")
    func passesCursorThrough() async throws {
        let source = ScriptedRepositorySource(repos: [Fixtures.page([], next: cursor2.absoluteString)])

        _ = try await makeLoader(source).load(source: .repos, cursor: cursor2)

        #expect(await source.reposCursors == [cursor2])
    }

    @Test("`nextCursor` 原样带出（映射不许顺手把它吃掉）")
    func keepsCursor() async throws {
        let source = ScriptedRepositorySource(
            repos: [Fixtures.page(mixed, next: cursor2.absoluteString)]
        )

        let page = try await makeLoader(source).load(source: .repos)

        #expect(page.nextCursor == cursor2)
        #expect(page.hasMore)
    }

    // MARK: - 错误传递

    @Test("映射失败原样抛出（不吞掉、不跳过那一条）")
    func mappingFailurePropagates() async {
        let source = ScriptedRepositorySource(repos: [Fixtures.page([Fixtures.dto("broken")])])

        await #expect(throws: RepositoryMappingError.malformedFullName("broken")) {
            _ = try await makeLoader(source).load(source: .repos)
        }
    }

    @Test("网络层错误原样上抛（限流 / 5xx / 断网由上层决定怎么显示）")
    func networkFailurePropagates() async {
        let resetAt = Date(timeIntervalSince1970: 1_700_000_000)
        let source = ScriptedRepositorySource()
        await source.failWith(.rateLimited(resetAt: resetAt, isSecondary: false))

        await #expect(throws: GitHubError.rateLimited(resetAt: resetAt, isSecondary: false)) {
            _ = try await makeLoader(source).load(source: .repos)
        }
    }

    // MARK: - ★ 分段切换不重新请求，也不丢数据

    @Test("★ 在「私有」段加载的下一页，其公开仓库**必须**在切回「全部」后还在")
    func segmentSwitchNeverDropsData() async throws {
        let page1 = Fixtures.page([Fixtures.dto("my-git/notes", isPrivate: true, push: true)], next: cursor2.absoluteString)
        let page2 = Fixtures.page([Fixtures.dto("my-git/gitduo", isPrivate: false, push: true)])
        let source = ScriptedRepositorySource(repos: [page1, page2])
        let loader = makeLoader(source)

        var state = PagedListState<Repository>()

        // 首屏（「全部」段）
        state.beginLoad(reset: false)
        state.received(try await loader.load(source: .repos))

        // 切到「私有」段（**不重新请求**，只是换个过滤条件）—— 此时只有 1 条可见
        #expect(state.visibleItems(segment: .privateOnly).map(\.fullName) == ["my-git/notes"])

        // 在「私有」段点「加载更多」
        state.beginLoad(reset: false)
        state.received(try await loader.load(source: .repos, cursor: cursor2))

        // 切回「全部」—— 第 2 页里的公开仓库必须还在
        #expect(
            state.visibleItems(segment: .all).map(\.fullName) == ["my-git/notes", "my-git/gitduo"],
            "取数时就按段过滤的话，这里会少一条，而且界面上没有任何迹象"
        )
        #expect(state.visibleItems(segment: .privateOnly).map(\.fullName) == ["my-git/notes"])
    }

    @Test("★ 切段**不产生请求**：三次切换后数据源只被调用过一次")
    func segmentSwitchDoesNotRefetch() async throws {
        let source = ScriptedRepositorySource(repos: [Fixtures.page(mixed)])
        var state = PagedListState<Repository>()
        state.beginLoad(reset: false)
        state.received(try await makeLoader(source).load(source: .repos))

        for segment in RepoListSegment.allCases {
            _ = state.visibleItems(segment: segment)
            _ = state.content(segment: segment)
        }

        #expect(await source.reposCursors.count == 1)
        #expect(await source.starredCursors.isEmpty)
    }

    // MARK: - 展示层过滤

    @Test(
        "逐段可见条目",
        arguments: [
            (RepoListSegment.all, 3),
            (RepoListSegment.publicOnly, 2),
            (RepoListSegment.privateOnly, 1),
            (RepoListSegment.starred, 3)
        ]
    )
    func visibleItemsPerSegment(_ segment: RepoListSegment, _ expectedCount: Int) async throws {
        let source = ScriptedRepositorySource(repos: [Fixtures.page(mixed)])
        var state = PagedListState<Repository>()
        state.beginLoad(reset: false)
        state.received(try await makeLoader(source).load(source: .repos))

        #expect(state.visibleItems(segment: segment).count == expectedCount)
    }

    @Test("⚠️ 整页在「私有」段下无匹配、但还有下一页 ⇒ `.needsMore`，不是「还没有私有仓库」")
    func filteredEmptyButMoreIsNeedsMore() async throws {
        let source = ScriptedRepositorySource(
            repos: [Fixtures.page([Fixtures.dto("rust-lang/rust", isPrivate: false, push: false)], next: cursor2.absoluteString)]
        )
        var state = PagedListState<Repository>()
        state.beginLoad(reset: false)
        state.received(try await makeLoader(source).load(source: .repos))

        #expect(state.visibleItems(segment: .privateOnly).isEmpty)
        #expect(state.content(segment: .privateOnly) == .needsMore)
        #expect(
            state.content(segment: .publicOnly) == .items,
            "同一份数据在另一段里有内容 —— 空态是**分段**的属性，不是列表的属性"
        )
    }

    @Test("整页无匹配、且已到底 ⇒ `.empty`（此时才可以说「还没有私有仓库」）")
    func filteredEmptyAtEndIsEmpty() async throws {
        let source = ScriptedRepositorySource(
            repos: [Fixtures.page([Fixtures.dto("rust-lang/rust", isPrivate: false, push: false)])]
        )
        var state = PagedListState<Repository>()
        state.beginLoad(reset: false)
        state.received(try await makeLoader(source).load(source: .repos))

        #expect(state.content(segment: .privateOnly) == .empty)
    }
}
