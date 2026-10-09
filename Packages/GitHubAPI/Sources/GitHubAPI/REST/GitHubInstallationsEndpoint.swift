import Foundation

/// 「授权范围自查」—— `GET /user/installations`（TECH_SPEC §3.5.4 / **§3.5.5**、§4.6.4、决策 **#80**）。
///
/// ## 它回答的问题
///
/// > **本 App 装在哪些账号上？**
///
/// 这个集合是「Star 写得动吗」的**唯一**判据（`GitDuoKit.StarWriteScope`）——
/// 因为 GitHub App 的用户令牌，**写 Star 只对「App 安装范围内的仓库」有效**：
/// 自己的仓库 `PUT` 回 **204**、别人的仓库回 **403** `Resource not accessible by integration`
/// （2026-10-09 真机实测，REST 与 GraphQL 两条路同样被拒）。
///
/// ## ⚠️ 它是 user-to-server 端点，**不需要任何额外权限**
///
/// 2026-10-09 实测：带上本 App 的用户令牌直接回 **200**（当时只有 1 个安装）。
/// ⇒ 不必为它去 `§3.4` 的权限清单里加项 —— 那条清单与授权页、登录页预告**逐条对应**，
/// 加一项就要动三处（还有 harness 的"预告 ≡ 清单"断言）。
///
/// ## ⚠️ 只取 `account.login`，其余字段**故意不声明**
///
/// 响应里还有 `id` / `repository_selection` / `permissions` / `events` 等。
/// 判定只需要"哪些账号"这一个集合；把别的字段也解出来会诱使调用方在**这里**
/// 做第二套判断，而判据只能有一处（`StarWriteScope.canWrite(fullName:)`）。
///
/// ⚠️ 其中 `repository_selection` 尤其别急着用：它是 `"all"` 还是 `"selected"`
/// 会影响"这个具体仓库在不在范围里"，而本片对它采取的处置是
/// **"不确定就不拦"**（见 `StarWriteScope` 的说明）—— 不是靠多解一个字段解决的。
///
/// ## ⚠️ 分页：只取第一页，且这是**有意**的
///
/// 用户自己装过的 App 数量是个位数（每一行 = 一个用户或组织），
/// 100 条一页足以覆盖；出现下一页时**不续**（续页的代价是每次进页多一次请求，
/// 而它换来的是"第 101 个安装"—— 一个不存在的场景）。
public struct GitHubInstallationsEndpoint: Sendable {

    /// 一页取回 —— 端点的上限（同 `GitHubRepoLabelsEndpoint.pageSize` 的口径：
    /// 宁可一次多要点，也别让"只显示了一部分"变成屏幕上完全看不出来的事）。
    public static let pageSize = 100

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    /// 已安装本 App 的**账号登录名**（user 或 org），按服务端返回的顺序。
    ///
    /// - Throws: 网络层的一切错误（调用方 `LoadStarWriteScope` 会把它折叠成 `.unknown` ——
    ///   这次查询失败不该让任何页面打不开）。
    public func installedAccounts() async throws -> [String] {
        let payload = try await client.get(
            "user/installations",
            query: [URLQueryItem(name: "per_page", value: String(Self.pageSize))],
            as: InstallationsDTO.self
        )
        // ⚠️ `login` 缺失的条目**丢掉而不是补空串** —— 一个空串会在
        //    `StarWriteScope` 那一侧变成"名字为空的账号装了 GitDuo"，
        //    而那不会报错，只会让某个仓库的按钮莫名其妙可点。
        return payload.installations.compactMap(\.account?.login)
    }

    // MARK: - 响应形状

    /// 只声明判定用得上的那一个字段 —— 见类型说明。
    private struct InstallationsDTO: Decodable {
        let installations: [InstallationDTO]
    }

    private struct InstallationDTO: Decodable {
        let account: AccountDTO?
    }

    private struct AccountDTO: Decodable {
        let login: String?
    }
}
