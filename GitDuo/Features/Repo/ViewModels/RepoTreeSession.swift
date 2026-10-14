import Foundation
import GitHubAPI
import GitDuoKit

/// 一次「目录浏览」的会话状态 —— 当前分支 + 当前目录那一页 + 分支列表。
///
/// ## 为什么它是一个独立类型，而不是在 ViewModel 里各写一遍
///
/// 它服务**两种仓库**（同一页的两档）：
/// - 自己的仓库（可写）—— §4.4 首页四行入口的第一行；
/// - 他人仓库（只读）—— §4.13 的文件浏览入口行。
///
/// ⚠️ 它**原先还服务两个不同的页面**（§4.4 的「代码」分区与 §4.13 的 ⑤ / ⑥ 分区各一份），
/// 2026-10-14 起两处收进了同一个代码页（走查第 63 条）⇒ 它是一个页面的两档。
///
/// 两档的**取数与状态迁移完全一样**，而且每一条都是"错了不报错"的那一类：
/// 分支两段式解析（决策 #55）、记忆失效后静默回落并重发一次（§9.4.1 第 3 条）、
/// 分支列表按需取（命中 304）。
/// 它们差的是**外壳**：谁推入、点一行去哪里、右上角那颗「⋯」给不给那第二项 ——
/// 那些留在各自的视图里（见 `RepoTreeSection`）。
///
/// 抄一份的代价不是那几十行，而是上面四条规则将来只会改到其中一份：
/// 改了可写那一档的回落、没改只读那一档的，症状是"同一个仓库在两档里点同一行结果不一样"。
///
/// ## ⚠️ 2026-10-14 起它**不取 README**
///
/// README 原先挂在根目录那一页上（`RepoTreePage.readme`）—— 现在它由
/// `LoadRepoReadme` 单独取、画在两个**首页**上（§4.4 四行入口之下 / §4.13 入口行之后）。
/// 本类型因此只剩"某条分支下某个目录的清单"这一件事。
///
/// ## ⚠️ 它**不取头部**
///
/// `defaultBranch` 由调用方传进来：§4.4 从 `LoadRepoDetail` 拿、§4.13 从
/// `LoadRepoInsights` 拿 —— 两边都已经有一份头部在手，本类型再去问一次是白花一个请求。
@MainActor
@Observable
final class RepoTreeSession {

    // MARK: - 状态

    /// 当前目录那一页（含解析后的分支）。
    private(set) var page: LoadState<RepoTreePage> = .idle

    /// 已解析出来的当前分支；`page` 拿到之前为 `nil`。
    private(set) var branch: String?

    /// 分支弹层要的数据。`idle` = 还没打开过。
    private(set) var branchList: LoadState<BranchList> = .idle

    // MARK: - 依赖

    private let loader: LoadRepoTree
    private let branchesLoader: LoadBranches
    private let memory: any BranchMemoryStore

    /// 上一次 `load` 用的默认分支 —— `reload()` 重取时要用它。
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
        } catch {
            page.fail(Self.failure(from: error))
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
    /// ⚠️ 它**不提示、也不动别人的列表** —— 那些是调用方的事。
    /// （原来它还负责"清空同一页上的提交列表"；2026-10-14 提交列表搬去了
    /// `RepoSectionListView` 那一页，改成它自己在进页时按**记忆**重新解析分支。）
    /// 所以这里返回"到底换没换"，让调用方据此决定。
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
