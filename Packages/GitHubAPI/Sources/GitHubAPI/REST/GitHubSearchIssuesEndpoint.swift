import Foundation

/// 会话（Issue / PR）搜索 —— `GET /search/issues`（TECH_SPEC §4.6.2、§9.2、
/// PRD §4.2、**决策 #47**）。
///
/// ## ⚠️ 它必须带 `is:issue` 或 `is:pull-request`，否则直接 422
///
/// 官方原文（`docs.github.com/rest/search/search`，多版本一致）：
///
/// > For requests made by **GitHub Apps with a user access token**, you can't retrieve a
/// > combination of issues and pull requests in a single query. Requests that don't include
/// > the `is:issue` or `is:pull-request` qualifier will receive an **HTTP 422**.
/// > To get results for both, you must **send separate queries**.
///
/// 本项目用的正是 App 用户令牌（`ghu_`）⇒ **一次只能问一类**。
/// 所以本端点的调用方要发**两次**（`… is:issue` 与 `… is:pull-request`），
/// 那件事由领域层做（`SearchQueryBuilder.parts`，把两条查询交给 `LoadSearch` 分发），
/// 本类型**只负责把给它的那一条发出去**。
///
/// ⚠️ **那道门槛不在这里再拦一遍**：它属于"查询怎么拼"的领域规则，
/// 已有唯一实现与单测（`SearchQueryBuilder`）。在这一层再用子串判断写一份，
/// 等于同一条规则有了两处实现，而且子串那份更弱（引号里的 `is:issue` 也会被算中）。
///
/// ## 配额
///
/// 与其余搜索范围共用 `search` 桶（30/分钟）。因为要发两条，**每翻一页消耗 2 格**
/// —— 这是决策 #47 明写的代价。
public struct GitHubSearchIssuesEndpoint: Sendable {

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    /// 搜一页会话（Issue **或** PR —— 由 `query` 里的 `is:` 限定符决定）。
    ///
    /// - Parameter query: 完整的 `q=`，**必须含 `is:issue` 或 `is:pull-request`**
    ///   （理由见类型说明）。
    /// - Parameter cursor: 上一页的 `nextCursor`（**完整 URL**）；`nil` 取第一页。
    public func search(
        query: String,
        perPage: Int = 30,
        cursor: URL? = nil
    ) async throws -> SearchResult<SearchConversationDTO> {
        let query = try SearchEndpointSupport.validatedQuery(query)

        let response: HTTPResponse
        if let cursor {
            response = try await client.send(.get(cursor, rateLimitResource: .search))
        } else {
            response = try await client.send(
                .get(
                    client.url(
                        "search/issues",
                        query: SearchEndpointSupport.queryItems(query: query, perPage: perPage)
                    ),
                    rateLimitResource: .search
                )
            )
        }

        return try SearchResult<SearchConversationDTO>.decoded(from: response)
    }
}
