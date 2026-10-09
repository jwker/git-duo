import Foundation
import GitHubAPI

/// 「我的 Pull Request / 我的 Issue」那一条查询的取数入口 ——
/// 领域层与网络层之间的**端点接缝**（切片 9.2）。
///
/// ## 为什么单开一条，而不是复用搜索页的 `SearchEndpoints`
///
/// 接缝是按**用例需要哪些动作**切的，不是按端点切的（`RepoEndpointsContractTests`
/// 的抬头写着这条判据）。搜索页要的是"服务端 best match"（**不带** `sort`），
/// 这一页要的是 `sort=updated&order=desc`（PRD §4.21）—— 两条口径不同，
/// 而 `sort` 漏了**不会报错**，只会安静地按相关度排。
///
/// 如果复用搜索页那条，`GitHubMyConversationsDataSource` 就得偷看搜索页的常量、
/// 或者去改它的签名；单开一条之后，"这一页必须带排序"就成了**协议要求**，
/// 想漏也漏不掉（协议声明里不允许默认值 ⇒ 调用方必须显式交出这两个参数）。
///
/// ## ⚠️ 扩展体是**空的**，所以它是"被删了也不报错"的那一类
///
/// 与 `extension GitHubRepositoryEndpoint: RepositoryDataSource {}` 同一处置：
/// 删掉之后编译照样过、其余测试照样绿，一直到组合根装配时才炸。
/// ⇒ 已在 `RepoEndpointsContractTests` 里把它**当协议用一次**。
public protocol ConversationSearchEndpoint: Sendable {

    /// 发一条 `search/issues` 查询的一页。
    ///
    /// - Parameters:
    ///   - query: 完整的 `q=`，**必须含 `is:issue` 或 `is:pull-request`**
    ///     （决策 #47：App 用户令牌下一次只能问一类）。这一层**不再拦第二遍** ——
    ///     那条规则的唯一实现在领域层（`MyConversationsQuery`）。
    ///   - sort: **独立查询参数**（不是 `q` 里的限定符）。本页传
    ///     `MyConversationsQuery.sortParameter`。
    ///
    /// - Throws: 数据层归一化后的 `GitHubError`。
    func search(
        query: String,
        perPage: Int,
        cursor: URL?,
        sort: String?,
        order: String
    ) async throws -> SearchResult<SearchConversationDTO>
}

/// 生产实现：真实端点接上这条接缝。
///
/// ⚠️ **签名与协议逐字一致**（对齐由编译器保证；被删由清点测试保证）。
extension GitHubSearchIssuesEndpoint: ConversationSearchEndpoint {}
