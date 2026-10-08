import Foundation

/// PR 的一个改动文件 —— `GET /repos/{o}/{r}/pulls/{n}/files` 的元素。
///
/// ## ⚠️ 它是 `CommitFileDTO` 的**别名**，不是新类型
///
/// 两个端点的文件条目**形状完全一致**（`filename` / `status` / `additions` / `deletions` /
/// `changes` / `blob_url` / `raw_url` / `contents_url` / `patch` / `previous_filename`），
/// 而本项目收的就那几样。
///
/// 那为什么不直接写 `CommitFileDTO`？因为读代码的人在 PR 那一屏看到
/// "Commit" 会以为取错了端点。别名让**词**对上、**定义**只有一份 ——
/// 两个类型各写一遍字段清单的下场是：哪天补一个字段，总有一处漏掉，
/// 而漏掉的那处不报错、只是少显示一样东西（"同形必分叉"，这里选了不分叉）。
///
/// ⚠️ 领域层因此只需要**一个**映射器（`FileChange`），两个端点共用 —— 那是别名带来的好处。
public typealias PullFileDTO = CommitFileDTO

/// 仓库的 **PR 读写** —— 列表 / 详情 / 文件 / Commits / 评审 / 合并 / 关闭
/// （TECH_SPEC §4.6.2、§4.15、§9.9）。
///
/// 与 `GitHubRepoIssuesEndpoint` 的关系：**PR 的"会话评论"走 Issue 端点**
/// （`/issues/{n}/comments`，GitHub 把 PR 当作一种 Issue），
/// 而列表、详情、文件、Commits、**评审**、合并、关闭走本类型（§4.6.2 / §9.9）。
/// 两个类型不是重复的。
///
/// ## ⚠️ `/reviews` 与 `/comments` 别混（决策 #60）
///
/// `GET …/pulls/{n}/comments` 是**行内评论**（挂在 diff 的某一行上），**不带审批状态**；
/// 审批状态（`APPROVED` / `CHANGES_REQUESTED` / …）只在 `GET …/pulls/{n}/reviews`。
/// 本类型**只提供 `/reviews`** —— 行内评论本片不渲染（原型也没有），
/// 用不到的东西不声明（"只声明真正用到的字段"同理）。
public struct GitHubRepoPullsEndpoint: Sendable {

    /// 列表页大小（与其余列表一致，§4.4）。
    public static let pageSize = 30

    /// 文件 / Commits / 评审三页的页大小。
    ///
    /// 取端点上限 100 而不是 30：这三样都是**这一屏的内容本身**
    /// （PRD §4.11「{N} 个文件 · 点击文件卡片展开 diff」、Commits 列表、评审列表），
    /// 只给 30 条会让"这个 PR 有 87 个文件"在界面上变成"有 30 个"。
    /// 缺口由 `nextCursor` 兜住。
    ///
    /// ⚠️ `{N} 个文件` 那个数字**不用这一页的条数**，用 `PullDetailDTO.changedFiles`
    /// （见那里的说明：两者都是"文件数"，读错不报错、只显示一个偏小的数）。
    public static let detailPageSize = 100

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    // MARK: - 读：列表

    /// 取一页 PR（**按状态**）。
    ///
    /// - Parameter state: `open` / `closed` / `all`。⚠️ 服务端**没有 "只看已合并"** 这一个
    ///   筛选项（`state` 只有 open / closed；合并与"关闭但没合并"长得一样）⇒ 要看"已合并"
    ///   只能取 `closed` 再按 `isMerged` 本地分（§9.9、PRD §4.4 分区三）。
    /// - Parameter cursor: 上一页的 `nextCursor`；`nil` 取第一页。
    ///
    /// ## 三个取值分别是谁在用
    ///
    /// | 调用方 | `state` | 之后还要滤什么 |
    /// |---|---|---|
    /// | 探索 PR 列表（§4.15、决策 #39） | `all` | **滤掉 `.closed`**（只留开放 + 已合并） |
    /// | 仓库详情 PR 段「已合并」（§4.4 分区三） | `closed` | 滤掉"关闭但没合并的" |
    /// | 仓库详情 PR 段「开放」 | `open` | 不用滤 |
    ///
    /// ⚠️ `state` **没有默认值**，这是有意的：三个调用方的意图各不相同，
    /// 给个默认值等于让"忘了传"表现为"混排"，而那看起来完全正常
    /// （切片 4 给 `openIssues` 写死 `state=open` 是对的，因为那时只有一种用途；
    /// 现在有四种用途，写死与默认值都会静默选错一侧）。
    public func pullRequests(
        owner: String,
        repo: String,
        state: String,
        cursor: URL? = nil
    ) async throws -> Page<PullRequestDTO> {
        if let cursor {
            return try await client.page(at: cursor, as: PullRequestDTO.self)
        }
        return try await client.page(
            "repos/\(owner)/\(repo)/pulls",
            query: [
                URLQueryItem(name: "state", value: state),
                // 显式写全，不依赖服务端默认值（它们也决定缓存键）
                URLQueryItem(name: "sort", value: "created"),
                URLQueryItem(name: "direction", value: "desc"),
                URLQueryItem(name: "per_page", value: String(Self.pageSize))
            ],
            as: PullRequestDTO.self
        )
    }

    // MARK: - 读：详情

    /// 单个 PR —— `GET /repos/{o}/{r}/pulls/{n}`（PRD §4.11）。
    ///
    /// ⚠️ **`additions` / `deletions` / `changed_files` 只有这条请求会给**
    /// （列表端点不返回 ⇒ 决策 #58）。PR 详情页的「文件 +842 −156」因此只有这一条路。
    public func pullRequest(owner: String, repo: String, number: Int) async throws -> PullDetailDTO {
        try await client.get(
            "repos/\(owner)/\(repo)/pulls/\(number)",
            as: PullDetailDTO.self,
            rateLimitResource: .core
        )
    }

    // MARK: - 读：文件

    /// PR 的改动文件 —— `GET /repos/{o}/{r}/pulls/{n}/files`（PRD §4.11 分区三）。
    ///
    /// ⚠️ **每个文件的 `patch` 是独立的一份 diff、各自从头编号** ——
    /// 不能把它们接成一份连续 diff 解析（那是本片的验证靶心，§9.9 与 §11.2）。
    ///
    /// ⚠️ `patch` 为 `nil` 有**两种**原因（二进制 / 改动过大），用户出路不同；
    /// 判定在领域层（`FileChange`），本层原样带出去。
    public func pullFiles(
        owner: String,
        repo: String,
        number: Int,
        cursor: URL? = nil
    ) async throws -> Page<PullFileDTO> {
        if let cursor {
            return try await client.page(at: cursor, as: PullFileDTO.self)
        }
        return try await client.page(
            "repos/\(owner)/\(repo)/pulls/\(number)/files",
            query: [URLQueryItem(name: "per_page", value: String(Self.detailPageSize))],
            as: PullFileDTO.self
        )
    }

    // MARK: - 读：Commits

    /// PR 里的提交 —— `GET /repos/{o}/{r}/pulls/{n}/commits`（PRD §4.11 分区二）。
    ///
    /// ⚠️ 返回的就是提交列表那一份 `CommitListItemDTO`：两个端点的条目形状一致
    /// （`sha` / `commit{message,author,committer}` / `author`），
    /// 所以 PR 的提交行**直接复用提交详情页**（§4.7），不另做一套行视图。
    public func pullCommits(
        owner: String,
        repo: String,
        number: Int,
        cursor: URL? = nil
    ) async throws -> Page<CommitListItemDTO> {
        if let cursor {
            return try await client.page(at: cursor, as: CommitListItemDTO.self)
        }
        return try await client.page(
            "repos/\(owner)/\(repo)/pulls/\(number)/commits",
            query: [URLQueryItem(name: "per_page", value: String(Self.detailPageSize))],
            as: CommitListItemDTO.self
        )
    }

    // MARK: - 读：评审

    /// PR 的评审 —— `GET /repos/{o}/{r}/pulls/{n}/reviews`（**决策 #60**）。
    ///
    /// ⚠️ **不是** `/pulls/{n}/comments` —— 那个是行内评论、不含审批状态。
    /// 原型评论上那枚「已批准」胶囊来自本端点（`PullReviewDTO` 的对照表）。
    public func pullReviews(
        owner: String,
        repo: String,
        number: Int,
        cursor: URL? = nil
    ) async throws -> Page<PullReviewDTO> {
        if let cursor {
            return try await client.page(at: cursor, as: PullReviewDTO.self)
        }
        return try await client.page(
            "repos/\(owner)/\(repo)/pulls/\(number)/reviews",
            query: [URLQueryItem(name: "per_page", value: String(Self.detailPageSize))],
            as: PullReviewDTO.self
        )
    }

    // MARK: - 写：合并

    /// 合并 PR —— `PUT /repos/{o}/{r}/pulls/{n}/merge`（PRD §5.3、TECH_SPEC §9.9）。
    ///
    /// - Parameter method: 三种方式之一（PRD §5.3 的单选，默认第一项 `merge`）。
    ///
    /// - Returns: 见 `PullMergeOutcome` —— **200 + 405 两档，且 200 也要看响应体里的
    ///   `merged`**（"只看状态码就报成功"是这条路上最容易犯的错）。
    ///
    /// ⚠️ **写操作不自动重试**（`HTTPMethod.isSafelyRetryable` 只认 GET）：
    /// 合并重放会真的产生第二个合并提交。
    ///
    /// ⚠️ 405 在本端点**不是失败**，是"这个 PR 不能被合并"的一种确凿答案
    /// （已合过 / draft / 有冲突）⇒ 转成 `.notMergeable`，不抛错。
    /// 而 **404 / 403 照旧抛** —— 那两样是"这个 PR 你看不到"或"你没权限"，
    /// 与"不能合"是不同的事（GitHub 把 404 与无权限混同，文案统一"不存在或无权访问"）。
    public func mergePull(
        owner: String,
        repo: String,
        number: Int,
        method: PullMergeMethod
    ) async throws -> PullMergeOutcome {
        let body = try JSONSerialization.data(
            withJSONObject: ["merge_method": method.rawValue],
            options: [.sortedKeys]
        )

        do {
            let response = try await client.send(
                .sending(
                    .put,
                    to: client.url("repos/\(owner)/\(repo)/pulls/\(number)/merge"),
                    body: body,
                    // 合上了 ⇒ 详情（状态变了）、列表（去向变了）都要失效。
                    invalidating: [Self.pullsPrefix(owner: owner, repo: repo)]
                )
            )
            let result = try response.decode(PullMergeResultDTO.self)
            // ⚠️ 200 不等于成功 —— 见 `PullMergeOutcome` 的长说明。
            return result.merged ? .merged(result) : .notMergeable
        } catch GitHubError.serverError(let status) where status == 405 {
            return .notMergeable
        }
    }

    // MARK: - 写：关闭 / 重新打开

    /// 关闭或重新打开 PR —— `PATCH /repos/{o}/{r}/pulls/{n}`（PRD §4.11 操作区）。
    ///
    /// - Parameter state: **只允许 `open` / `closed`**。
    ///   ⚠️ 本方法**故意不做校验**：`isMerged` 那一档（已合并的 PR 不给任何操作按钮）
    ///   是**产品口径**（PRD §4.11 的操作区表格），它属于领域层（`PullAction`）。
    ///   数据层照发，把服务端的话带回来 —— 与 `deleteBranch` 的做法一致。
    ///
    /// - Returns: 更新后的详情（服务端回的是完整的 PR 对象，直接用，
    ///   不自己在本地改一个 `state` 字段 —— 那样"界面说已关闭、服务端说还开着"就成了可能）。
    public func updatePullState(
        owner: String,
        repo: String,
        number: Int,
        state: String
    ) async throws -> PullDetailDTO {
        let body = try JSONSerialization.data(
            withJSONObject: ["state": state],
            options: [.sortedKeys]
        )
        let response = try await client.send(
            .sending(
                .patch,
                to: client.url("repos/\(owner)/\(repo)/pulls/\(number)"),
                body: body,
                invalidating: [Self.pullsPrefix(owner: owner, repo: repo)]
            )
        )
        return try response.decode(PullDetailDTO.self)
    }

    // MARK: - 缓存前缀

    /// PR 的**整棵子树**：列表 / 详情 / 文件 / Commits / 评审都在 `/pulls` 下面。
    ///
    /// 粗粒度理由同 `GitHubRepoIssuesEndpoint.issuesPrefix`。
    private static func pullsPrefix(owner: String, repo: String) -> String {
        "/repos/\(owner)/\(repo)/pulls"
    }
}
