import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 提交详情页（PRD §4.7）的状态。
///
/// ## 它只管取数 —— 展开 / 折叠**不在这里**
///
/// §11.2 的「按需解析」（折叠状态下不解析、展开那一刻才解析该文件）落在
/// **`DiffCard` 自己的 `@State` 里**（6.3 已交付，见该类型的"按需解析"一节）。
/// 本类型**有意不持有一份 `[文件名: [DiffHunk]]`**：那会造出同一件事的第二份实现，
/// 而两份里只有一份会被修。
///
/// 它因此也不需要"刷新后清空解析结果"这一步 —— 卡片在 `patch` 变化时会自己重解析。
@MainActor
@Observable
final class CommitDetailViewModel {

    private(set) var detail: LoadState<CommitDetail> = .idle

    private let loader: LoadRepoCommits
    private let toast: ToastCenter

    let fullName: String
    let sha: String

    /// 只读（他人仓库）—— 决定操作区画 Revert 还是那句页脚（§4.7 的权限差异）。
    let readOnly: Bool

    init(
        fullName: String,
        sha: String,
        readOnly: Bool,
        loader: LoadRepoCommits,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.sha = sha
        self.readOnly = readOnly
        self.loader = loader
        self.toast = toast
    }

    // MARK: - 取数

    func start() async {
        guard !detail.hasFinished else { return }
        await load()
    }

    func refresh() async {
        await load(pullToRefresh: true)
    }

    private func load(pullToRefresh: Bool = false) async {
        let hadContent = detail.value != nil
        if !hadContent { detail.begin() }

        do {
            detail.succeed(try await loader.detail(fullName: fullName, sha: sha))
        } catch {
            // ⚠️ 已有内容时的下拉刷新**不能把整屏变成失败态**（§8.5：
            //    "刷新不遮挡已有内容"）—— 给一条 toast，内容留在屏幕上。
            if hadContent, pullToRefresh {
                // ⚠️ 正本在 `GitDuoKit.RefreshCopy`（切片 7.4 收口）。
                toast.show(RefreshCopy.failed)
            } else {
                detail.fail(Self.failure(from: error))
            }
        }
    }

    // MARK: - 派生

    /// 改动的文件。**顺序即服务端给的顺序**（`files[]`），本层不重排
    /// —— 用户对照 GitHub 网页端时顺序一致才好对。
    var files: [FileChange] { detail.value?.files ?? [] }

    /// 这个提交在网页端的地址 —— **Revert 的唯一出口**。
    ///
    /// ⚠️ 不是 `/revert/{sha}` 那种伪路径：GitHub 的 revert 是提交页上的一个按钮
    /// （`POST` + CSRF + 服务端内部能力），**没有**可以直达它的 URL。
    /// 拼一个看起来对的地址只会得到 404，而那时用户已经在浏览器里了。
    /// 地址形状收在 `RepoWebLinks.commit`。
    ///
    /// ⚠️ 用**完整** SHA 而不是短哈希：短哈希在网页端能用，但完整 SHA 与
    /// `GET /repos/{o}/{r}/commits/{ref}` 的 `ref` 是同一个东西 ——
    /// 我们手上这个 `sha` 就是从那条路由的参数来的，原样带回去最不容易出错。
    var webURL: URL? {
        RepoWebLinks.commit(fullName: fullName, sha: sha)
    }

    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}
