import Foundation
import GitHubAPI

/// 生产实现：两个真实端点凑齐 `ProfileDataSource` 那道接缝（切片 9.2）。
///
/// ## 为什么需要这个"凑齐"的类型
///
/// 与 `GitHubSearchEndpoints` / `GitHubSearchDataSource` 同一手法：那道接缝的两个方法
/// **分属两个不同的端点类型**（一个 REST、一个 GraphQL），所以没法像
/// `extension GitHubRepositoryEndpoint: RepositoryDataSource {}` 那样让某一个既有类型
/// 直接满足协议 —— 那样写也是不可能的：`ProfileDataSource` 要求两个方法都在。
///
/// 于是这个类型只做转发，**没有任何判断**。
///
/// ## ⚠️ 两个客户端**不是同一个**
///
/// 这是本类型的另一处要点：REST 与 GraphQL 是**两个端点、两个配额桶、两条会各自失败的路径**。
/// 用一个客户端硬凑（比如让 GraphQL 也走 REST 客户端）在类型上做不到；
/// 而"以为它们共用一份缓存 / 一个桶"这个印象本身值得在这里点出来。
/// （`LoadProfileOverview` 的并发与分开降级正是建立在这条事实上。）
public struct GitHubProfileDataSource: ProfileDataSource {

    private let profile: GitHubViewerProfileEndpoint
    private let activity: GitHubViewerActivityEndpoint

    /// 接缝注入 —— 测试用（两个替身各接各的）。
    public init(
        profile: GitHubViewerProfileEndpoint,
        activity: GitHubViewerActivityEndpoint
    ) {
        self.profile = profile
        self.activity = activity
    }

    /// 组合根用：按两个客户端装配真实端点。
    ///
    /// ⚠️ 两个客户端必须由调用方传**共享的那一对** —— 各建一份的话缓存会分成几份、
    /// 配额各算各的，而它不会报错（同 `GitHubSearchEndpoints` 的说明）。
    public init(restClient: GitHubRESTClient, graphQLClient: GitHubGraphQLClient) {
        self.init(
            profile: GitHubViewerProfileEndpoint(client: restClient),
            activity: GitHubViewerActivityEndpoint(client: graphQLClient)
        )
    }

    /// `GET /user`（主桶）。
    public func loadProfile() async throws -> ViewerProfileDTO {
        try await profile.loadProfile()
    }

    /// GraphQL `viewer` 三个字段（**1 点**，切年份也是 1 点）。
    public func loadActivity(from: Date, to: Date) async throws -> ViewerActivityDTO {
        try await activity.loadActivity(from: from, to: to)
    }
}
