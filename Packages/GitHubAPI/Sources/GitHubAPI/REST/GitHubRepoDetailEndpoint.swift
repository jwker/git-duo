import Foundation

/// 仓库详情页（**自己的仓库**，PRD §4.4）的头部数据 —— `GET /repos/{owner}/{repo}`。
///
/// ## 为什么它与 `GitHubRepoInsightsEndpoint.repository(owner:repo:)` 是两个类型
///
/// 两者打的是**同一条路由**、解的是**同一个 DTO**（`RepositoryDetailDTO`）——
/// 重复的只有一行 URL。不合并的理由是**语义**：那一个是探索页看**别人的**仓库
/// （只读、不问写权限），本类型是「我的仓库 → 看代码」这条主线上的**可写详情**
/// （`permissions` 决定整页给不给编辑入口）。
///
/// 把它们合成一个类型，会让"仓库详情页的数据层"横跨到探索那边去 ——
/// 而下一句通常就是"既然都在一个类型里，顺手把探索的 languages / contributors 也调过来",
/// 那正是切片边界开始溶解的样子。
///
/// ⚠️ 真正的反重复在 DTO 上：**两边共用 `RepositoryDetailDTO`**，
/// 所以字段口径（例如 `watcherCount` 必须读 `subscribers_count`）只有一处定义。
public struct GitHubRepoDetailEndpoint: Sendable {

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session ——
    /// 所有端点必须共用同一个 `GitHubRESTClient`。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    /// 取仓库头部。
    ///
    /// 返回的 `defaultBranch` 是**分支解析的起点**（§9.4.1）：
    /// 进仓库先拿它当回落值，再去 `GET …/branches` 校正记忆值。
    ///
    /// ⚠️ 这一路上**没有一处可以吞掉的错误**：
    /// - 404 同时意味着"仓库不存在"与"你没有权限"（GitHub 混同这两件事），
    ///   文案必须两说，绝不能替用户断定是哪一种；
    /// - 403 可能是配额、二级限流或权限不足，只有响应头分得清。
    ///
    /// - Parameter rateLimitResource: 显式 `.core`。本类型全部请求都在**主桶**上
    ///   （5,000/小时，靠 ETag 压住）；显式写出来是为了让"这里不是搜索桶"
    ///   在**读代码时**就能看出来，而不是要靠"默认值是 `.core`"去推。
    public func repository(owner: String, repo: String) async throws -> RepositoryDetailDTO {
        try await client.get(
            "repos/\(owner)/\(repo)",
            as: RepositoryDetailDTO.self,
            rateLimitResource: .core
        )
    }
}
