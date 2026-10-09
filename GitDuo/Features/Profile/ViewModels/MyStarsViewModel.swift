import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 「我的 Star」页的状态（PRD §4.18、TECH_SPEC §9.14）。
///
/// ## 它管两件节奏不同的事
///
/// | | 数据 | 何时 |
/// |---|---|---|
/// | 列表 | `GET /user/starred`（**复用切片 3 就有的 `listStarred`**） | 进页 / 滚到底 / 下拉刷新 |
/// | 单行 Star 切换 | `DELETE /user/starred/{o}/{r}` | 用户点那一行右侧的按钮 |
///
/// ## ⚠️⚠️ 这一页的 Star「基准」**来自列表本身**，不再补一次查询
///
/// 决策 #41 的要害是「`±1` 之前必须知道**操作前的状态**」—— 不加这一步，
/// 一个本来就已经 Star 过的仓库会按"未 Star"起手，点一下会显示成"新增一颗"。
///
/// 而这一页的数据源就是 `GET /user/starred`：**进得来的每一条都必然是已 Star 的**。
/// 那个状态由数据源本身给出，不是猜的 ⇒ `StarState(baselineConfirmed: true)`
/// **不是绕过决策 #41，而是它的一种情形**（"基准已经知道了"）。
///
/// 代价与收益都如实记在这里：每取消一颗 **1 次请求**（`DELETE`），
/// 而不是 `ExploreRepoViewModel` 那两处（进页先 `GET` 确认基准、点击再 `DELETE`）。
///
/// ## ⚠️ 取消 Star 之后这一行**不消失**
///
/// PRD §4.18 逐字：「成功后按钮变回「Star」、Star 数 −1；失败则回滚并提示，
/// 不留半截状态」—— 它说的是"就地改文案"，不是"把这一行移掉"。
/// 所以改动记在 `toggled` 里，列表本身不动：
/// 点掉一行就让它当场消失，会让人怀疑"我是不是误删了什么"，
/// 而按钮变回「Star」既说明了结果、也留了后悔的余地（再点一下就是重新 Star）。
@MainActor
@Observable
final class MyStarsViewModel {

    /// 累计的 Starred 仓库（**未过滤** —— 过滤在展示时现算）。
    private var state = PagedListState<Repository>()

    /// 本页**改过**的那几行（仓库全名 → 切换后的状态）。
    ///
    /// ⚠️ 只有被点过的行才在这里 —— 默认值由 `starState(of:)` 从列表条目现算，
    /// 而不是在这里预填一份"我看到过的全部状态"（那是第二份真相，刷新后必然不同步）。
    private var toggled: [String: StarState] = [:]

    /// 正在切换的那几行（按钮内联 loading + 禁用，§8.5「操作类」）。
    private(set) var toggling: Set<String> = []

    private let loader: LoadRepositoriesPage
    private let starToggle: ToggleStar
    private let toast: ToastCenter

    init(loader: LoadRepositoriesPage, starToggle: ToggleStar, toast: ToastCenter) {
        self.loader = loader
        self.starToggle = starToggle
        self.toast = toast
    }

    // MARK: - 供视图读取

    /// 屏幕上要画的条目（已按 PRD §4.18 滤掉私有仓库）。
    var items: [Repository] { state.items.filter(Self.isListable) }

    var content: PagedListContent {
        // ⚠️ 判断"有没有内容"必须基于**过滤后**的结果（同 `RepoListViewModel`）：
        //    只拉到私有仓库时 `items` 非空，而屏幕上一条都不该有。
        state.content(matching: { Self.isListable($0) })
    }

    var isLoading: Bool { state.isLoading }

    /// 最近一次失败。**与 `items` 并存** —— 有内容时它只驱动底部的重试行。
    var error: GitHubError? { state.error }

    var canLoadMore: Bool { state.canLoadMore }

    /// 某一行现在该显示什么（按钮文案 + 星数）。
    ///
    /// 没被点过 ⇒ 由**列表条目**现算（它就是已 Star，见类型说明）。
    func starState(of repository: Repository) -> StarState {
        toggled[repository.fullName] ?? StarState(
            fullName: repository.fullName,
            isStarred: true,
            starCount: repository.starCount,
            baselineConfirmed: true
        )
    }

    func isToggling(_ repository: Repository) -> Bool {
        toggling.contains(repository.fullName)
    }

    // MARK: - 用户动作

    /// 首次出现时按需加载。
    func loadIfNeeded() async {
        guard !state.hasLoaded else { return }
        await load(reset: false)
    }

    /// 下拉刷新：重新取第一页并**整体替换**。
    ///
    /// ⚠️ 顺带丢掉本页记的那几行改动 —— 刷新之后服务端的答案才是真的，
    /// 留着本地覆盖会让"我刚 Star 回来的那个仓库"显示成未 Star。
    func refresh() async {
        toggled.removeAll()
        await load(reset: true)
    }

    /// 滚到底自动加载（PRD §4.18：与仓库页同规矩，**与搜索页的「加载更多」有意不同**）。
    func loadMore() async {
        guard state.canLoadMore, !state.isLoading else { return }
        await load(reset: false)
    }

    /// 取消 / 恢复某一行。
    ///
    /// ⚠️ 失败**不改动任何计数**（`ToggleStar.toggle` 保证这一点），按钮恢复可点
    /// （`defer` 收起 loading），并给一条提示 —— 与 `ExploreRepoViewModel.toggleStar` 同口径。
    func toggleStar(_ repository: Repository) async {
        let fullName = repository.fullName
        guard !toggling.contains(fullName) else { return }

        toggling.insert(fullName)
        defer { toggling.remove(fullName) }

        do {
            let (next, action) = try await starToggle.toggle(starState(of: repository))
            toggled[fullName] = next
            toast.show(StarCopy.toast(for: action))
        } catch {
            toast.show(ActionCopy.failed)
        }
    }

    // MARK: - 内部

    /// ⚠️ **只列非私有仓库**（PRD §4.18 / TECH_SPEC §9.14）：私有 Star 属于
    /// "我在关注什么"，而且那些仓库对当前令牌可能已不可访问。
    ///
    /// 判定**复用「公开」那一段**（`RepoListSegment.publicOnly.matches`）而不是
    /// 在这里再写一遍 `!isPrivate`：那条规则只有一个实现，两处各写一份时
    /// 改了一处就会让"公开"与"我的 Star"两个列表对同一个仓库给出不同答案。
    private static func isListable(_ repository: Repository) -> Bool {
        RepoListSegment.publicOnly.matches(repository)
    }

    private func load(reset: Bool) async {
        guard !state.isLoading else { return }

        // 只有刷新才从头取；其余一律接着上次的游标。
        let cursor = reset ? nil : state.nextCursor
        state.beginLoad(reset: reset)

        do {
            state.received(try await loader.load(source: .starred, cursor: cursor))
        } catch {
            state.failed(Self.failure(from: error))
        }
    }

    /// 把任意错误收敛成 `GitHubError`（同其余 ViewModel 的口径：
    /// 映射失败归 `.decoding`，**不是** `.transport`）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}
