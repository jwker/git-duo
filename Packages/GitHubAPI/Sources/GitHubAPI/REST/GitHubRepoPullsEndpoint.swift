import Foundation

/// 仓库的 **PR 列表（只读）** —— `GET /repos/{owner}/{repo}/pulls`（TECH_SPEC §4.6.2、§4.15）。
///
/// 与 `GitHubRepoIssuesEndpoint` 的关系：**PR 的"会话评论"走 Issue 端点**
/// （`/issues/{n}/comments`），而列表、diff、评审评论走 PR 端点（§4.6.2）。
/// 所以这两个类型不是重复的。
public struct GitHubRepoPullsEndpoint: Sendable {

    /// 列表页大小（与其余列表一致，§4.4）。
    public static let pageSize = 30

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    /// 取一页 PR（**开放 + 已合并/已关闭**，`state=all`）。
    ///
    /// - Parameter cursor: 上一页的 `nextCursor`；`nil` 取第一页。
    ///
    /// ## 为什么是 `state=all` 而不是 `state=open`
    ///
    /// PRD §4.15 完全没规定取哪些，而原型（**事实优先级最高的一侧**）是**混排**：
    /// 两条开放 + 一条已合并，每行按状态换图标。
    /// 这与刚定的 Issue 口径（只取开放式）**有意不对称**，理由不是"照抄原型"，而是：
    /// - PR 的 `已合并` 是一个**结局**，信息量高；而 Issue 的 `已关闭` 只说明"没人做了"。
    /// - PRD §4.13 把进入本页的入口副标题写成「**查看他人贡献** · 可评论不可合并」——
    ///   已合入的 PR 正是"贡献"最直接的证据，把它们藏起来与本页的立意相悖。
    ///
    /// 已合并的判定**不在服务端**（没有 `merged` 状态）：取回后按 `isMerged` 本地判定（§4.6.2）。
    public func pullRequests(
        owner: String,
        repo: String,
        cursor: URL? = nil
    ) async throws -> Page<PullRequestDTO> {
        if let cursor {
            return try await client.page(at: cursor, as: PullRequestDTO.self)
        }
        return try await client.page(
            "repos/\(owner)/\(repo)/pulls",
            query: [
                URLQueryItem(name: "state", value: "all"),
                // 显式写全，不依赖服务端默认值（它们也决定缓存键）
                URLQueryItem(name: "sort", value: "created"),
                URLQueryItem(name: "direction", value: "desc"),
                URLQueryItem(name: "per_page", value: String(Self.pageSize))
            ],
            as: PullRequestDTO.self
        )
    }
}
