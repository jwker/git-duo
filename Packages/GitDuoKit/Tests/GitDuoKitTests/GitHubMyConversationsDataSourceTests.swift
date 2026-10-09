import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 我的会话列表的**生产实现**（切片 9.2、PRD §4.21、决策 #73）。
///
/// ## 这一套守的是三件"漏了不报错"的事
///
/// 1. **限定符按 `kind` 选对** —— 选错的表现不是错误，而是"这一页列的是另一类东西"；
/// 2. **`sort=updated&order=desc` 带上了** —— 漏了只会安静地按相关度排
///    （列表有内容、条数也对，只有用户会发现"顺序怪"）；
/// 3. **四个字段原样带出去** —— 丢一个的症状分别是：结果标题永远 `0 个结果`、
///    翻不了页、"结果不完整"永不提示。
///
/// 它们都**不是**"服务端会报错"的那类问题，所以只能在这里钉。
/// 收的是接缝协议（`ConversationSearchEndpoint`）而不是具体端点 ⇒ 全程不碰 HTTP。
@Suite("GitHubMyConversationsDataSource · 限定符 / 排序 / 四个字段")
struct GitHubMyConversationsDataSourceTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let next = URL(string: "https://api.github.com/search/issues?q=me&page=2")!

    /// 一条会话行（`pull_request` 标记的存在性 = 这是一条 PR，见 `SearchConversationDTO`）。
    private func item(
        number: Int = 42,
        state: String = "open",
        title: String = "t",
        mergedAt: Date? = nil,
        isPullRequest: Bool = false
    ) -> SearchConversationDTO {
        SearchConversationDTO(
            number: number,
            title: title,
            state: state,
            updatedAt: base,
            repositoryURL: URL(string: "https://api.github.com/repos/my-git/gitduo")!,
            pullRequest: isPullRequest
                ? SearchConversationDTO.PullRequestMarker(mergedAt: mergedAt)
                : nil
        )
    }

    // MARK: - 限定符与排序

    @Test("⚠️ PR 项：`author:@me is:pull-request` + `sort=updated&order=desc`")
    func pullRequestCarriesQualifiersAndSort() async throws {
        let endpoint = ScriptedConversationEndpoint()
        let source = GitHubMyConversationsDataSource(endpoint: endpoint)

        _ = try await source.search(kind: .pullRequest, perPage: 30, cursor: nil)

        let call = try #require(await endpoint.calls.first)
        #expect(call.query == MyConversationsQuery.qualifiers(for: .pullRequest))
        #expect(call.query == "author:@me is:pull-request")
        // 排序**必须**显式带 —— 漏了不报错，只会按相关度排（PRD §4.21 把它写成了口径）。
        #expect(call.sort == "updated")
        #expect(call.order == "desc")
        #expect(call.perPage == 30)
        #expect(call.cursor == nil)
    }

    @Test("Issue 项：`author:@me is:issue`（两类**各发一条**，不混排 —— 决策 #73）")
    func issueCarriesItsOwnQualifier() async throws {
        let endpoint = ScriptedConversationEndpoint()
        let source = GitHubMyConversationsDataSource(endpoint: endpoint)

        _ = try await source.search(kind: .issue, perPage: 30, cursor: nil)

        let call = try #require(await endpoint.calls.first)
        #expect(call.query == "author:@me is:issue")
        #expect(await endpoint.calls.count == 1, "单条 part ⇒ 一次请求，而不是搜索页那样两条")
    }

    @Test("续页把游标原样传下去（`nextCursor` 是服务端给的完整 URL）")
    func passesTheCursor() async throws {
        let endpoint = ScriptedConversationEndpoint()
        let source = GitHubMyConversationsDataSource(endpoint: endpoint)

        _ = try await source.search(kind: .pullRequest, perPage: 10, cursor: next)

        let call = try #require(await endpoint.calls.first)
        #expect(call.cursor == next)
        #expect(call.perPage == 10, "页大小由调用方给（`LoadMyConversations` 传 30）")
    }

    // MARK: - 四个字段

    @Test("⚠️ 四个字段逐个原样带出：行 / 总数 / 游标 / 不完整标记")
    func passesAllFourFieldsThrough() async throws {
        let endpoint = ScriptedConversationEndpoint(pages: [
            SearchResult(
                items: [item(number: 1), item(number: 2)],
                totalCount: 15,
                nextCursor: next,
                incompleteResults: true
            )
        ])
        let source = GitHubMyConversationsDataSource(endpoint: endpoint)

        let page = try await source.search(kind: .pullRequest, perPage: 30, cursor: nil)

        #expect(page.hits.map(\.number) == [1, 2])
        // ⚠️ 是服务端匹配总数，不是这一页的条数 —— 说明行里的 `{N} 个结果` 要用它。
        #expect(page.totalCount == 15)
        #expect(page.nextCursor == next)
        #expect(page.incompleteResults)
    }

    @Test("空结果照常（`totalCount` 保留，视图据此画空态而不是一片空白）")
    func emptyResultIsPassedThrough() async throws {
        let endpoint = ScriptedConversationEndpoint(pages: [
            SearchResult(items: [], totalCount: 0, nextCursor: nil, incompleteResults: false)
        ])
        let source = GitHubMyConversationsDataSource(endpoint: endpoint)

        let page = try await source.search(kind: .issue, perPage: 30, cursor: nil)

        #expect(page.hits.isEmpty)
        #expect(page.totalCount == 0)
        #expect(!page.incompleteResults)
    }

    // MARK: - 行映射**复用搜索页**的

    @Test("⚠️ 行模型复用搜索页那一份：PR 的 `merged_at` ⇒ `.merged`（两个页面不可能分叉）")
    func reusesTheSearchRowMapper() async throws {
        // 决策 #73 的「结果行复用」：状态胶囊、状态图标、点击去向在搜索页与这一页
        // 必须是**同一套**。各写一份必然分叉（"合并"的图标在一处带箭头、另一处不带）。
        let endpoint = ScriptedConversationEndpoint(pages: [
            SearchResult(
                items: [
                    SearchConversationDTO(
                        number: 7,
                        title: "修一个 bug",
                        state: "closed",
                        updatedAt: base,
                        repositoryURL: URL(string: "https://api.github.com/repos/my-git/gitduo")!,
                        pullRequest: SearchConversationDTO.PullRequestMarker(mergedAt: base)
                    )
                ],
                totalCount: 1, nextCursor: nil, incompleteResults: false
            )
        ])
        let source = GitHubMyConversationsDataSource(endpoint: endpoint)

        let page = try await source.search(kind: .pullRequest, perPage: 30, cursor: nil)

        let hit = try #require(page.hits.first)
        #expect(hit.kind == .pullRequest)
        #expect(hit.repoFullName == "my-git/gitduo", "`repository_url` 的解析只有一处实现")
        // `state == closed` 且 `merged_at` 有值 ⇒ 已合并（无独立 merged 状态，本地判定）。
        #expect(hit.state == .merged)
    }

    @Test("Issue 的 `closed` ⇒ `.closed`（不是红族的「已关闭 PR」那一支）")
    func closedIssueMapsToClosed() async throws {
        let endpoint = ScriptedConversationEndpoint(pages: [
            SearchResult(
                items: [item(number: 9, state: "closed")],
                totalCount: 1, nextCursor: nil, incompleteResults: false
            )
        ])
        let source = GitHubMyConversationsDataSource(endpoint: endpoint)

        let page = try await source.search(kind: .issue, perPage: 30, cursor: nil)

        let hit = try #require(page.hits.first)
        #expect(hit.kind == .issue)
        #expect(hit.state == .closed)
        #expect(hit.statusTone == .completed, "Issue 关了是紫族；红族是「关闭且未合并的 PR」")
    }

    // MARK: - 失败

    @Test("失败**原样抛**（不折叠、也不吞）—— 调用方据此给失败态 + 重试")
    func failureIsPropagated() async throws {
        let endpoint = ScriptedConversationEndpoint(failure: .rateLimited(resetAt: base, isSecondary: false))
        let source = GitHubMyConversationsDataSource(endpoint: endpoint)

        await #expect(throws: GitHubError.rateLimited(resetAt: base, isSecondary: false)) {
            _ = try await source.search(kind: .pullRequest, perPage: 30, cursor: nil)
        }
    }
}

// MARK: - 替身

/// 会话搜索接缝的脚本化替身 —— 领域层测试用它，**不碰 HTTP**。
///
/// 理由同 `ScriptedRepositorySource` / `ScriptedSearchSource`：这一层要断言的是
/// "限定符与排序带对了没"，而不是请求怎么编码（那由 `GitHubAPITests` 用真实
/// `URLProtocol` 桩件覆盖）。
private actor ScriptedConversationEndpoint: ConversationSearchEndpoint {

    struct Call: Sendable, Equatable {
        let query: String
        let perPage: Int
        let cursor: URL?
        let sort: String?
        let order: String
    }

    /// 依次返回的页；**用完最后一页后重复它**（"到底了"只由该页的 `nextCursor` 表达）。
    private var pages: [SearchResult<SearchConversationDTO>]

    private let failure: GitHubError?

    private(set) var calls: [Call] = []

    init(
        pages: [SearchResult<SearchConversationDTO>] = [],
        failure: GitHubError? = nil
    ) {
        self.pages = pages
        self.failure = failure
    }

    func search(
        query: String,
        perPage: Int,
        cursor: URL?,
        sort: String?,
        order: String
    ) async throws -> SearchResult<SearchConversationDTO> {
        calls.append(Call(query: query, perPage: perPage, cursor: cursor, sort: sort, order: order))

        if let failure { throw failure }

        guard !pages.isEmpty else {
            return SearchResult(items: [], totalCount: 0, nextCursor: nil, incompleteResults: false)
        }
        return pages.count > 1 ? pages.removeFirst() : pages[0]
    }
}
