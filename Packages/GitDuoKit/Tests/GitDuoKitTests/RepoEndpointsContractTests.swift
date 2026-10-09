import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// **接缝清点** —— `RepoEndpoints.swift` 的类型说明点名过这个文件。
///
/// ## 为什么需要一个"看起来什么都没测"的测试
///
/// 领域层与网络层之间的接缝，写法都是这样一个**空的大括号**：
///
/// ```swift
/// extension GitHubRepoContentEndpoint: RepoFileWriteDataSource {}
/// ```
///
/// 它看起来像死代码 —— 删掉之后**编译照样过、其余测试照样绿**，
/// 一直到组合根真正装配时才炸（而那时的错误信息指向 `AppEnvironment`，
/// 与真正的原因隔着两层）。
///
/// 所以这里把每一条接缝**当作协议用一次**：能赋值给 `any RepoYDataSource`，
/// 就同时说明了两件事 ——
///
/// 1. 扩展体还在；
/// 2. 端点的方法签名与协议**逐字一致**（对不上时，空的扩展体会当场报
///    "does not conform to protocol"，而不是等到调用那一刻）。
///
/// ⇒ 它把"某天有人顺手删掉一个空扩展体"从**静默**变成**当场红**。
///
/// ## 关于"一个端点对多个协议"
///
/// `GitHubRepoPullsEndpoint` 一个类型就对着 **4 条**接缝（列表 / 详情 / 建 PR / 动作），
/// `GitHubRepoIssuesEndpoint` 同样 5 条 —— 这是有意的：接缝是按**用例需要哪些动作**切的，
/// 不是按端点切的（见 `RepoEndpoints` 的类型说明）。
/// 本文件把同一端点的多条接缝**分开列**，就是为了让"它到底服务几个用例"看得见。
@Suite("接缝清点 · 领域层与网络层之间")
struct RepoEndpointsContractTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private var client: GitHubRESTClient { GitHubRESTClient(credentials: credentials) }

    /// ⚠️ 置顶那一条走的是 **GraphQL** 客户端，不是 REST —— 两者的接缝长得一样，
    /// 但客户端类型不同。写错了的表现是编译不过（这一步还好），
    /// 但"以为所有端点都收 REST 客户端"这个印象本身值得在这里点出来。
    private var graphQLClient: GitHubGraphQLClient {
        GitHubGraphQLClient(credentials: credentials)
    }

    // MARK: - 仓库读（切片 3 / 6 / 7 / 8）

    @Test("仓库详情 / 代码浏览 / 提交 / 分支 —— 四条读接缝")
    func repoReadSeams() {
        let _: any RepoDetailDataSource = GitHubRepoDetailEndpoint(client: client)
        let _: any RepoContentsDataSource = GitHubRepoContentEndpoint(client: client)
        let _: any RepoCommitsDataSource = GitHubRepoCommitEndpoint(client: client)
        let _: any RepoBranchDataSource = GitHubRepoBranchEndpoint(client: client)
    }

    @Test("切片 6/7 的七条接缝（仓库四分区 + Issue 三条 + PR 三条）")
    func sliceSixAndSevenSeams() {
        // 仓库四分区
        let _: any RepoInsightsDataSource = GitHubRepoInsightsEndpoint(client: client)
        let _: any RepoIssuesDataSource = GitHubRepoIssuesEndpoint(client: client)
        let _: any RepoPullsDataSource = GitHubRepoPullsEndpoint(client: client)
        let _: any RepoLabelsDataSource = GitHubRepoLabelsEndpoint(client: client)

        // Issue 侧
        let _: any IssueDetailDataSource = GitHubRepoIssuesEndpoint(client: client)
        let _: any IssueCommentReading = GitHubRepoIssuesEndpoint(client: client)
        let _: any IssueComposerDataSource = GitHubRepoIssuesEndpoint(client: client)
        // ⚠️ 2026-10-09 新增（决策 #79）：关闭 / 重新打开走同一个端点。
        //    ⚠️ 这一行不能少：`extension GitHubRepoIssuesEndpoint: IssueActionDataSource {}`
        //    是个空扩展体，删掉之后**编译照过、其余测试照绿**，一直到组合根装配时才炸。
        let _: any IssueActionDataSource = GitHubRepoIssuesEndpoint(client: client)

        // PR 侧
        let _: any PullDetailDataSource = GitHubRepoPullsEndpoint(client: client)
        let _: any PullActionDataSource = GitHubRepoPullsEndpoint(client: client)
    }

    // MARK: - 写通道（切片 8.2 新接上的两条）

    @Test("⚠️ 切片 8 的两条写接缝 —— 8.1 立协议、8.2 接上，这里钉住它们**没有掉下来**")
    func sliceEightWriteSeams() {
        // `RepoFileWriteDataSource` 与 `RepoContentsDataSource` 是**同一个类型**的两个协议：
        // 写与读各自服务不同的用例（`SaveFile` / `DeleteFile` 只要写那一条）。
        let _: any RepoFileWriteDataSource = GitHubRepoContentEndpoint(client: client)

        // 「新分支 + PR」的第三步
        let _: any RepoPullCreationDataSource = GitHubRepoPullsEndpoint(client: client)
    }

    // MARK: - 切片 3 / 4 / 5

    @Test("仓库列表 / Star / 置顶 / 趋势榜 / 搜索 —— 五条接缝")
    func earlierSliceSeams() {
        let _: any RepositoryDataSource = GitHubRepositoryEndpoint(client: client)
        let _: any StarDataSource = GitHubStarEndpoint(client: client)
        let _: any PinnedRepositoriesDataSource = GitHubPinnedItemsEndpoint(client: graphQLClient)
        let _: any RepositorySearchDataSource = GitHubSearchRepositoriesEndpoint(client: client)
        let _: any SearchDataSource = GitHubSearchDataSource(client: client)
    }

    // MARK: - 切片 11（Star 写范围的如实降级 · 决策 #80）

    @Test("⚠️ 切片 11 的接缝 —— 空扩展体，删掉之后编译照过、其余测试照绿")
    func sliceElevenSeam() {
        // `extension GitHubInstallationsEndpoint: StarScopeDataSource {}`（在 `StarWriteScope.swift`）——
        // 它是空的那一类，**必须有这一行**才守得住（同 `IssueActionDataSource` 那条）。
        let _: any StarScopeDataSource = GitHubInstallationsEndpoint(client: client)
    }

    // MARK: - 切片 9（我的页 / 我的会话）

    @Test("⚠️ 切片 9 的两条接缝 —— 9.1 立协议、9.2 接上，这里钉住它们**没有掉下来**")
    func sliceNineSeams() {
        // 一条是**空的**扩展体（那个端点的方法签名与协议逐字一致）——
        // 删掉它编译照样过、其余测试照样绿，所以必须有这一行。
        let _: any ConversationSearchEndpoint = GitHubSearchIssuesEndpoint(client: client)

        // 另一条跨两个端点类型（一个 REST、一个 GraphQL），所以是"凑齐"的类型：
        // 它同时说明两件事 —— 两个端点的方法名没被改过、两个客户端的装配签名没被改过。
        let _: any ProfileDataSource = GitHubProfileDataSource(
            restClient: client,
            graphQLClient: graphQLClient
        )

        // 适配器那一侧（生产实现）也各用一次：它俩是组合根真正要装配的东西。
        let _: any MyConversationsDataSource = GitHubMyConversationsDataSource(client: client)
    }
}
