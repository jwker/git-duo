import Foundation

/// 单个用户的公开资料 —— `GET /users/{login}`（PRD §5.10 用户资料弹层）。
///
/// ## 为什么搜索之外还要这一个端点
///
/// `GET /search/users` 返回的是**精简对象**：只有 `login` + `avatar_url`，
/// 拿不到昵称 / 简介 / 公开仓库数 / 关注者数（官方 200 示例就不含这些）。
/// 而 `GET /users/{login}` 返回完整公开资料 —— 搜索页点用户行时，用它补全弹层
/// （C 方案：列表行保持精简，点开才补一次）。
///
/// ## 配额与缓存
///
/// 走默认的 `core` 主桶（5,000/小时），**不是**搜索桶；缓存开启 ——
/// 公开资料第二次看大概率 304（ETag），不计配额。
///
/// ⚠️ `login` 直接拼进路径：GitHub 登录名只允许字母、数字与连字符，无需额外编码。
public struct GitHubPublicUserEndpoint: Sendable {

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言请求形状与会话。
    var session: URLSession { client.transport.session }

    /// ⚠️ 只有这一个初始化器：生产里所有端点必须共用同一个 `GitHubRESTClient`
    /// （否则缓存分成几份、配额各算各的，而且不报错）。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    /// 取某用户的公开资料。
    ///
    /// - Throws: `GitHubError`。`404` 表示该用户不存在（notFound）。
    public func loadUser(login: String) async throws -> SearchUserDTO {
        try await client.get("users/\(login)", as: SearchUserDTO.self)
    }
}
