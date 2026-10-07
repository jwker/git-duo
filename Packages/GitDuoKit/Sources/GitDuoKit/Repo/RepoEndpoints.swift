import Foundation
import GitHubAPI

/// 仓库详情 / 代码浏览 / 提交 / 分支四条链路在**领域层与网络层之间的接缝**。
///
/// 依据：TECH_SPEC §9.4 / §9.5 / §9.7 / §9.7.1。
/// 先例：`RepositoryDataSource`（切片 3）、`RepoInsightsDataSource`（切片 4）。
///
/// ## 为什么每个端点一个协议、而不是"一个大协议"
///
/// 每个用例只用得上其中一两个端点（`LoadRepoTree` 要 contents + commits，
/// `LoadBranches` 只要 branches）。合成一个大协议会让**每个替身都得实现全部方法**，
/// 于是"这个用例到底依赖哪几个动作"这件事就从类型上消失了 ——
/// 而那正是这层接缝存在的理由（见 `RepositoryDataSource` 的类型说明）。
///
/// ## 协议与扩展都在 `GitDuoKit`、被扩展的类型在 `GitHubAPI`
///
/// 这**不是**追溯适配（retroactive conformance）：协议是我们自己声明的，
/// 不存在"两个模块给同一个类型声明同一份适配"的冲突风险（同 `RepositoryDataSource`）。
///
/// ⚠️ 扩展体可以是**空的** —— 条件是真实端点的**方法签名逐字一致**（含默认值参数：
/// 默认值不参与签名比对）。任何一处参数名改了，这里会**编译不过**，
/// 那正是我们想要的：接缝断开要当场可见，而不是等到运行时才发现调错了。
/// （有一条测试用 `RepoEndpointsContractTests` 钉住四种载荷的类型，见该文件。）

// MARK: - ① 仓库详情头部

/// `GET /repos/{owner}/{repo}` —— 仓库详情页（§4.4）的头部。
public protocol RepoDetailDataSource: Sendable {

    /// 仓库头部。`permissions` 决定整页给不给编辑入口（§8.3、铁律 #7）。
    func repository(owner: String, repo: String) async throws -> RepositoryDetailDTO
}

extension GitHubRepoDetailEndpoint: RepoDetailDataSource {}

// MARK: - ② 代码浏览与文件正文

/// 目录清单 / 文件正文 / README（§4.4 代码分区、§4.5 文件查看）。
public protocol RepoContentsDataSource: Sendable {

    /// 一个路径的内容 —— 目录回 `.directory`、文件回 `.file`（同一个路由的两种形状）。
    func contents(
        owner: String,
        repo: String,
        path: String,
        ref: String?
    ) async throws -> ContentsPayload

    /// 裸字节（`Accept: application/vnd.github.raw`）—— 大文本与图片走它（决策 #54）。
    func rawFile(
        owner: String,
        repo: String,
        path: String,
        ref: String?
    ) async throws -> Data

    /// README 原文（raw Markdown）；**`nil` = 这个仓库没有 README**（唯一允许吞 404 的一处）。
    func readme(owner: String, repo: String, ref: String?) async throws -> String?
}

extension GitHubRepoContentEndpoint: RepoContentsDataSource {}

// MARK: - ③ 提交

/// 提交列表 / 提交详情 / 某一文件的最近一条（§4.4 分区四、§4.7、决策 #49）。
public protocol RepoCommitsDataSource: Sendable {

    /// 一页提交（`cursor` 为 `nil` 取第一页）。
    func commits(
        owner: String,
        repo: String,
        branch: String?,
        cursor: URL?
    ) async throws -> Page<CommitListItemDTO>

    /// 提交详情 —— 含 `stats` 与 `files[].patch`。
    func commit(owner: String, repo: String, sha: String) async throws -> CommitDetailDTO

    /// 最近一次改动该路径的提交；该路径没有任何提交时 `nil`。
    ///
    /// ⚠️ **它走的是一次真实请求**（`per_page=1`），文件树的每一行都要它一次
    /// —— 这正是决策 #49 的代价，也是"副标题分两趟填"的由来。
    func latestCommit(
        owner: String,
        repo: String,
        path: String,
        ref: String?
    ) async throws -> CommitListItemDTO?
}

extension GitHubRepoCommitEndpoint: RepoCommitsDataSource {}

// MARK: - ④ 分支（读 + 写）

/// 分支列表 / 单分支 / 比较 / 建 / 删 / 合并（§4.8、§5.7、决策 #52 / #53）。
public protocol RepoBranchDataSource: Sendable {

    /// `GET /repos/{o}/{r}/branches?per_page=100`。`hasMore` 用来判断
    /// `items.count` 是不是精确总数（决策 #40 的口径）。
    func branches(owner: String, repo: String) async throws -> Page<BranchDTO>

    /// `GET /repos/{o}/{r}/branches/{branch}` —— **只在列表里没有它时才该调用**（§9.7.1）。
    func branch(owner: String, repo: String, name: String) async throws -> BranchDTO

    /// `GET /repos/{o}/{r}/compare/{base}...{head}` —— 删除前的未合并校验只读 `aheadBy`。
    func compare(
        owner: String,
        repo: String,
        base: String,
        head: String
    ) async throws -> CompareDTO

    /// `POST /repos/{o}/{r}/git/refs` —— **不幂等**，不自动重试。
    @discardableResult
    func createBranch(
        owner: String,
        repo: String,
        name: String,
        sha: String
    ) async throws -> GitReferenceDTO

    /// `DELETE /repos/{o}/{r}/git/refs/heads/{branch}` —— 成功是 204，无响应体。
    func deleteBranch(owner: String, repo: String, name: String) async throws

    /// `POST /repos/{o}/{r}/merges` —— `.nothingToMerge`（204）**不是失败**。
    func merge(
        owner: String,
        repo: String,
        base: String,
        head: String,
        message: String?
    ) async throws -> MergeOutcome
}

extension GitHubRepoBranchEndpoint: RepoBranchDataSource {}
