import Foundation

/// 代码搜索 —— `GET /search/code`（TECH_SPEC §4.6.1、§9.2、PRD §4.2）。
///
/// ## ⚠️ 它是四个范围里最贵的一个
///
/// 配额约 **10 次/分钟**（官方有 9 与 10 两种说法，本项目按 §4.5 保守取 9 ⇒ 6.7 秒一次），
/// 且限流器对它是**串行 + 间隔**（`RateLimiter.Bucket.codeSearch.requiresSerialization`），
/// 所以 `rateLimitResource: .codeSearch` **一个都不能漏**。
///
/// ## 它要一个特殊的 `Accept`
///
/// `Accept: application/vnd.github.text-match+json` 才会在结果里带上 `text_matches`
/// （命中的那几行原文）。不带也照样 200，只是没有预览行 ——
/// 所以那个头是**功能开关**，不是协商：漏了不会报错，只是结果行永远少一行。
///
/// ## ⚠️ 门槛不在这一层
///
/// 代码搜索**必须含至少一个检索词**（`language:go` 不合法），违反时服务端回 422 而
/// **那次失败照样扣配额**。拦它的是领域层的 `SearchQueryBuilder.hasBareTerm`
/// （决策 #48），本类型只做"关键词不能为空"那道兜底 —— 两处判据不同，都有单测。
public struct GitHubSearchCodeEndpoint: Sendable {

    /// 拿到 `text_matches` 的唯一办法（见类型说明）。
    ///
    /// 它**覆盖** transport 的默认 `Accept`（`application/vnd.github+json`）——
    /// 两者不会同时生效，所以不必担心"两个 Accept"。
    static let textMatchAccept = "application/vnd.github.text-match+json"

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    /// 搜一页代码。
    ///
    /// - Parameter cursor: 上一页的 `nextCursor`（**完整 URL**）；`nil` 取第一页。
    ///   ⚠️ 续页**同样要带那个 `Accept`**：漏了的话第一页有预览、后面几页全没有，
    ///   而这种"前 30 条正常、之后的都不正常"最容易被当成服务端的问题。
    public func search(
        query: String,
        perPage: Int = 30,
        cursor: URL? = nil
    ) async throws -> SearchResult<SearchCodeDTO> {
        let query = try SearchEndpointSupport.validatedQuery(query)
        let headers = ["Accept": Self.textMatchAccept]

        let response: HTTPResponse
        if let cursor {
            response = try await client.send(
                .get(cursor, headers: headers, rateLimitResource: .codeSearch)
            )
        } else {
            response = try await client.send(
                .get(
                    client.url(
                        "search/code",
                        query: SearchEndpointSupport.queryItems(query: query, perPage: perPage)
                    ),
                    headers: headers,
                    rateLimitResource: .codeSearch
                )
            )
        }

        return try SearchResult<SearchCodeDTO>.decoded(from: response)
    }
}
