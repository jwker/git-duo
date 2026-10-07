import Foundation
import GitHubAPI

/// 提交的取数：列表（分页）与详情（§4.4 分区四、§4.7）。
///
/// ## ⚠️ 列表与详情**不是同一份数据**
///
/// | | 列表 | 详情 |
/// |---|---|---|
/// | 信息 / 作者 / 时间 | ✅ | ✅ |
/// | `files[]`（含 `patch`） | ❌ | ✅ |
/// | `stats{additions,deletions,total}` | ❌ | ✅ |
///
/// 所以"在列表行上顺手显示 `+12 −4`"是做不到的 —— 那需要为每一行补一次详情请求。
/// 本切片不做（原型的列表行也只有作者 / 时间 / 短 SHA）。
public struct LoadRepoCommits: Sendable {

    private let source: any RepoCommitsDataSource

    public init(source: any RepoCommitsDataSource) {
        self.source = source
    }

    /// 一页提交。
    ///
    /// - Parameter branch: **当前分支**。`nil` 时服务端用的是**默认分支** ——
    ///   在 `feature/x` 上浏览却传 `nil`，会看到另一个分支的历史，
    ///   而界面上的面包屑写着 `feature/x`（一个"看着很合理、其实属于另一条分支"的错值）。
    /// - Parameter cursor: 上一页的 `nextCursor`；`nil` 取第一页。
    public func page(
        fullName: String,
        branch: String?,
        cursor: URL? = nil
    ) async throws -> Page<CommitSummary> {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let page = try await source.commits(
            owner: owner, repo: repo, branch: branch, cursor: cursor
        )
        return page.map(RepoCommitMapper.summary)
    }

    /// 提交详情（含 `files[].patch` 与 `stats`）。
    ///
    /// ⚠️ `patch` 解析走 `UnifiedDiffParser`（§11.2），**在视图展开时才做** ——
    /// 本方法只把 `[FileChange]` 原样带出去（§11.2 的"按需解析"）。
    /// 大 PR 有几百个文件，在取数这一步就全解析会让首屏卡住。
    public func detail(fullName: String, sha: String) async throws -> CommitDetail {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        return RepoCommitMapper.detail(try await source.commit(owner: owner, repo: repo, sha: sha))
    }
}
