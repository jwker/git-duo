import Foundation
import GitHubAPI

/// 「我的」页两路数据来源 —— 领域层与网络层之间的**接缝**（TECH_SPEC §9.14）。
///
/// ## 为什么是**两个方法**（而不是像 `SearchDataSource` 那样一个）
///
/// 因为它们是**两个端点、两个配额桶、两条会各自失败的路径**：
///
/// | 方法 | 端点 | 桶 |
/// |---|---|---|
/// | `loadProfile()` | `GET /user` | REST 主桶（5,000/h） |
/// | `loadActivity()` | GraphQL `viewer { … }` | GraphQL 点（5,000/h，这一次 **1 点**） |
///
/// 合成一个方法就必然要么串行（白等一次往返）、要么把两个失败合成一个
/// —— 而决策 #76 末句要的正是**失败隔离**：热力图取不到不该让 Follower 也消失。
/// 两个方法一摆，隔离就成了自然而然的事（`LoadProfileOverview` 里各 catch 各的）。
///
/// ## 返回值用 **DTO**，映射归领域层
///
/// 与 `RepositoryDataSource` 同一条纪律：`ProfileMapper` 才是"这些字段怎么变成
/// 产品语义"的唯一所在，它必须能被单测（App target 没有测试 target）。
/// 所以适配器只负责"把端点回的东西原样端出来"，不在这里做翻译。
///
/// ## 生产实现（切片 9.2 已接上）
///
/// 与切片 8 的处置相同（8.1 立协议、8.2 接端点）：本协议由本包声明、
/// 由本包的单测做替身。真实实现是 `GitHubProfileDataSource` —— 一个把 REST 的
/// `GitHubViewerProfileEndpoint` 与 GraphQL 的 `GitHubViewerActivityEndpoint`
/// 凑齐的包装类型（对照 `GitHubSearchEndpoints`）。
///
/// ⚠️ 那个类型是**纯转发、没有规则**，所以它**没有专属测试套件** —— 装配由
/// `RepoEndpointsContractTests.sliceNineSeams` 那一行保证（签名一改就编译不过）。
/// 这一层真正被断言的是 `LoadProfileOverviewTests`（用脚本化替身测降级隔离）。
public protocol ProfileDataSource: Sendable {

    /// `GET /user` —— 资料头部（昵称 / 简介 / 关注者数）。
    func loadProfile() async throws -> ViewerProfileDTO

    /// GraphQL `viewer { contributionsCollection { contributionCalendar } starredRepositories { totalCount } repositories { totalCount } }`
    /// —— 一次往返同时供热力图与头部的两个计数（决策 #74 / #76）。
    func loadActivity() async throws -> ViewerActivityDTO
}
