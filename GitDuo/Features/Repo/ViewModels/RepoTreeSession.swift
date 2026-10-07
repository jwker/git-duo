import Foundation
import GitHubAPI
import GitDuoKit

/// 一次「目录浏览」的会话状态 —— 当前分支 + 当前目录那一页 + 分支列表 + 副标题补填。
///
/// ## 为什么它是一个独立类型，而不是两个 ViewModel 里各写一遍
///
/// 它服务**两个页面**：
/// - §4.4「代码」分区（自己的仓库，可写）；
/// - §4.13 第 ⑤ / ⑥ 分区「文件浏览 · README」（他人仓库，只读）。
///
/// 两者的**取数与状态迁移完全一样**，而且每一条都是"错了不报错"的那一类：
/// 分支两段式解析（决策 #55）、记忆失效后静默回落并重发一次（§9.4.1 第 3 条）、
/// 副标题逐条补填 + 404 中止整趟（决策 #49）、分支列表按需取（命中 304）。
/// 它们差的是**外壳**：谁推入、点一行去哪里、面包屑右边有没有「＋ 添加」——
/// 那些留在各自的视图里（见 `RepoTreeSection`）。
///
/// 抄一份的代价不是那几十行，而是上面四条规则将来只会改到其中一份：
/// 改了 §4.4 的回落、没改 §4.13 的，症状是"同一个仓库在两页里点同一行结果不一样"。
///
/// ## ⚠️ 它**不取头部**
///
/// `defaultBranch` 由调用方传进来：§4.4 从 `LoadRepoDetail` 拿、§4.13 从
/// `LoadRepoInsights` 拿 —— 两边都已经有一份头部在手，本类型再去问一次是白花一个请求。
@MainActor
@Observable
final class RepoTreeSession {

    // MARK: - 状态

    /// 当前目录那一页（含解析后的分支与 README）。
    private(set) var page: LoadState<RepoTreePage> = .idle

    /// 已解析出来的当前分支；`page` 拿到之前为 `nil`。
    private(set) var branch: String?

    /// 分支弹层要的数据。`idle` = 还没打开过。
    private(set) var branchList: LoadState<BranchList> = .idle

    // MARK: - 依赖

    private let loader: LoadRepoTree
    private let branchesLoader: LoadBranches
    private let memory: any BranchMemoryStore

    /// 上一次 `load` 用的默认分支 —— 记忆失效要回落到它（见 `handleRefMissing`）。
    private var defaultBranch: String?

    let fullName: String

    /// 本次查看的目录 —— 由路由决定，**进页后不再变**（换目录走 push 一层新页面）。
    let path: RepoPath

    init(
        fullName: String,
        path: RepoPath,
        loader: LoadRepoTree,
        branches: LoadBranches,
        memory: any BranchMemoryStore
    ) {
        self.fullName = fullName
        self.path = path
        self.loader = loader
        self.branchesLoader = branches
        self.memory = memory
    }

    // MARK: - 取目录

    /// 取当前目录。调用方在**头部到手之后**调它（理由见类型说明）。
    func load(defaultBranch: String) async {
        self.defaultBranch = defaultBranch
        page.begin()

        // ⚠️ 记忆值在这里读、不在别处缓存：用户可能刚从分支弹层切过分支，
        //    而那次切换已经写过记忆。缓存一份会让"切完再进同一目录"用回旧值。
        let remembered = await memory.branch(for: fullName)

        do {
            let value = try await loader.load(
                fullName: fullName,
                path: path,
                remembered: remembered,
                defaultBranch: defaultBranch
            )
            page.succeed(value)
            branch = value.branch

            // 记忆值失效 ⇒ 清掉它（§9.4.1 表第二行）。
            // ⚠️ **不报错、不提示**：回落是设计里"被无声吸收"的那一类，
            //    用户看到的是"还是打开了，只是回到了默认分支"—— 那正是要的结果。
            if value.didFallBack { await memory.forget(fullName: fullName) }

            // ⚠️ **起一个独立任务，不 `await`** —— 决策 #49 要求"副标题随请求陆续填充、
            //    不阻塞列表先出"。`page.succeed(value)` 上面已经写过了，所以列表此刻
            //    就能渲染；若在这里 `await`，那几十个补请求全部回来之前
            //    `load` 不会返回 ⇒ **下拉刷新的圈会一直转**（而内容早就出来了）。
            Task { [weak self] in await self?.fillSubtitles(value) }
        } catch {
            page.fail(Self.failure(from: error))
        }
    }

    /// 第二趟：逐条补副标题（决策 #49）。**取到一条更新一行**。
    private func fillSubtitles(_ value: RepoTreePage) async {
        let paths = value.entries.map(\.path)
        guard !paths.isEmpty else { return }

        let snapshotBranch = value.branch
        await loader.loadSubtitles(
            fullName: fullName,
            ref: snapshotBranch,
            paths: paths,
            onEach: { [weak self] raw, commit in
                await MainActor.run { self?.applySubtitle(path: raw, commit: commit) }
            },
            onRefMissing: { [weak self] in
                // 当前分支在服务端不存在了（§9.4.1 第 3 条）⇒ 重解析一次。
                // 记忆被清掉之后，下一次 `load` 会走 `initial` ⇒ 拿默认分支。
                await MainActor.run { self?.handleRefMissing() }
            }
        )
    }

    private func applySubtitle(path raw: String, commit: RecentCommit) {
        guard let value = page.value,
              let index = value.entries.firstIndex(where: { $0.path.raw == raw })
        else { return }

        var entries = value.entries
        entries[index] = entries[index].withRecentCommit(commit)
        page.succeed(value.replacingEntries(entries))
    }

    private func handleRefMissing() {
        guard let current = branch, let fallback = defaultBranch else { return }
        // 已经在默认分支上了 ⇒ 再落一次只会无限循环（`load` 又会触发这一支）。
        guard current != fallback else { return }
        branch = fallback
        Task { [weak self] in
            guard let self else { return }
            await self.memory.forget(fullName: self.fullName)
            await self.load(defaultBranch: fallback)
        }
    }

    /// 重新取当前目录 —— 用最近一次拿到的默认分支。
    ///
    /// 给分区里的「重试」用。⚠️ 一次都没得过 `defaultBranch` 时是**空操作**：
    /// 那种情况下这一块还是骨架屏（没有重试按钮可点）。
    func reload() async {
        guard let defaultBranch else { return }
        await load(defaultBranch: defaultBranch)
    }

    // MARK: - 分支

    /// 打开切换弹层时取分支列表。
    ///
    /// ⚠️ 这次请求**几乎总是命中缓存**：`load` 解析分支时刚问过同一个地址
    /// （§9.4.1 明写"校验不额外消耗请求"）⇒ 条件请求命中 304、不计配额。
    func loadBranches() async {
        guard !branchList.isLoading else { return }
        if branchList.value == nil { branchList.begin() }
        do {
            branchList.succeed(try await branchesLoader.load(fullName: fullName))
        } catch {
            branchList.fail(Self.failure(from: error))
        }
    }

    /// 切到另一条分支 —— 写记忆 + 重取目录。
    ///
    /// ⚠️ 它**不提示、也不动别人的列表**（§4.4 还要清空已加载的提交列表）——
    /// 那些是调用方的事。所以这里返回"到底换没换"，让调用方据此决定。
    ///
    /// - Returns: 真的换了分支才 `true`（点当前那一条时 `false`）。
    @discardableResult
    func switchBranch(to name: String, defaultBranch: String) async -> Bool {
        guard name != branch else { return false }
        await memory.remember(branch: name, for: fullName)
        branch = name
        await load(defaultBranch: defaultBranch)
        return true
    }

    // MARK: - 面包屑

    /// 面包屑上某一层对应的路径。`nil` = 下标越界（调用方据此不跳）。
    func path(upTo index: Int) -> RepoPath? {
        guard index >= 0, index < path.components.count else { return nil }
        return RepoPath(path: path.components.prefix(index + 1).joined(separator: "/"))
    }

    // MARK: - 错误归一化

    /// 把任意错误收敛成 `GitHubError`（同其余 ViewModel：映射失败归 `.decoding`，
    /// **不是** `.transport` —— 后者会让界面给出"检查网络"的错误引导）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}
