import Foundation
import GitHubAPI

/// 四个搜索范围各自的取数入口 —— 领域层与网络层之间的**端点接缝**。
///
/// ## 为什么要多这一层（而不是让 `GitHubSearchDataSource` 直接攥着四个端点）
///
/// 与 `RepositorySearchDataSource` / `RepoPullsDataSource` 同一手法：
/// 协议由本包声明、由本包的单测做替身，真实端点在一个具体类型里凑齐。
/// 有了它，适配器里**真正容易写错的那部分**（哪个范围打哪个端点、四份行怎么拼、
/// `total_count` 与游标有没有原样带出去）就能在没有网络的情况下被断言 ——
/// 而"HTTP 头带没带版本号""`q` 怎么编码"已经由 `GitHubAPITests` 用真实
/// `URLProtocol` 桩件覆盖过了。
///
/// ⚠️ 四个方法**分属四个不同的端点类型**，所以没法像 `RepositorySearchDataSource` 那样
/// 用一句 `extension` 让某个既有类型直接满足协议 —— 需要 `GitHubSearchEndpoints`
/// 这个"凑齐"的包装。它是生产里唯一的实现，**没有逻辑**（只有转发）。
public protocol SearchEndpoints: Sendable {

    /// `GET /search/repositories` 的一页。`sort` 一律不带（要的是服务端 best match）。
    func searchRepositories(
        query: String,
        perPage: Int,
        cursor: URL?
    ) async throws -> SearchResult<SearchRepositoryDTO>

    /// `GET /search/users` 的一页。
    func searchUsers(
        query: String,
        perPage: Int,
        cursor: URL?
    ) async throws -> SearchResult<SearchUserDTO>

    /// `GET /search/code` 的一页（带 `text-match` 媒体类型）。
    func searchCode(
        query: String,
        perPage: Int,
        cursor: URL?
    ) async throws -> SearchResult<SearchCodeDTO>

    /// `GET /search/issues` 的一页。`query` 必须自带 `is:issue` / `is:pull-request`
    /// （决策 #47：App 用户令牌下一次只能问一类）。
    func searchConversations(
        query: String,
        perPage: Int,
        cursor: URL?
    ) async throws -> SearchResult<SearchConversationDTO>
}

/// 生产实现：四个真实端点凑齐上面的接缝。
///
/// ⚠️ 四个端点**共用同一个 `GitHubRESTClient`**（由这一个初始化器保证）——
/// 各自 new 一个的话缓存会分成几份、配额各算各的，而它不会报错。
public struct GitHubSearchEndpoints: SearchEndpoints {

    private let repositories: GitHubSearchRepositoriesEndpoint
    private let users: GitHubSearchUsersEndpoint
    private let code: GitHubSearchCodeEndpoint
    private let issues: GitHubSearchIssuesEndpoint

    public init(client: GitHubRESTClient) {
        self.repositories = GitHubSearchRepositoriesEndpoint(client: client)
        self.users = GitHubSearchUsersEndpoint(client: client)
        self.code = GitHubSearchCodeEndpoint(client: client)
        self.issues = GitHubSearchIssuesEndpoint(client: client)
    }

    public func searchRepositories(
        query: String,
        perPage: Int,
        cursor: URL?
    ) async throws -> SearchResult<SearchRepositoryDTO> {
        // `sort` 走默认的 `nil` ⇒ 不带 `sort`/`order`，即服务端的 best match。
        try await repositories.search(query: query, perPage: perPage, cursor: cursor)
    }

    public func searchUsers(
        query: String,
        perPage: Int,
        cursor: URL?
    ) async throws -> SearchResult<SearchUserDTO> {
        try await users.search(query: query, perPage: perPage, cursor: cursor)
    }

    public func searchCode(
        query: String,
        perPage: Int,
        cursor: URL?
    ) async throws -> SearchResult<SearchCodeDTO> {
        try await code.search(query: query, perPage: perPage, cursor: cursor)
    }

    public func searchConversations(
        query: String,
        perPage: Int,
        cursor: URL?
    ) async throws -> SearchResult<SearchConversationDTO> {
        try await issues.search(query: query, perPage: perPage, cursor: cursor)
    }
}
