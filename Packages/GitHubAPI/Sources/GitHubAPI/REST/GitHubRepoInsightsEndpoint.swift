import Foundation

/// 语言 → **字节数**（`GET /repos/{owner}/{repo}/languages` 的响应就是这样一个 JSON 对象）。
///
/// ⚠️ **顺序没有任何意义** —— 它是一个 JSON 对象，`Dictionary` 的迭代顺序在 Swift 里
/// 本就不确定，而"百分比 + 占比条"必须按字节数降序。所以**排序与百分比换算都在领域层做**
/// （否则同一个响应两次解析可能得到两根顺序不同的占比条）。
///
/// ⚠️ 官方**只给字节数、不给百分比**，需要本地 `bytes / sum(bytes)`。
/// 也不给颜色 —— 语言色来自 `GitDuoDesign` 的内置映射表（§9.11）。
public typealias LanguageBytes = [String: Int]

/// 他人仓库详情页的四路数据 —— TECH_SPEC §9.11 点名的
/// `GET /repos/{o}/{r}` + `languages` + `releases/latest` + `contributors`。
///
/// ## 为什么四个方法在一个类型里
///
/// 它们**只被同一屏使用**（§4.13 的头部 / 语言构成 / Latest Release / 贡献者），
/// 且共享同一个实例状态（`client`）。拆成四个类型只会让调用方多写四行装配代码，
/// 换不来任何隔离 —— 它们的调用点永远是同一处。
///
/// ## 它们都是**只读**的
///
/// 本类型没有任何写方法：探索页对他人仓库**无写操作**（PRD §4.13），
/// 唯一会写的是 Star（`GitHubStarEndpoint`，它写的是**你与这个仓库的关系**，
/// 不是仓库本身）。
public struct GitHubRepoInsightsEndpoint: Sendable {

    /// 贡献者一页取回多少。
    ///
    /// 取 **100（端点上限）** 而不是 30，是因为 PRD §4.13 要显示总数
    /// （`贡献者 · {N} 位`），而 `GET /contributors` **不返回总数**。
    /// 一页 100 条覆盖了绝大多数仓库 ⇒ 没有下一页时 `hasMore == false`，
    /// 此时条目数**就是**精确总数；出现下一页才退化成"100 位以上"
    /// （2026-10-06 用户拍板，备选是额外打一次 `?per_page=1` 读 `Link` 的 `rel=last` 页号）。
    public static let contributorPageSize = 100

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session —— 理由同
    /// `GitHubRepositoryEndpoint`：所有端点必须共用同一个 `GitHubRESTClient`。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    // MARK: - 仓库头部

    /// `GET /repos/{owner}/{repo}` —— 详情的头部数据（§9.11）。
    public func repository(owner: String, repo: String) async throws -> RepositoryDetailDTO {
        try await client.get("repos/\(owner)/\(repo)", as: RepositoryDetailDTO.self)
    }

    // MARK: - 语言构成

    /// `GET /repos/{owner}/{repo}/languages` —— REST 独有（GraphQL 无等价端点，§4.6.3）。
    ///
    /// 返回空字典是正常结果（空仓库）。**不要**把它当成失败。
    public func languages(owner: String, repo: String) async throws -> LanguageBytes {
        try await client.get("repos/\(owner)/\(repo)/languages", as: LanguageBytes.self)
    }

    // MARK: - Latest Release

    /// `GET /repos/{owner}/{repo}/releases/latest`。
    ///
    /// - Returns: 最新正式版本；**`nil` 表示这个仓库没有发布过版本**。
    /// - Throws: 除 404 外的所有错误原样抛出（网络、配额、5xx、解码…）。
    ///
    /// ⚠️ **404 在这里被有意吞掉并翻译成 `nil`**。这是"404 与无权限被 GitHub 混同"
    /// 那条纪律的**唯一例外**，理由是可以确定的：同一屏的 `GET /repos/{o}/{r}` 已经成功，
    /// 仓库存在且可见已被证实 ⇒ 这个 404 只可能是"没有 release"。
    /// 不这么做的话，一个只是没发过版本的仓库会让整个详情页显示成"加载失败"。
    ///
    /// ⚠️ **只吞 404**。其余错误必须抛出 —— 把 5xx / 断网也吞成 `nil`，
    /// 用户会看到"这个仓库没有版本"，而事实是网络断了（"断网 ≠ 没有数据"）。
    public func latestRelease(owner: String, repo: String) async throws -> RepoReleaseDTO? {
        do {
            return try await client.get(
                "repos/\(owner)/\(repo)/releases/latest",
                as: RepoReleaseDTO.self
            )
        } catch {
            if case GitHubError.notFound = error { return nil }
            throw error
        }
    }

    // MARK: - 贡献者

    /// `GET /repos/{owner}/{repo}/contributors?per_page=100`。
    ///
    /// 返回 `Page` 而不是裸数组，是为了把 **`hasMore`** 带出来：
    /// 没有下一页时 `page.items.count` 就是**精确**的贡献者总数（§4.13 的 `{N} 位`）；
    /// 有下一页时只能说"至少 100 位"。丢掉 `hasMore` 就等于丢掉这个区分。
    ///
    /// ⚠️ **空仓库回 204 No Content，不是 200 + `[]`**（官方文档明确）。
    /// 走 `client.page(...)` 会拿一个空 body 去解 `[T]` ⇒ **解码失败**，
    /// 于是"这个仓库还没有贡献者"会被显示成"加载失败"。所以这里手工发请求、
    /// 在解码之前先把 204 认出来。
    ///
    /// ⚠️ 顺带一条实测口径：**这个 204 会被写进响应缓存**
    /// （`CachedHTTPResponse.isStorable` 只挡 `Cache-Control: no-store`，不看状态码）。
    /// 这对"首屏本地优先"其实有益 —— 能立刻渲染出"还没有贡献者"；
    /// 但**直接读缓存的那一方必须先看 `statusCode`**，别拿一个空 body 去解码。
    /// ⚠️ **为什么是两个重载，而不是一个带默认值的参数**（2026-10-06 编译期踩到）：
    ///
    /// **默认参数不能充当协议见证。** `RepoInsightsDataSource`（声明在 `GitDuoKit`）
    /// 要求的是 `contributors(owner:repo:)` **两参数**形式，而带默认值的
    /// `contributors(owner:repo:perPage:)` 在见证匹配时**参数个数就是对不上** ——
    /// 报错只有一句 `type 'GitHubRepoInsightsEndpoint' does not conform to
    /// protocol 'RepoInsightsDataSource'`，`note` 里那句 `(String, String)` 才是线索。
    ///
    /// 拆成两个**真方法**（谁都不要默认值）同时解决第二件事：如果让带默认值的三参数版
    /// 与本方法并存，调用点写两参数时两个候选都成立 ⇒ **重载歧义**。
    public func contributors(owner: String, repo: String) async throws -> Page<RepoContributorDTO> {
        try await contributors(owner: owner, repo: repo, perPage: Self.contributorPageSize)
    }

    /// 显式指定 `per_page` 的那一档 —— 测试用它断言查询串里真的是 `per_page=100`。
    public func contributors(
        owner: String,
        repo: String,
        perPage: Int
    ) async throws -> Page<RepoContributorDTO> {
        let response = try await client.send(
            .get(
                client.url(
                    "repos/\(owner)/\(repo)/contributors",
                    query: [URLQueryItem(name: "per_page", value: String(perPage))]
                )
            )
        )

        if response.statusCode == 204 {
            return Page(items: [], headers: response.headers)
        }

        return Page(
            items: try response.decode([RepoContributorDTO].self),
            headers: response.headers
        )
    }
}
