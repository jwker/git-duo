import Foundation

/// 首页置顶仓库 —— `viewer.pinnedItems`（TECH_SPEC §9.1、§4.6.1、§4.6.5）。
///
/// ## 本项目的**首个真业务 GraphQL 用例**
///
/// §4.6.5 把 GraphQL 的用途钉在四个场景上，这是其中之一，理由是 **REST 完全没有置顶端点**
/// （不是"GraphQL 更省事"）—— `ProfileOwner` 只暴露 `pinnedItems` / `pinnableItems` 这些
/// **只读**字段，GraphQL 变更集里不存在任何置顶相关 mutation。所以本类型**只有读**，
/// 「管理」入口只能跳网页端（§9.1）。
///
/// ## 一次查询拿回全部，且只花 1 点配额
///
/// §13.2 的预算表：`pinnedItems(first: 6)` 且**不嵌套任何连接** ⇒ 潜在请求数 1 ⇒ 预扣 **1 点**。
/// 置顶 ≤ 6 个，逐个 `GET /repos/{owner}/{repo}` 是 6 次 REST 往返、还占主桶；
/// 而这里 1 次查询就带回名称 / 描述 / 语言 / Star / Fork / 私有标记。
///
/// ⚠️ **不要在 `nodes` 下面再开连接**（例如给每个仓库取 `issues`）：那正是 §13.2 里
///    "同一个查询只因多写一层嵌套、点数从 1 涨到 100" 的反面案例。
public struct GitHubPinnedItemsEndpoint: Sendable {

    /// 一次取回的置顶上限。
    ///
    /// 6 就是 GitHub 个人主页置顶栏本身的容量（§9.1「≤6 个」），不是我们随手定的数 ——
    /// 写在这里而不是散在调用点，是为了让 `first:` 与它的语义挨着。
    public static let maximumCount = 6

    private let client: GitHubGraphQLClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var transport: HTTPTransport { client.transport }

    public init(client: GitHubGraphQLClient) {
        self.client = client
    }

    /// 取回当前用户的全部置顶仓库（最多 6 个，顺序即 GitHub 上的排列顺序）。
    ///
    /// 返回空数组是**正常结果**（还没置顶任何仓库），不是错误 —— 视图据此显示空态
    /// `GitHub 个人主页还没有置顶仓库`（§9.1）。
    ///
    /// - Throws: `GitHubError.graphQLErrors(messages:partialData:)`（**HTTP 200 也可能是失败**，
    ///   错误在 body 的 `errors` 里）、`GitHubError.decoding`（形状完全不符）、
    ///   以及 transport 归一化出的网络 / 状态码错误。
    public func pinnedRepositories() async throws -> [PinnedRepositoryDTO] {
        let response = try await client.query(
            Self.query,
            variables: Variables(first: Self.maximumCount),
            as: Response.self
        )
        // 元素可空：失效的置顶（仓库被删 / 安装范围没勾到）会回 null，
        // 让它**只丢自己那一个**，而不是把整块首页打崩。
        return response.viewer.pinnedItems.nodes.compactMap { $0 }
    }

    // MARK: - 查询文本

    /// ⚠️ 三处细节**都不是随手写的**：
    ///
    /// 1. `types: [REPOSITORY]` 是**字面量而不是变量** —— 它的取值集合由 schema 固定
    ///    （`PinnableItem` = `Repository` | `Gist`），不是可调参数。写成变量只会多一个
    ///    "调用方传错就静默查不到东西"的入口。
    /// 2. `first: $first` 走变量，把上限留在 Swift 侧（`maximumCount`）—— 数字进查询文本
    ///    就再也 grep 不到了，而它是配额预算的一部分（§13.2）。
    /// 3. `... on Repository` 是**必须的**：`nodes` 的元素类型是 union `PinnableItem`，
    ///    不写内联片段就取不到任何仓库字段。
    /// 4. `viewerPermission`（2026-10-06 补）是**首页置顶卡去向的唯一依据**：
    ///    卡片要在点开之前就知道该进"自己的仓库"还是"他人只读页"（TECH_SPEC §9.1、铁律 #7）。
    ///    ⚠️ 它是**标量字段、不是连接** ⇒ 预扣点数仍是 1 点（§13.2 的预算不变）。
    static let query = """
    query PinnedItems($first: Int!) {
      viewer {
        pinnedItems(first: $first, types: [REPOSITORY]) {
          nodes {
            ... on Repository {
              nameWithOwner
              description
              isPrivate
              stargazerCount
              forkCount
              viewerPermission
              primaryLanguage { name }
              # 走查第 72 条：置顶卡换 owner 头像。`avatarUrl` 是标量字段、
              # 不是连接 ⇒ 预扣点数不变（§13.2「加字段不扣点」）。
              owner { avatarUrl }
            }
          }
        }
      }
    }
    """

    // MARK: - 私有形状

    struct Variables: Encodable, Sendable {
        let first: Int
    }

    struct Response: Decodable, Sendable {

        struct Viewer: Decodable, Sendable {
            let pinnedItems: PinnedItems
        }

        struct PinnedItems: Decodable, Sendable {
            /// ⚠️ 元素**可空**（schema：`nodes: [PinnableItem]`）。
            /// 声明成 `[PinnedRepositoryDTO]` 会让"一个失效置顶"变成"整页没有置顶"。
            let nodes: [PinnedRepositoryDTO?]
        }

        let viewer: Viewer
    }
}
