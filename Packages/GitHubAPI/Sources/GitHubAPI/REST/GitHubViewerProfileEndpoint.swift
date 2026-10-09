import Foundation

/// 「我的」页的资料头部 —— `GET /user`（TECH_SPEC §9.14、PRD §4.17、决策 #76）。
///
/// ## 为什么不复用 `GitHubUserEndpoint`
///
/// 那个端点是**登录第 8 步**的契约（§3.1）：它只声明 `login`、对外抛 `OAuthError`、
/// 并且用 `HTTPRequest.explicitToken` 把令牌显式交进去（那一刻 Keychain 还是空的）。
/// 三件事都只服务"验证令牌有效性"这一个用途。
///
/// 本类型是**登录之后的日常读**：走 `AccessTokenProviding`（令牌从 Keychain 来）、
/// 抛 `GitHubError`、要 `name` / `bio` / `followers` 三个登录路径根本不看的字段。
/// 合成一个的话，"登录能不能成功"会开始取决于三个它并不需要的字段。
/// （`ViewerProfileDTO` 的类型说明里记着同一条判据。）
///
/// ## 配额：主桶
///
/// 走默认的 `.core`（5,000/小时）。**不是搜索桶** —— 它是一条普通读，
/// 而且有 ETag 兜着（第二次进「我的」页大概率是 304，不计配额）。
public struct GitHubViewerProfileEndpoint: Sendable {

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session —— 生产里所有端点
    /// 必须共用同一个 `GitHubRESTClient`（理由见 `GitHubRepositoryEndpoint` 的说明）。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    /// 取回当前令牌对应的用户资料。
    ///
    /// ## 缓存是**开着**的（与 `GitHubUserEndpoint` 有意相反）
    ///
    /// 那边是"一次性有效性校验"，`cachesResponse: false`——免得把"某枚一次性令牌能用"
    /// 固化下来。这里是**页面内容**：带 `If-None-Match` 问一次，命中就是 304、**不计配额**，
    /// 而拿到的还是最新的一份（ETag 变了就说明昵称 / 简介变了）。
    ///
    /// ⚠️ 这份缓存是**自建的那一层**，不是 `URLCache`（决策 #32）——
    /// 本包所有出网会话都不挂系统缓存。
    ///
    /// - Throws: 数据层归一化后的 `GitHubError`。**注意 401 的处理**：
    ///   它由 `HTTPTransport` 归一化成 `.unauthorized`（凭据失效 ⇒ 上层登出），
    ///   而不是在这里被吞成"这一块加载失败"（决策 #33 的唯一出口）。
    public func loadProfile() async throws -> ViewerProfileDTO {
        try await client.get("user", as: ViewerProfileDTO.self)
    }
}
