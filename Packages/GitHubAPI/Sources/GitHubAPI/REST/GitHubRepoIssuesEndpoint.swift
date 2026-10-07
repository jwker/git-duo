import Foundation

/// 仓库的 **Issue 列表（只读）** —— `GET /repos/{owner}/{repo}/issues`（TECH_SPEC §4.6.2、§4.14）。
///
/// 只读是**客户端行为**：这条请求对任何公开仓库都成立，不需要任何额外权限；
/// 而"能不能关 Issue / 加标签"由 `GET /repos/{o}/{r}` 的 `permissions` 决定（§9.11），
/// 是另一个端点的事。本类型只提供读。
public struct GitHubRepoIssuesEndpoint: Sendable {

    /// 列表页大小（与其余列表一致，§4.4）。
    public static let pageSize = 30

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    /// 取一页**开放式** Issue。
    ///
    /// - Parameter cursor: 上一页的 `nextCursor`。`nil` 取第一页。
    ///    续页用 `client.page(at:)`（完整 URL）—— 自己拼 `?page=n` 会漏掉
    ///    服务端带的其它参数（§4.4）。
    ///
    /// - Returns: 一页条目。⚠️ **里面混着 PR**，调用方必须按 `isPullRequest` 过滤
    ///   （见 `IssueDTO` 的类型说明）。
    ///
    /// ## 为什么方法名带 `open`
    ///
    /// 本切片只用到"开放式"这一种（PRD §4.14 的说明行就是 `开放 {N} 个`）。
    /// 写成一个不带参数的 `issues()` 再加一个 `state` 开关，会留一个**至今没有任何调用方**
    /// 的分支 —— 而它的取值集合（`open` / `closed` / `all`）与响应里的 `state`
    /// （只有 `open` / `closed`）并不是同一个词汇表，混在一个参数里迟早有人传错。
    /// 切片 7 的「我的仓库」四分区确实需要"已关闭"，**那时再加参数**。
    ///
    /// ⚠️ **服务端也会混入 PR，所以分页步长不是"每页 30 个 Issue"** ——
    /// 一页 30 条里可能只有 9 个 Issue。这不是 bug，是 `GET /issues` 的固有行为；
    /// 也因此界面上的计数用**过滤后的已加载条数**（2026-10-06 用户拍板）。
    public func openIssues(
        owner: String,
        repo: String,
        cursor: URL? = nil
    ) async throws -> Page<IssueDTO> {
        if let cursor {
            return try await client.page(at: cursor, as: IssueDTO.self)
        }
        return try await client.page(
            "repos/\(owner)/\(repo)/issues",
            query: [
                URLQueryItem(name: "state", value: "open"),
                // 显式写 sort / direction / per_page：不依赖服务端默认值（§4.6.2 的同类口径）。
                // 它们也决定缓存键 —— 隐式默认值会让"服务端改了默认"表现为缓存莫名换了一份。
                URLQueryItem(name: "sort", value: "created"),
                URLQueryItem(name: "direction", value: "desc"),
                URLQueryItem(name: "per_page", value: String(Self.pageSize))
            ],
            as: IssueDTO.self
        )
    }
}
