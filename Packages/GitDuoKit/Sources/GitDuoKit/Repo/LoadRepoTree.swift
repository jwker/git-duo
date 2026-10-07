import Foundation
import GitHubAPI

/// 代码浏览的取数：目录清单 + README + **两段式分支解析**。
///
/// 依据：TECH_SPEC §9.4.1（分支解析）、§9.5（代码浏览）、决策 #49 / #55。
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

    /// 副标题填充的并发上限。
    ///
    /// ⚠️ **不能全并发**：一个 30 项的目录会瞬间发出 30 个请求，
    /// 而 GitHub 的二级限流（secondary rate limit）正是冲这种形状来的 ——
    /// 被限流之后**整页**都慢下来，代价远大于"慢慢填"。4 是保留序列感的同时
    /// 让 30 项大约 8 个往返完成的折中。
    public static let subtitleConcurrency = 4

    private let contents: any RepoContentsDataSource
    private let commits: any RepoCommitsDataSource

    /// 分支列表 —— 只用于第 2 步的校正（`BranchResolver.resolved` 要看"记忆值还在不在"）。
    private let branchSource: any RepoBranchDataSource

    public init(
        contents: any RepoContentsDataSource,
        commits: any RepoCommitsDataSource,
        branches: any RepoBranchDataSource
    ) {
        self.contents = contents
        self.commits = commits
        self.branchSource = branches
    }

    // MARK: - 第一趟：目录 + README

    /// 取一个路径的目录清单（根目录另附 README）。
    ///
    /// - Parameters:
    ///   - path: 已经过 `RepoPath` 校验的路径（`RepoPath.root` 表示根目录）。
    ///   - remembered: `BranchMemoryStore` 里该仓库的记忆值；没有则 `nil`。
    ///   - defaultBranch: 头部（`RepositoryDetail.defaultBranch`）给的回落值。
    ///
    /// - Throws: 目录请求的错误（含**两次都失败**时的那个）。⚠️ README 的 404
    ///   不会抛 —— 它在端点里已被翻译成 `nil`（§9.5：唯一允许吞 404 的一处）。
    public func load(
        fullName: String,
        path: RepoPath,
        remembered: String?,
        defaultBranch: String
    ) async throws -> RepoTreePage {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)

        // ── 第 1 步：立即用记忆值（无记忆则默认分支）发，不等分支列表。
        var branch = BranchResolver.initial(remembered: remembered, defaultBranch: defaultBranch)
        var fetched: (entries: [ContentEntryDTO], readme: String?)
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
            entries: fetched.entries.map(RepoFileMapper.treeEntry),
            // ⚠️ 解析在**这里**做一次，不在视图的 `body` 里（见 `MarkdownDocument`）：
            //    放进 body 是每次重绘重扫全文，而结果每次都相同。
            readme: fetched.readme.map(MarkdownDocument.init),
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

    /// 目录 + README 一趟取回（根目录两路并发）。
    private func fetch(
        owner: String,
        repo: String,
        path: RepoPath,
        ref: String
    ) async throws -> (entries: [ContentEntryDTO], readme: String?) {
        async let payloadTask = contents.contents(
            owner: owner, repo: repo, path: path.raw, ref: ref
        )

        guard path.isRoot else {
            // ⚠️ 非根目录**不取 README**：`readme` 端点找的是仓库级的 README，
            //    在任何子目录下问它都会拿到同一份（那不是"这个目录的说明"）。
            return (try await payloadTask.entries, nil)
        }

        async let readmeTask = contents.readme(owner: owner, repo: repo, ref: ref)
        let (payload, readme) = try await (payloadTask, readmeTask)
        return (payload.entries, readme)
    }

    // MARK: - 第二趟：逐条补副标题（决策 #49）

    /// 逐条取「最近一次改动该路径的提交」，**取到一条回调一条**。
    ///
    /// 目录清单里没有这个信息，也没有任何批量接口能把它带出来 ⇒ 只能逐条补。
    /// 决策 #49 要求"副标题随请求陆续填充、不阻塞文件列表先出"，
    /// 所以本方法是**流式**的：`onEach` 每收到一条就被调一次，
    /// 调用方据此就地更新那一行（而不是等全部回来再一次性刷新）。
    ///
    /// - Parameters:
    ///   - onEach: `(路径, 最近提交)`，路径是仓库内**完整**路径（`RepoPath.raw`）。
    ///   - onRefMissing: 某一条吃了 **404** 时被调**一次**，随后**整趟中止**。
    ///
    ///     ⚠️ 为什么 404 要中止而不是"跳过这一条"：这里的 404 意味着
    ///     **当前 `ref` 在服务端不存在**（§9.4.1 明写：与回落相关的请求都不许把 404
    ///     吞成空值）。继续问下去只会拿到剩下全部条目的 404，
    ///     而"静默空白"会让分支回落**永远不被触发**。交回调用方重解析分支才是对的。
    ///
    /// - Note: 单条的网络 / 配额失败（**不是 404**）只是这一条留空，
    ///   不中止整趟 —— 一个副标题取不到不该让另外 29 行也跟着不显示。
    public func loadSubtitles(
        fullName: String,
        ref: String,
        paths: [RepoPath],
        onEach: @Sendable (String, RecentCommit) async -> Void,
        onRefMissing: @Sendable () async -> Void
    ) async {
        guard let (owner, repo) = try? RepositoryMapper.splitFullName(fullName) else { return }
        guard !paths.isEmpty else { return }

        await withTaskGroup(of: SubtitleOutcome.self) { group in
            var next = 0

            // ⚠️ 这里**不能**抽成嵌套函数：`withTaskGroup` 的 body 拿到的是 `inout` 的
            //    group，而嵌套函数（以及逃逸闭包）不允许捕获 `inout` 参数。
            //    所以"发起一条"抽成了 `Self.fetchSubtitle`（它不碰 group），
            //    两处调度各写一遍 —— 只有三行。
            while next < paths.count, next < Self.subtitleConcurrency {
                let path = paths[next]
                next += 1
                group.addTask {
                    await Self.fetchSubtitle(
                        commits: commits, owner: owner, repo: repo, path: path, ref: ref
                    )
                }
            }

            while let outcome = await group.next() {
                switch outcome {
                case let .found(path, commit):
                    await onEach(path, commit)
                case .missing, .failed:
                    // 该路径没有提交（正常）／这一条取不到（留空）：都不打断其余条目。
                    break
                case .refMissing:
                    group.cancelAll()
                    await onRefMissing()
                    return
                }
                if next < paths.count {
                    let path = paths[next]
                    next += 1
                    group.addTask {
                        await Self.fetchSubtitle(
                            commits: commits, owner: owner, repo: repo, path: path, ref: ref
                        )
                    }
                }
            }
        }
    }

    /// 一条副标题的请求与归一化（不碰 `TaskGroup`，见 `loadSubtitles` 的说明）。
    private static func fetchSubtitle(
        commits: any RepoCommitsDataSource,
        owner: String,
        repo: String,
        path: RepoPath,
        ref: String
    ) async -> SubtitleOutcome {
        do {
            let dto = try await commits.latestCommit(
                owner: owner, repo: repo, path: path.raw, ref: ref
            )
            guard let dto else { return .missing(path.raw) }
            return .found(path.raw, RepoFileMapper.recentCommit(dto))
        } catch {
            // ⚠️ 只有 404 算"ref 失效"；其余（断网 / 配额 / 5xx）是**这一条**的事。
            if case GitHubError.notFound = error { return .refMissing }
            return .failed(path.raw)
        }
    }

    /// 一条副标题的四种结局。
    ///
    /// ⚠️ 四档而不是 `RecentCommit?`：`nil` 会把"这个路径没有提交"（正常）
    /// 与"这一条请求失败了"（异常）合成同一个结果，而两者对调用方的含义不同 ——
    /// 前者什么都不用做，后者是**一次被吞掉的失败**。
    private enum SubtitleOutcome: Sendable {
        case found(String, RecentCommit)
        case missing(String)
        case refMissing
        case failed(String)
    }
}

/// 一个路径的目录清单（根目录另附 README）与**解析后的分支**。
public struct RepoTreePage: Sendable {

    /// 本次取数实际用的分支 —— 视图的面包屑现实显示它。
    ///
    /// ⚠️ 它可能**不是**传进来的 `remembered`：记忆值已失效时这里已经是回落后的值。
    /// 视图必须用它、不能自己再解析一遍（那就是第二套规则）。
    public let branch: String

    public let entries: [TreeEntry]

    /// README（原文 + 已解析的块）；`nil` = 这个仓库没有 README，或当前不在根目录。
    ///
    /// ⚠️ 解析（`MarkdownParser`，§11.1）**在取数那一层已经做完** —— 视图拿到的是
    /// 可以直接渲染的块，不必（也不该）在 `body` 里再解析一次。
    public let readme: MarkdownDocument?

    /// 记忆值失效、回落到了默认分支。
    ///
    /// 调用方拿到 `true` 时有一件事必须做：`BranchMemoryStore.forget(fullName:)`。
    /// （"失效该仓库的 contents / commits 缓存"那一半由数据层负责 ——
    /// `compare` / `merge` / `deleteBranch` 的 `invalidating` 已经做了，而纯读路径
    /// **不清缓存**：清掉只会让下一帧多几个请求。）
    public let didFallBack: Bool

    public init(
        branch: String,
        entries: [TreeEntry],
        readme: MarkdownDocument?,
        didFallBack: Bool
    ) {
        self.branch = branch
        self.entries = entries
        self.readme = readme
        self.didFallBack = didFallBack
    }

    /// 视图要传给 `CodeSurface` 的行（README 与这里无关，它走 Markdown 渲染）。
    public var isEmptyDirectory: Bool { entries.isEmpty }

    /// 换掉条目列表（副标题陆续填充时用）—— 理由同 `TreeEntry.withRecentCommit`。
    public func replacingEntries(_ entries: [TreeEntry]) -> RepoTreePage {
        RepoTreePage(
            branch: branch,
            entries: entries,
            readme: readme,
            didFallBack: didFallBack
        )
    }
}
