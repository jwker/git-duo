import Foundation
import GitHubAPI

/// 删除一个文件 —— §9.6.5，`DELETE /repos/{o}/{r}/contents/{path}`。
///
/// ## ⚠️ 为什么 `sha` 要**现取**
///
/// 官方要求 `message` 与 `sha` **两个都必填**（决策 #66②）。而这里的 `sha`
/// 与 `SaveFile` 里那个**性质不同**：
///
/// - `SaveFile` 的 `sha` 是**乐观锁的基准**（用户读到的那一版）⇒ 必须是旧值，才拦得住并发改动；
/// - 删除**没有"用户手上的那一版"**这回事 —— 用户要的是"这个路径从我眼前消失"，
///   拿他读到的那一版去删反而会把"别人刚改过"变成一次失败（而那个改动马上也要被删掉）。
///
/// 所以这里是**现取**（PRD §5.17 明写"删除前要现取一次版本标识，这一步对用户不可见"）。
/// 它顺带回答了"这个文件还在不在" —— 而那个答案**不是一条错误**：
/// 文件已经被别人删掉时，用户想要的结果本来就已经成立 ⇒ `.alreadyGone`。
public struct DeleteFile: Sendable {

    private let contents: any RepoContentsDataSource
    private let files: any RepoFileWriteDataSource

    public init(contents: any RepoContentsDataSource, files: any RepoFileWriteDataSource) {
        self.contents = contents
        self.files = files
    }

    /// - Parameters:
    ///   - path: 要删的路径。
    ///   - message: 提交信息（空则用默认信息 —— 删除没有输入框，`CommitMessageDefaults`）。
    ///   - branch: 在哪条分支上删（恒传，决策 #65）。
    ///
    /// - Returns: `.deleted` / `.alreadyGone`。
    /// - Throws: 除了"源文件已经不在了"之外的失败。
    ///   ⚠️ 404 **不抛**：PRD §5.17 明写这一档提示"该文件已不存在"，**不报"删除失败"**。
    public func run(
        fullName: String,
        path: RepoPath,
        message: String?,
        branch: String
    ) async throws -> DeleteFileOutcome {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)

        // ── 现取 sha（对用户不可见）。这一步同时是"还在不在"的判据。
        let payload: RepoFileDTO?
        do {
            payload = try await contents.contents(
                owner: owner, repo: repo, path: path.raw, ref: branch
            ).file
        } catch {
            guard let githubError = error as? GitHubError else { throw error }
            if case .notFound = githubError { return .alreadyGone }
            throw githubError
        }

        guard let payload else {
            // 这个 path 上已经不是文件了（目录 / 形状变了）。
            // 对用户而言这正是"那个文件不在了"，而 DELETE 一个目录会 422 ——
            // 与其发出去再解释 422，不如就地给这个准确的结论。
            return .alreadyGone
        }

        // ── 真的删。
        try await files.deleteFile(
            owner: owner,
            repo: repo,
            path: path.raw,
            message: CommitMessageDefaults.resolved(message),
            sha: payload.sha,
            branch: branch
        )
        return .deleted
    }
}

/// 删除的两个结局。
///
/// ⚠️ 只有两档，而且 `.alreadyGone` **不是错误**（PRD §5.17）。
/// 刻意**不加**一个"删除失败"档：真正的失败（403 / 配额 / 断网）都该抛出去、
/// 由 `GitHubError` 说清楚，在这里造一个笼统的失败档会把那些原因一起盖住。
public enum DeleteFileOutcome: Sendable, Equatable {

    case deleted

    /// 现取 `sha` 时发现它已经不在了（别人先删了 / 分支已经不是那条了）。
    case alreadyGone
}
