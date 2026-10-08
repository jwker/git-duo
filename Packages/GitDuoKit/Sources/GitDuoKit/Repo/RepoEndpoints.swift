import Foundation
import GitHubAPI

/// 仓库详情 / 代码浏览 / 提交 / 分支 / **文件写** / **建 PR** 六条链路在
/// **领域层与网络层之间的接缝**。
///
/// 依据：TECH_SPEC §9.4 / §9.5 / §9.6 / §9.7 / §9.7.1。
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
///
/// ⚠️ 但**编译期保证只覆盖"签名改了"**：一个空的扩展体被**整条删掉**时，
/// 编译、其余测试**全都不会有反应** —— 那也是一种"静默"。所以另有一条测试
/// （`RepoEndpointsContractTests`）把每条接缝**当作协议用一次**，专钉这一种情形。
/// **新增接缝时记得在那边也加一行**，否则它保护的名单会慢慢落后于现实。

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

// MARK: - ⑤ 文件写（切片 8）

/// 写文件的两条动作：`PUT`（新建 / 更新）与 `DELETE`（删除）—— §9.6.1、§9.6.5。
///
/// ## ⚠️ `branch` 是**必传参数**，不是可选
///
/// 官方原文：`branch` — *"The branch name. **Default: the repository's default branch.**"*
/// ⇒ 不传的后果是**用户在 `feature/x` 上编辑、提交却落到 `main`**，
/// 而全过程没有错误信号（界面显示"已提交"，分支也对，只是提交去了别处）——
/// 决策 #65，性质同 #47 / #53 那些"外部事实逼出来的"条目。
///
/// 所以它在签名里**没有默认值**：接缝这一层不允许"忘了传"这件事发生。
/// 有一条正面断言钉住它（`make test` 里的请求构造测试，见切片 8.2）。
///
/// ## ⚠️ `sha` 的两个含义（同一个参数，两种语义）
///
/// - `putFile`：`nil` = **新建**（路径已存在 ⇒ 服务端 422，**不静默覆盖**，决策 #70⑤）；
///   非 `nil` = **更新**，而那个值必须是**用户读到的那一版**（乐观锁，见 `SaveFile`）；
/// - `deleteFile`：**必填**（官方要求 `message` 与 `sha` 都必填），且它是**现取**的
///   （删除没有"用户手上的那一版"这回事，见 `DeleteFile`）。
///
/// 类型上无法把这两种语义分开（同一个 `String?` / `String`），所以两条说明写在这里。
///
/// ## ⚠️ 为什么不做 `@discardableResult`
///
/// `putFile` 的返回值（新 `sha` + 提交 `sha`）**必须被消费**：编辑器要靠新 `sha`
/// 换掉手上的基准，否则连续两次编辑的第二次必然 409（看起来像"刚提交完就说被人改过"）。
/// `deleteFile` 返回 `Void`（成功是 204、无响应体），所以它天然没有这个问题。
///
/// ## ⚠️ 扩展体在 8.2 已接上
///
/// 本协议在 8.1（领域层）落地，`GitHubRepoContentEndpoint` 的两个写方法在 **8.2** 补上
/// ⇒ 扩展体现在存在。中间那一版之所以是空的，是因为**协议先立、端点的实现随后跟上**
/// 是这片接缝的固定分工（与切片 7 的 `PullActionDataSource` 同一先例）——
/// 它与类型顶部那条"扩展体可以是空的"是同一件事的两面。
/// ⚠️ 它不再空也是一个信号：`GitHubRepoContentEndpoint` 的方法**签名一旦改动**，
/// 这里会**当场编译不过**，而不是等到调用时才炸。
public protocol RepoFileWriteDataSource: Sendable {

    /// 新建 / 更新一个文件（`PUT /repos/{o}/{r}/contents/{path}`）。
    ///
    /// - Parameters:
    ///   - path: 仓库内相对路径（`RepoPath.raw`），**不带前导 `/`**。
    ///   - message: 提交信息。**空串不该走到这里** —— 「空则用默认信息」那条规则
    ///     在领域层（`CommitDraft.effectiveMessage` / `CommitMessageDefaults`）。
    ///   - content: **原始字节**；base64 编码是数据层的事（§4.6.2）。
    ///     放数据层的理由与图片不重编码同源：那一步错了的表现是"内容损坏"。
    ///   - sha: 见类型说明（`nil` = 新建）。
    ///   - branch: **必传**，见类型说明。
    ///
    /// - Returns: 新 blob SHA 与提交 SHA。
    func putFile(
        owner: String,
        repo: String,
        path: String,
        message: String,
        content: Data,
        sha: String?,
        branch: String
    ) async throws -> FileWriteResultDTO

    /// 删除一个文件（`DELETE /repos/{o}/{r}/contents/{path}`）。
    ///
    /// ⚠️ 官方 NOTE：它**不能与 `putFile` 并行**（会冲突），必须 serially ——
    /// 这正是「重命名 = PUT 新 + DELETE 旧」要顺序两步的原因（决策 #66）。
    /// 串行的编排在 `RenameFile` 里，本层只是两个各自独立的动作。
    ///
    /// - Parameter sha: **必填**（官方要求）。取法见 `DeleteFile`（现取）。
    func deleteFile(
        owner: String,
        repo: String,
        path: String,
        message: String,
        sha: String,
        branch: String
    ) async throws
}

extension GitHubRepoContentEndpoint: RepoFileWriteDataSource {}

// MARK: - ⑥ 建 PR（切片 8，「新分支 + PR」的第三步）

/// `POST /repos/{o}/{r}/pulls` —— §9.6.3 的第三步。
///
/// ## ⚠️ 三个必填，一个都不能少
///
/// 官方原文：`title` — *"Required unless issue is specified"*；
/// `head` / `base` — `(required)`。
/// 而原型与 PRD §5.9 的提交弹层里**原本只有一个 commit message 输入框** ——
/// 那两个必填值没有任何来源，这正是决策 #67（弹出两行输入）要补的缺口。
///
/// ## ⚠️ `head` 在同仓库时**只写分支名**
///
/// `owner:branch` 是**跨仓库 fork** 的写法。本期"新分支 + PR"的分支恒在同一个仓库里
/// ⇒ 传 `name` 即可；传成 `owner:name` 在官方文档下也是合法的（同一个 owner），
/// 但那会让这条调用的前提（"就在本仓库"）从代码里消失。
///
/// ## ⚠️ 扩展体同样在 8.2 已接上
///
/// 与 `RepoFileWriteDataSource` 同一条：协议在 8.1、端点方法在 8.2。
/// 这一条比那一条更值得留意 —— `head` / `base` 两个参数**在别处都以 `String` 出现**
/// （分支名到处都是 `String`），签名错位一对调不动编译器，只会发出一次参数对调的请求。
public protocol RepoPullCreationDataSource: Sendable {

    /// 开一个 PR。
    ///
    /// - Parameters:
    ///   - title: **必填**。领域层保证它非空（`CommitDraft.effectivePRTitle` 的回落链）。
    ///   - head: 源分支 —— 「新分支 + PR」里刚建成的那条（只写分支名，见类型说明）。
    ///   - base: 目标分支 —— 提交弹层里那个"当前分支"。
    ///
    /// - Returns: 服务端回的那条 PR（**编号只能用这一份**，
    ///   同 `CreatedIssue.number` 的理由：不能靠本地猜）。
    func createPull(
        owner: String,
        repo: String,
        title: String,
        head: String,
        base: String
    ) async throws -> PullDetailDTO
}

extension GitHubRepoPullsEndpoint: RepoPullCreationDataSource {}

