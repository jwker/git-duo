import Foundation

/// Star / 取消 Star —— `PUT` / `DELETE /user/starred/{owner}/{repo}`（TECH_SPEC §4.6.2、§4.6.4、§4.13）。
///
/// ## 为什么写操作单独成一个类型
///
/// §4.6.5 的纪律是「**GraphQL 只做聚合，写操作一律走 REST**」（REST 用 URL 直接标识对象，
/// GraphQL 多数要先查 node ID）。本类型是探索链路里**唯一**会改服务端状态的东西 ——
/// 而且它改的**不是那个仓库**，是"你与该仓库的关系"。
///
/// ## ⚠️ 写的那两条**有范围限制**（2026-10-09 真机实测定案，TECH_SPEC §3.5.5）
///
/// 本类型原来的注释写着「它**不需要**对该仓库的任何权限（他人仓库也 Star 得动）」——
/// **那句话是错的，实测推翻了它**：
///
/// | | 自己的仓库 | 别人的仓库 |
/// |---|---|---|
/// | `GET /user/starred/{o}/{r}`（**读**） | 200 / 204 | **200 / 204**（通） |
/// | `PUT` / `DELETE /user/starred/{o}/{r}`（**写**） | **204** ✅ | **403** ❌ |
///
/// 403 的体是 `{"message":"Resource not accessible by integration"}`，
/// 且 **GraphQL `addStar` 同样被拒** ⇒ 这是**权限层**的判断（写 Star 要求目标仓库
/// 落在 **App 的安装范围内**），不是请求形状、更不只是"少勾了 `Starring`"。
///
/// ⇒ 所以本类型**照实抛错**（它不该自己吞掉或改判），由 `GitDuoKit` 那一侧
/// 决定两件事：① **先判"这个仓库写不写得动"**（`StarWriteScope`，判据来自
/// `GET /user/installations`）；② 真被拒时**给一句准确的提示**
/// （`StarCopy.failureMessage(for:)`），而不是通用的 `操作失败 · 请重试`
/// —— 那句话把用户送向"重试"，而重试永远不会成功。
///
/// ## ⚠️ 两个写端点都返回 **204 No Content**（不是 200，也**没有响应体**）
///
/// 所以这里只读状态码、**绝不解码**。顺带一个真实后果：**新计数不在响应里** ——
/// §4.6.2 的口径是"客户端本地 +1 / −1，无需重拉"。那个 ±1 的前提是
/// **知道操作前的状态**，见 `isStarred(owner:repo:)`。
public struct GitHubStarEndpoint: Sendable {

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    /// 查询**你是否已 Star 这个仓库**。
    ///
    /// - Returns: 已 Star ⇒ `true`；没有 ⇒ `false`。
    ///
    /// ## 为什么需要它（不是"锦上添花"）
    ///
    /// §4.6.2 让计数靠**本地 ±1**。而本地 ±1 **必须先知道基准状态**，否则：
    /// 一个你已经 Star 过、共 100 星的仓库，详情页按"未 Star"起手显示 `Star · 100`；
    /// 你点一下 ⇒ `PUT`（服务端幂等、**什么也没发生**）+ 本地 +1 ⇒ 界面变成 `Starred · 101`。
    /// **真实值是 100**，而屏幕上那个 101 会一直挂到下次重新取数为止 ——
    /// 既多算了一颗星，也把"你已经 Star 过"这件事说反了（点击前它显示的是 `Star ·`）。
    ///
    /// ## 实现形状：204 / 404 两条路
    ///
    /// GitHub 用 **204** 表示"已 Star"，用 **404** 表示"没 Star"
    /// （注意：这里的 404 **不**是"仓库不存在"—— 仓库刚刚在详情页取到过，
    /// 存在性已经证实）。其余错误（含 403 权限缺失、配额耗尽）一律原样抛出。
    ///
    /// - Throws: 除 404 外的所有错误。
    public func isStarred(owner: String, repo: String) async throws -> Bool {
        do {
            _ = try await client.send(.get(client.url("user/starred/\(owner)/\(repo)")))
            return true
        } catch {
            if case GitHubError.notFound = error { return false }
            throw error
        }
    }

    /// Star 这个仓库（幂等：已 Star 再调也回 204，不会重复计数）。
    public func star(owner: String, repo: String) async throws {
        try await send(.put, owner: owner, repo: repo)
    }

    /// 取消 Star（幂等：没 Star 过也回 204）。
    ///
    /// ⚠️ 与**登出时的授权撤销**（`DELETE /applications/{client_id}/grant`）是两件事：
    /// 那个是撤销整个 App 的授权，这个是取消一个仓库的星标。
    public func unstar(owner: String, repo: String) async throws {
        try await send(.delete, owner: owner, repo: repo)
    }

    // MARK: - 内部

    private func send(_ method: HTTPMethod, owner: String, repo: String) async throws {
        _ = try await client.send(
            .sending(
                method,
                to: client.url("user/starred/\(owner)/\(repo)"),
                // 失效两份缓存，缺一不可：
                //
                // ① `/user/starred` —— 我的 Star 列表（§4.6.4）。不失效的话，
                //    刚 Star 完进「我的 Star」看不到它。
                // ② `/repos/{owner}/{repo}` —— 仓库详情。它的 `stargazers_count`
                //    现在少/多了一颗。不失效的话，**上一步的本地 ±1 会被打回旧值**：
                //    详情页会用缓存里的旧响应重绘，用户看到的星数"自己弹回去了"。
                //
                // ⚠️ ② 会**连带**清掉该仓库下的 `languages` / `releases/latest` / `contributors`
                //    缓存（`invalidate(pathPrefix:)` 只能按前缀失效，没有"只清这一个路径"的模式）。
                //    代价是下一次进详情页多 3 个主桶请求（5,000/小时，不紧张）；
                //    收益是"星数不会打回旧值"。这个取舍是有意的 —— 数字错了比多三个请求糟得多。
                invalidating: ["/user/starred", "/repos/\(owner)/\(repo)"]
            )
        )
    }
}
