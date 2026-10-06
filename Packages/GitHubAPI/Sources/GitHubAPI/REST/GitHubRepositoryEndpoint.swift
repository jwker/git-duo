import Foundation

/// 仓库列表端点 —— `GET /user/repos` 与 `GET /user/starred`。
///
/// 依据：TECH_SPEC §4.6.2、§9.3。
///
/// ## `affiliation` 的三个值**有意写全**（决策 #34 的配套口径，2026-10-06 用户拍板）
///
/// §4.6.2 原来写的是 `?affiliation=owner`，但那与 §8.1「自己的仓库 = 用户**拥有写权限**的
/// 任意仓库」对不上：只拉 owner 的话，组织仓库与别人邀请你协作的仓库**永远不出现在「仓库」Tab**，
/// 而 PRD §1 明写目标用户是"个人项目 + 团队仓库"。
///
/// 于是改为 `owner,collaborator,organization_member`（= GitHub 的默认集合）。
/// **写全而不省略**的理由：省略等于把行为押在服务端的默认值上，而默认值是会变的；
/// 写在这里，这条口径在调用点就看得见。
///
/// ⚠️ 可写性**仍然**由 `permissions.push` 判定，与本参数无关 ——
///    这个参数只决定"哪些仓库会出现"，不决定"哪些能写"。
public struct GitHubRepositoryEndpoint: Sendable {

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言请求形状与"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session。
    ///
    /// 生产里所有端点必须共用**同一个** `GitHubRESTClient`（= 同一个 `HTTPTransport`），
    /// 才能共享那一份缓存、那一个配额闸门、那一套重试策略。
    /// 给本类型开一个"自己拿 credentials 造 transport"的便利构造，就等于留了第二条出网通道 ——
    /// 而它**不会报错**，只会让缓存分成两份、配额各算各的。
    /// 测试需要桩件时，请显式构造 `GitHubRESTClient(credentials:session:cache:)`。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    // MARK: - 仓库列表

    /// `GET /user/repos` —— 「全部 / 公开 / 私有」三段的数据源（本地按 `private` 过滤，§9.3）。
    ///
    /// - Parameter cursor: 上一页的 `nextCursor`；`nil` 表示取第一页。
    public func listRepos(cursor: URL? = nil) async throws -> Page<RepositoryDTO> {
        try await page(path: "user/repos", cursor: cursor)
    }

    /// `GET /user/starred` —— 「Starred」段的数据源（§9.3：前三段本地过滤，这一段另取）。
    public func listStarred(cursor: URL? = nil) async throws -> Page<RepositoryDTO> {
        try await page(path: "user/starred", cursor: cursor)
    }

    // MARK: - 内部

    private func page(path: String, cursor: URL?) async throws -> Page<RepositoryDTO> {
        if let cursor {
            return try await client.page(at: cursor, as: RepositoryDTO.self)
        }
        return try await client.page(
            path,
            query: [
                URLQueryItem(
                    name: "affiliation",
                    value: "owner,collaborator,organization_member"
                ),
                URLQueryItem(name: "sort", value: "updated"),
                // §4.4：列表默认 per_page=30。写出来是为了不依赖服务端默认值 ——
                // 它也决定缓存键，隐式取默认值会让"改了默认值"表现为缓存莫名换了一份。
                URLQueryItem(name: "per_page", value: "30")
            ],
            as: RepositoryDTO.self
        )
    }
}
