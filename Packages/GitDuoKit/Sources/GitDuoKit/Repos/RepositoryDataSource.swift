import Foundation
import GitHubAPI

/// 仓库列表的数据来源 —— 领域层与网络层之间的**接缝**。
///
/// ## 为什么要有这层协议
///
/// 领域层的测试应该断言"分段过滤、去重、状态迁移"这些**业务规则**，而不是
/// "请求头带没带版本号""`Link` 头解析对不对" —— 后者已经由 `GitHubAPITests`
/// 用真实的 `URLProtocol` 桩件覆盖过了。
///
/// 有了这层接缝，本包的测试可以直接喂一页数据进去，不必再复制一整套 HTTP 桩件；
/// 同时它也把"领域层依赖的是哪几个动作"写明在类型上 —— 依赖的是**取数的能力**，
/// 不是某个具体的 HTTP 客户端。
///
/// ⚠️ 返回值用数据层的 `Page<RepositoryDTO>`（而不是已映射的 `Page<Repository>`）是**有意的**：
///    映射与过滤都是领域层的职责，若把它们放进实现方，这两条规则就会各自散在
///    每个数据源里，而它们本该只有一处、且被测试守着。
public protocol RepositoryDataSource: Sendable {

    /// `GET /user/repos` 的一页（`cursor` 为 `nil` 表示第一页）。
    func listRepos(cursor: URL?) async throws -> Page<RepositoryDTO>

    /// `GET /user/starred` 的一页。
    func listStarred(cursor: URL?) async throws -> Page<RepositoryDTO>
}

/// 让真实端点满足上面的接缝。
///
/// 协议与本扩展都在 `GitDuoKit` 里，被扩展的类型在 `GitHubAPI` 里 ——
/// 这**不是**追溯适配（retroactive conformance）：协议是我们自己声明的，
/// 所以不存在"两个模块给同一个类型声明同一份适配"的冲突风险。
extension GitHubRepositoryEndpoint: RepositoryDataSource {}
