import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// `GitHubSearchDataSource` —— 把「一条 part」变成「一页行」的适配器（切片 5.2）。
///
/// 本套件盯三件事：
/// 1. **按 `part.scope` 分发到四个端点** —— 漏了不报错：拿 `is:issue` 的 q 去问
///    `/search/users` 只会返回空结果，屏幕上表现为"这个范围永远搜不到东西"；
/// 2. **三个字段原样带出**（`totalCount` / 游标 / `incomplete_results`）——
///    它们分别决定结果标题的 N、「加载更多」还在不在、"结果不完整"的提示；
/// 3. 行级映射抛出的错误**穿透适配器**（那一整页就没有"半页可用"的说法）。
@Suite("GitHubSearchDataSource · 分发与拼页")
struct GitHubSearchDataSourceTests {

    // MARK: - 替身

    /// 记录每个端点被调几次、各自返回什么。四个方法各自独立计数 ——
    /// 断言"该调的调了、**不该调的一次都没调**"就靠它。
    private final class ScriptedEndpoints: SearchEndpoints, @unchecked Sendable {

        struct Call: Equatable {
            let query: String
            let perPage: Int
            let cursor: URL?
        }

        private let lock = NSLock()
        private var callsByKey: [String: [Call]] = [:]
        var failures: [String: Error] = [:]

        var repositoriesResult: SearchResult<SearchRepositoryDTO>?
        var usersResult: SearchResult<SearchUserDTO>?
        var codeResult: SearchResult<SearchCodeDTO>?
        var conversationsResult: SearchResult<SearchConversationDTO>?

        func calls(_ key: String) -> [Call] {
            lock.lock(); defer { lock.unlock() }
            return callsByKey[key] ?? []
        }

        private func record(_ key: String, _ call: Call) {
            lock.lock(); defer { lock.unlock() }
            callsByKey[key, default: []].append(call)
        }

        private func answer<T>(_ key: String, _ fallback: T) throws -> T {
            if let failure = failures[key] { throw failure }
            return fallback
        }

        func searchRepositories(
            query: String, perPage: Int, cursor: URL?
        ) async throws -> SearchResult<SearchRepositoryDTO> {
            record("repos", Call(query: query, perPage: perPage, cursor: cursor))
            return try answer("repos", repositoriesResult ?? SearchResult(
                items: [], totalCount: 0, nextCursor: nil, incompleteResults: false
            ))
        }

        func searchUsers(
            query: String, perPage: Int, cursor: URL?
        ) async throws -> SearchResult<SearchUserDTO> {
            record("users", Call(query: query, perPage: perPage, cursor: cursor))
            return try answer("users", usersResult ?? SearchResult(
                items: [], totalCount: 0, nextCursor: nil, incompleteResults: false
            ))
        }

        func searchCode(
            query: String, perPage: Int, cursor: URL?
        ) async throws -> SearchResult<SearchCodeDTO> {
            record("code", Call(query: query, perPage: perPage, cursor: cursor))
            return try answer("code", codeResult ?? SearchResult(
                items: [], totalCount: 0, nextCursor: nil, incompleteResults: false
            ))
        }

        func searchConversations(
            query: String, perPage: Int, cursor: URL?
        ) async throws -> SearchResult<SearchConversationDTO> {
            record("issues", Call(query: query, perPage: perPage, cursor: cursor))
            return try answer("issues", conversationsResult ?? SearchResult(
                items: [], totalCount: 0, nextCursor: nil, incompleteResults: false
            ))
        }
    }

    private let now = Date(timeIntervalSince1970: 1_759_833_600)

    // MARK: - 分发（本套件存在的核心理由）

    @Test("⚠️ 四个范围各打各的端点：该调的调了，**其余三个一次都没调**", arguments: [
        (SearchScope.repositories, "repos"),
        (SearchScope.users, "users"),
        (SearchScope.code, "code"),
        (SearchScope.issues, "issues"),
    ])
    func dispatchesByScope(scope: SearchScope, key: String) async throws {
        let endpoints = ScriptedEndpoints()
        let source = GitHubSearchDataSource(endpoints: endpoints)

        _ = try await source.search(
            SearchQueryPart(scope: scope, qualifiers: "swiftui"),
            perPage: 30,
            cursor: nil
        )

        #expect(endpoints.calls(key).count == 1)
        for other in ["repos", "users", "code", "issues"] where other != key {
            #expect(endpoints.calls(other).isEmpty, "\(scope) 不该打到 \(other)")
        }
    }

    @Test("q / perPage / cursor 原样传给端点（游标是服务端给的完整 URL）")
    func passesArgumentsVerbatim() async throws {
        let endpoints = ScriptedEndpoints()
        let cursor = URL(string: "https://api.github.com/search/users?q=a&page=2")!

        _ = try await GitHubSearchDataSource(endpoints: endpoints).search(
            SearchQueryPart(scope: .users, qualifiers: "登录"),
            perPage: 17,
            cursor: cursor
        )

        #expect(endpoints.calls("users") == [
            .init(query: "登录", perPage: 17, cursor: cursor)
        ])
    }

    // MARK: - 拼页：三个字段一个都不能少

    @Test("拼页：totalCount / nextCursor / incompleteResults 原样带出")
    func carriesEnvelopeFields() async throws {
        let endpoints = ScriptedEndpoints()
        endpoints.repositoriesResult = SearchResult(
            items: [
                SearchRepositoryDTO(
                    fullName: "a/one", description: nil, language: "Swift",
                    starCount: 5, createdAt: now
                ),
            ],
            totalCount: 1234,
            nextCursor: URL(string: "https://api.github.com/search/repositories?q=x&page=2"),
            incompleteResults: true
        )

        let page = try await GitHubSearchDataSource(endpoints: endpoints).search(
            SearchQueryPart(scope: .repositories, qualifiers: "swiftui"),
            perPage: 30,
            cursor: nil
        )

        #expect(page.rows.count == 1)
        #expect(page.totalCount == 1234, "结果标题里的 N（决策 #44）")
        #expect(page.nextCursor != nil, "「加载更多」的入口")
        #expect(page.incompleteResults, "「这一页少了东西」的唯一信号")
        guard case let .repository(hit) = page.rows[0] else {
            Issue.record("仓库范围应映射成仓库行")
            return
        }
        #expect(hit.fullName == "a/one")
    }

    // MARK: - 错误穿透

    @Test("⚠️ 行级映射失败 ⇒ 穿透适配器（repository_url 形状不对就是整页作废）")
    func mapperErrorPropagates() async {
        let endpoints = ScriptedEndpoints()
        endpoints.conversationsResult = SearchResult(
            items: [
                SearchConversationDTO(
                    number: 1, title: "t", state: "open", updatedAt: now,
                    repositoryURL: URL(string: "https://api.github.com/not/repos/x")!
                ),
            ],
            totalCount: 1, nextCursor: nil, incompleteResults: false
        )

        await #expect(throws: RepositoryMappingError.self) {
            _ = try await GitHubSearchDataSource(endpoints: endpoints).search(
                SearchQueryPart(scope: .issues, qualifiers: "登录 is:issue"),
                perPage: 30,
                cursor: nil
            )
        }
    }

    @Test("端点抛的网络错误原样穿透（适配器不吞、不改写结论）")
    func endpointErrorPropagates() async {
        let endpoints = ScriptedEndpoints()
        endpoints.failures["code"] = GitHubError.serverError(status: 502)

        await #expect(throws: GitHubError.self) {
            _ = try await GitHubSearchDataSource(endpoints: endpoints).search(
                SearchQueryPart(scope: .code, qualifiers: "swiftui"),
                perPage: 30,
                cursor: nil
            )
        }
    }
}
