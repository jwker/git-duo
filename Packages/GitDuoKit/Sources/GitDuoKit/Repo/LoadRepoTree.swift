import Foundation
import GitHubAPI

/// 代码浏览的取数：目录清单 + **两段式分支解析**。
///
/// 依据：TECH_SPEC §9.4.1（分支解析）、§9.5（代码浏览）、决策 #55。
///
/// ## ⚠️ 2026-10-14 起它**不再取 README**（用户要求 README 进仓库首页）
///
/// 此前根目录那一趟会**并发**多问一次 `readme` 端点，把结果塞进 `RepoTreePage.readme`
/// —— 于是 README 与"目录"绑在一起，只是因为"仓库根"这个位置顺带有了它。
/// 现在 README 由 `LoadRepoReadme` 单独取（两个首页画它，它们都已经有头部在手
/// ⇒ 比这里少一整套依赖）。本件因此只剩"某条分支下某个目录的清单"这一件事。
///
/// ## ⚠️ 为什么分支解析落在这里而不是视图里
///
/// §9.4.1 那张表是**产品口径**（记忆值失效要回落哪条、要不要重取、什么时候静默重试），
/// 而它的三条规则各自对应一次真实的网络动作。写在 ViewModel 里意味着
/// **App target 没有测试 target** ⇒ 那三条规则一条都守不住
/// （典型症状：删掉一条分支后，进仓库稳定 404 一整帧然后自愈）。
///
/// ## 两段式的形状（决策 #55）
///
/// 1. **立即**用记忆值（无记忆则 `defaultBranch`）发首屏请求 —— 不串行等分支列表；
/// 2. 分支列表回来后校正；**换过分支就重取一次**（那一次的结果才是对的）；
/// 3. 第 1 步若因 `ref` 不存在吃了 404 ⇒ 回落默认分支、**静默重发一次**、不报错。
///
/// 三种情形最终都收敛到"用某个分支取一次目录"，所以第 2、3 步共用同一个重取动作。
public struct LoadRepoTree: Sendable {

    private let contents: any RepoContentsDataSource

    /// 分支列表 —— 只用于第 2 步的校正（`BranchResolver.resolved` 要看"记忆值还在不在"）。
    private let branchSource: any RepoBranchDataSource

    public init(
        contents: any RepoContentsDataSource,
        branches: any RepoBranchDataSource
    ) {
        self.contents = contents
        self.branchSource = branches
    }

    // MARK: - 目录

    /// 取一个路径的目录清单。
    ///
    /// - Parameters:
    ///   - path: 已经过 `RepoPath` 校验的路径（`RepoPath.root` 表示根目录）。
    ///   - remembered: `BranchMemoryStore` 里该仓库的记忆值；没有则 `nil`。
    ///   - defaultBranch: 头部（`RepositoryDetail.defaultBranch`）给的回落值。
    ///
    /// - Throws: 目录请求的错误（含**两次都失败**时的那个）。
    public func load(
        fullName: String,
        path: RepoPath,
        remembered: String?,
        defaultBranch: String
    ) async throws -> RepoTreePage {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)

        // ── 第 1 步：立即用记忆值（无记忆则默认分支）发，不等分支列表。
        var branch = BranchResolver.initial(remembered: remembered, defaultBranch: defaultBranch)
        var fetched: [ContentEntryDTO]
        do {
            fetched = try await fetch(owner: owner, repo: repo, path: path, ref: branch)
        } catch {
            // ── 第 3 步：`ref` 不存在 ⇒ 回落 + 静默重发一次。
            //    ⚠️ 判据里必须有 `attemptedBranch != defaultBranch`（见 `BranchResolver`）：
            //    默认分支自己吃 404 意味着仓库整体不可达，那种情况必须如实报错。
            guard let gitHubError = error as? GitHubError,
                  BranchResolver.shouldSilentlyRetry(
                      after: gitHubError,
                      attemptedBranch: branch,
                      defaultBranch: defaultBranch
                  )
            else { throw error }
            branch = defaultBranch
            fetched = try await fetch(owner: owner, repo: repo, path: path, ref: branch)
        }

        // ── 第 2 步：分支列表回来后校正。
        //
        // ⚠️ 列表失败**有意降级成空数组**（`try?`）：客户端拿不到分支列表 ≠ 仓库没有分支。
        //    `BranchResolver.resolved` 对空列表返回"沿用记忆值"（"无法验证 ≠ 什么都不存在"），
        //    所以这里不是在藏错误，而是**精确地落到"无法验证"那一档**。
        //    把列表失败也当成"记忆值失效"，会在一次网络抖动后清掉用户的记忆值
        //    —— 而清掉是**写盘**的，不会自愈。
        let available = await availableBranches(owner: owner, repo: repo)
        let resolution = BranchResolver.resolved(
            remembered: remembered,
            available: available,
            defaultBranch: defaultBranch
        )

        // 只有**真的换了分支**才重取：沿用记忆值时这一步是空操作。
        if resolution.branch != branch {
            branch = resolution.branch
            fetched = try await fetch(owner: owner, repo: repo, path: path, ref: branch)
        }

        return RepoTreePage(
            branch: branch,
            entries: fetched.map(RepoFileMapper.treeEntry),
            didFallBack: resolution.didFallBack
        )
    }

    /// 第 2 步用的分支名列表。见 `load` 里关于"失败降级成空数组"的说明。
    private func availableBranches(owner: String, repo: String) async -> [String] {
        guard let page = try? await branchSource.branches(owner: owner, repo: repo) else {
            return []
        }
        return page.items.map(\.name)
    }

    /// 一个路径的目录清单。
    ///
    /// ⚠️ **2026-10-14 起它不再顺带取 README**（本地图曾经是"目录 + README 一趟取回"，
    /// 根目录时两路并发）—— README 现在由 `LoadRepoReadme` 单独取，见类型说明。
    /// 连带好处：本函数不再需要知道"这是不是根目录"（原来那个 `path.isRoot` 分支
    /// 存在的唯一理由就是"子目录不问 readme 端点"）。
    private func fetch(
        owner: String,
        repo: String,
        path: RepoPath,
        ref: String
    ) async throws -> [ContentEntryDTO] {
        try await contents.contents(
            owner: owner, repo: repo, path: path.raw, ref: ref
        ).entries
    }

}

/// 一个路径的目录清单与**解析后的分支**。
public struct RepoTreePage: Sendable {

    /// 本次取数实际用的分支 —— 视图的面包屑现实显示它。
    ///
    /// ⚠️ 它可能**不是**传进来的 `remembered`：记忆值已失效时这里已经是回落后的值。
    /// 视图必须用它、不能自己再解析一遍（那就是第二套规则）。
    public let branch: String

    public let entries: [TreeEntry]

    /// 记忆值失效、回落到了默认分支。
    ///
    /// 调用方拿到 `true` 时有一件事必须做：`BranchMemoryStore.forget(fullName:)`。
    /// （"失效该仓库的 contents / commits 缓存"那一半由数据层负责 ——
    /// `compare` / `merge` / `deleteBranch` 的 `invalidating` 已经做了，而纯读路径
    /// **不清缓存**：清掉只会让下一帧多几个请求。）
    public let didFallBack: Bool

    /// ⚠️ **2026-10-14 起本类型没有 `readme` 了** —— README 改由 `LoadRepoReadme`
    /// 单独取（它不再是"某条分支下某个目录"的一部分）。理由见 `LoadRepoTree` 的类型说明。
    public init(
        branch: String,
        entries: [TreeEntry],
        didFallBack: Bool
    ) {
        self.branch = branch
        self.entries = entries
        self.didFallBack = didFallBack
    }

    /// 视图要传给 `CodeSurface` 的行（README 与这里无关，它走 Markdown 渲染）。
    public var isEmptyDirectory: Bool { entries.isEmpty }
}
