import Foundation

/// 用户搜索 —— `GET /search/users`（TECH_SPEC §4.6.1、§9.2、PRD §4.2）。
///
/// ## 它消耗的是**独立且最紧**的那一档配额
///
/// `search` 桶 **30 次/分钟**，与 `core`（5,000/小时）完全分开计，且与探索榜、
/// 搜索页其余三个范围**共用同一个桶**（§4.5、§13.2）。所以每一次出网都显式声明
/// `rateLimitResource: .search` —— 漏了**不会报错**，只会让闸门按"没有限额"放行。
///
/// ## 它**不**排序
///
/// 用户搜索支持 `sort=followers|repositories|joined`，但 PRD §4.2 没有规定排序，
/// 而相关性（服务端 best match）是唯一"不需要我们替用户猜"的那个 ⇒ 一个参数都不带。
public struct GitHubSearchUsersEndpoint: Sendable {

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session —— 理由同
    /// `GitHubSearchRepositoriesEndpoint`：所有端点必须共用同一个 `GitHubRESTClient`，
    /// 否则缓存会分成两份、配额各算各的（而它不会报错）。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    /// 搜一页用户。
    ///
    /// - Parameter cursor: 上一页的 `nextCursor`（**完整 URL**）；`nil` 取第一页。
    ///   续页原样用它 —— 自己拼 `?page=n` 会漏掉服务端带的其它参数（§4.4）。
    public func search(
        query: String,
        perPage: Int = 30,
        cursor: URL? = nil
    ) async throws -> SearchResult<SearchUserDTO> {
        let query = try SearchEndpointSupport.validatedQuery(query)

        let response: HTTPResponse
        if let cursor {
            response = try await client.send(.get(cursor, rateLimitResource: .search))
        } else {
            response = try await client.send(
                .get(
                    client.url(
                        "search/users",
                        query: SearchEndpointSupport.queryItems(query: query, perPage: perPage)
                    ),
                    rateLimitResource: .search
                )
            )
        }

        return try SearchResult<SearchUserDTO>.decoded(from: response)
    }
}
