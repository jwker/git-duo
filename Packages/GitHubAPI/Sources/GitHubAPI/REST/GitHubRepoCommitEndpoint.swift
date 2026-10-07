import Foundation

/// 提交：列表 / 详情 / 某一文件的最近一条 —— `GET /repos/{o}/{r}/commits` 与
/// `GET /repos/{o}/{r}/commits/{sha}`（TECH_SPEC §4.6.2 / §9.5、PRD §3.7、§4.4 分区四、§4.7）。
///
/// ## ⚠️ 列表与详情**不是同一份数据**（2026-10-07 实测）
///
/// | | 列表 `commits` | 详情 `commits/{sha}` |
/// |---|---|---|
/// | `commit.message` / 作者 / 时间 | ✅ | ✅ |
/// | `files[]`（含 `patch`） | ❌ | ✅ |
/// | `stats{additions,deletions,total}` | ❌ | ✅ |
///
/// 所以"在列表行上顺手显示 `+12 −4`"是**做不到**的 —— 那需要为每一行补一次详情请求。
/// 本切片不做（原型的列表行也只有作者 / 时间 / 短 SHA）。
public struct GitHubRepoCommitEndpoint: Sendable {

    /// 列表页大小（与其余列表一致，§4.4）。
    public static let pageSize = 30

    /// 「某一文件的最近提交」固定只取一条。
    ///
    /// ⚠️ **必须写 `per_page=1`**：决策 #49 靠的就是"只要第一条"。
    /// 不写的话服务端回一页 30 条，为一个副标题多解析 29 条提交
    /// （而目录有 30 项时，这一项差别乘 30 倍）。
    public static let latestCommitPageSize = 1

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    // MARK: - 提交列表

    /// 取一页提交 —— `GET /repos/{o}/{r}/commits?sha={branch}`。
    ///
    /// - Parameters:
    ///   - branch: 看哪条分支的提交历史。`nil` ⇒ 服务端用默认分支。
    ///     ⚠️ 非默认分支上浏览时**必须传**，否则列表与面包屑上的分支名对不上
    ///     （用户会以为是在看 `feature/x`，实际看的是 `main`）。
    ///   - cursor: 上一页的 `nextCursor`（**完整 URL**）；`nil` 取第一页。
    ///     续页直接复用服务端给的地址，不自己拼 `?page=n`（§4.4）。
    ///
    /// - Returns: `Page` 而非裸数组 —— `hasMore` 决定"滚到底还要不要继续加载"，
    ///   丢掉它等于丢掉分页（同 `contributors` 的取舍）。
    public func commits(
        owner: String,
        repo: String,
        branch: String? = nil,
        cursor: URL? = nil
    ) async throws -> Page<CommitListItemDTO> {
        if let cursor {
            return try await client.page(at: cursor, as: CommitListItemDTO.self)
        }
        return try await client.page(
            "repos/\(owner)/\(repo)/commits",
            query: branchQuery(branch) + [
                URLQueryItem(name: "per_page", value: String(Self.pageSize))
            ],
            as: CommitListItemDTO.self,
            rateLimitResource: .core
        )
    }

    // MARK: - 提交详情

    /// 提交详情 —— `GET /repos/{o}/{r}/commits/{sha}`，含 `stats` 与 `files[].patch`。
    ///
    /// ⚠️ `files[].patch` 会在**两种**情况下缺席（二进制 / diff 太大），
    /// 数据层原样带出去、不做判定 —— 分开判是领域层 `FileChange.isBinary` 的事
    /// （两件事的用户出路不同：一个去网页端看不了，一个去网页端看太长）。
    public func commit(owner: String, repo: String, sha: String) async throws -> CommitDetailDTO {
        try await client.get(
            "repos/\(owner)/\(repo)/commits/\(sha)",
            as: CommitDetailDTO.self,
            rateLimitResource: .core
        )
    }

    // MARK: - 某一文件的最近一条提交（决策 #49）

    /// 取「最近一次改动这个路径的提交」—— `GET …/commits?path={p}&sha={ref}&per_page=1`。
    ///
    /// 这是文件树每一行那条副标题的来源。**目录清单里没有这个信息**
    /// （`contents` 的返回项一个提交字段都没有，`git/trees` 也没有，GitHub 没有批量接口）
    /// ⇒ 只能逐条补。带 ETag ⇒ 复访时 304 不计配额。
    ///
    /// - Parameters:
    ///   - path: 文件**或目录**路径（`path` 参数两端都支持）。
    ///   - ref: 看哪条分支上的历史。
    ///     ⚠️ **必须传当前分支**（决策 #49 原文只写了 `path` 与 `per_page`，这里是补全）：
    ///     不带 `sha` 时服务端查的是**默认分支**，于是用户在 `feature/x` 上浏览时，
    ///     每行副标题显示的是 `main` 上的提交 —— 一个"看着很合理、其实属于另一条分支"的错值。
    ///     查当前分支的代价是 0（同一个请求，多一个查询项）。
    ///
    /// - Returns: 最近一条提交；该路径**没有**任何提交时返回 `nil`
    ///   （空仓库 / 刚建的空目录 —— 服务端回 `[]`，这是个正常结果而不是错误）。
    ///
    /// ⚠️ **404 不吞**：这里的 404 意味着"这个 `ref` 或这个路径在服务端不存在"，
    /// 而 §9.4.1 的分支回落**正是靠这个 404 触发**（contents 因 ref 失踪回 404 ⇒
    /// 静默重发一次）。把它吞成 `nil` 会让"分支记忆失效"永远自愈不了。
    public func latestCommit(
        owner: String,
        repo: String,
        path: String,
        ref: String? = nil
    ) async throws -> CommitListItemDTO? {
        let page = try await client.page(
            "repos/\(owner)/\(repo)/commits",
            query: [
                URLQueryItem(name: "path", value: path),
                URLQueryItem(name: "per_page", value: String(Self.latestCommitPageSize))
            ] + branchQuery(ref),
            as: CommitListItemDTO.self,
            rateLimitResource: .core
        )
        return page.items.first
    }

    // MARK: - 内部

    /// `sha` 只在非空时进查询串 —— 不带它才是文档里"用默认分支"的写法。
    private func branchQuery(_ branch: String?) -> [URLQueryItem] {
        guard let branch, !branch.isEmpty else { return [] }
        return [URLQueryItem(name: "sha", value: branch)]
    }
}
