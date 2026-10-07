import Foundation
import GitHubAPI

/// 让真实搜索端点满足 `SearchDataSource` 那道**行级接缝**（切片 5.2）。
///
/// ## 它只做一件事：把「一条 part」变成「一页行」
///
/// 四范围共用同一个接缝，而四个端点的返回类型各不相同 ⇒ 这里必须**按 `part.scope` 分发**。
///
/// ⚠️ 分发漏了不会报错：`q=` 里带着 `is:issue` 去问 `/search/users`，服务端只会返回
/// **空结果**，屏幕上表现为"这个范围永远搜不到东西"（而不是一个错误）——
/// 所以这件事有专门的单测（本包 `GitHubSearchDataSourceTests`）。
///
/// ## 它不含业务判断
///
/// DTO → 行的翻译全在 `SearchRowMapper`（纯函数、单独测），
/// 这里只负责"挑端点 + 拼一页 + 原样带出 `totalCount` / 游标 / `incomplete_results`"。
/// 三者漏掉任何一个的症状都是安静的：计数永远 0、翻不了页、"结果不完整"永不提示。
public struct GitHubSearchDataSource: SearchDataSource {

    private let endpoints: any SearchEndpoints

    /// 接缝注入 —— 测试用。
    public init(endpoints: any SearchEndpoints) {
        self.endpoints = endpoints
    }

    /// 组合根用：直接按 `GitHubRESTClient` 装配真实端点。
    public init(client: GitHubRESTClient) {
        self.init(endpoints: GitHubSearchEndpoints(client: client))
    }

    public func search(
        _ part: SearchQueryPart,
        perPage: Int,
        cursor: URL?
    ) async throws -> SearchHitPage {
        switch part.scope {
        case .repositories:
            let result = try await endpoints.searchRepositories(
                query: part.qualifiers, perPage: perPage, cursor: cursor
            )
            return hitPage(result) { .repository(SearchRowMapper.repository($0)) }

        case .users:
            let result = try await endpoints.searchUsers(
                query: part.qualifiers, perPage: perPage, cursor: cursor
            )
            return hitPage(result) { .user(SearchRowMapper.user($0)) }

        case .code:
            let result = try await endpoints.searchCode(
                query: part.qualifiers, perPage: perPage, cursor: cursor
            )
            return try hitPage(result) { .code(try SearchRowMapper.code($0)) }

        case .issues:
            let result = try await endpoints.searchConversations(
                query: part.qualifiers, perPage: perPage, cursor: cursor
            )
            return try hitPage(result) { .conversation(try SearchRowMapper.conversation($0)) }
        }
    }

    // MARK: - 内部

    /// 一页结果 → 一页行。
    ///
    /// ⚠️ **三个字段一个都不能少**：`totalCount` 是结果标题里的 N（决策 #44）、
    /// `nextCursor` 决定「加载更多」还在不在、`incompleteResults` 是"这一页少了东西"
    /// 的唯一信号。它们都由 `LoadSearch` 累计，在这一层丢掉就等于永久删掉。
    private func hitPage<DTO: Sendable>(
        _ result: SearchResult<DTO>,
        _ map: (DTO) throws -> SearchRow
    ) rethrows -> SearchHitPage {
        SearchHitPage(
            rows: try result.items.map(map),
            totalCount: result.totalCount,
            nextCursor: result.nextCursor,
            incompleteResults: result.incompleteResults
        )
    }
}
