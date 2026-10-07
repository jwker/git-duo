import Foundation
import GitHubAPI
import GitDuoKit

/// 探索 Issue / PR 两个二级列表共用的状态机（PRD §4.14 / §4.15、TECH_SPEC §8.5）。
///
/// ## 为什么两页共用一个泛型 ViewModel
///
/// 两页除"取什么"之外完全同构：分页状态机 · 滚到底自动加载 · 下拉刷新 ·
/// 首屏失败 · 底部重试行。写两份的下场是**两处的守卫条件迟早不一样**
/// （例如一处漏了 `canLoadMore`，于是滚到底会无限重复请求同一页，而屏幕上
/// 只是"转圈消失了又出现"），而那种偏差点几下是看不出来的。
///
/// 差异全部留在两侧，本类型一概不碰：
/// - **取数规则** —— `LoadRepoIssues` 滤掉混进来的 PR、`LoadRepoPulls` 滤掉已关闭未合并
///   （两边规则不同，见 `LoadRepoPulls` 的对照表）；
/// - **文案** —— 说明行 / 空态 / 页脚各由领域层的 `OpenIssueIndicator` /
///   `PullListIndicator` 提供（本类型不认识任何一个字）。
///
/// ## 它只管状态，不管内容
///
/// `rows` / `loadedCount` / `hasMore` 都是 `PagedListState` 的转发 ——
/// 分页那套规则（去重、`hasLoaded`、失败不清游标）在领域层被单测守着，
/// 这里只负责"把用户动作翻成对它的调用 + 发请求"。
@MainActor
@Observable
final class RepoSubListViewModel<Item: Identifiable & Sendable> {

    /// 取一页：`(仓库全名, 上一页游标) -> 一页`。
    ///
    /// 收闭包而不是收协议，是因为两边的取数类型（`LoadRepoIssues` / `LoadRepoPulls`）
    /// 没有共同超类型，而它们的 `load(fullName:cursor:)` 签名恰好一致 ——
    /// 为此现造一个协议只会多一处需要跟着改的地方。
    private let loadPage: @Sendable (String, URL?) async throws -> Page<Item>

    private var state = PagedListState<Item>()

    /// 当前仓库全名。由 `start(fullName:)` 记下 —— 它同时也是"本页是谁"的唯一副本。
    private var fullName = ""

    init(loadPage: @escaping @Sendable (String, URL?) async throws -> Page<Item>) {
        self.loadPage = loadPage
    }

    // MARK: - 供视图读取

    var rows: [Item] { state.items }

    /// 主区域的渲染形态（骨架 / 内容 / 空态 / 失败，四者可辨 —— §8.5）。
    var content: PagedListContent { state.content() }

    var isLoading: Bool { state.isLoading }

    /// 最近一次失败。**与 `rows` 并存** —— 有内容时它只驱动底部的重试行（§8.5）。
    var error: GitHubError? { state.error }

    /// 已加载的条数。Issues 的说明行 `开放 {N} 个` 用它 ——
    /// ⚠️ **不是**服务端那个"开放 Issue 数"（它把 PR 也算作 Issue，会比屏幕上多，见 §4.14）。
    var loadedCount: Int { state.items.count }

    /// 还有下一页 ⇒ 计数要写成 `30+`（**下界，不是确数**，§4.14）。
    var hasMore: Bool { state.canLoadMore }

    // MARK: - 生命周期

    /// 进页取数。**只在没加载过时发请求** —— 返回上层再进来不该重打一遍。
    func start(fullName: String) async {
        self.fullName = fullName
        guard !state.hasLoaded else { return }
        await perform(reset: false)
    }

    /// 滚到底自动加载 / 底部「重试」。
    func loadMore() async {
        guard state.canLoadMore, !state.isLoading else { return }
        await perform(reset: false)
    }

    /// 下拉刷新：重取第一页。
    func refresh() async {
        await perform(reset: true)
    }

    // MARK: - 内部

    /// - Parameter reset: `true` = 下拉刷新（整体替换，且**从第一页取**）。
    private func perform(reset: Bool) async {
        // ⚠️ 一次只允许一发在途。
        //
        // 没有这道守卫时，`refresh()` 与滚到底触发的 `loadMore()` 会在同一个 `await`
        // 点上交错：两发各自 `beginLoad`，然后**后返回的那发覆盖先返回的**
        // —— 表现是"下拉刷新之后列表少了一半"，而它看起来完全正常（有内容、不报错、
        // 分页行也在）。
        //
        // 代价是连点的第二发被静默跳过（`.refreshable` 的下拉指示器仍会转一下）。
        // 这比"两发结果互相覆盖"好：前者只是没反应，后者是**数据出错**。
        guard !state.isLoading else { return }

        // ⚠️ 游标要在 `beginLoad` **之前**读，且刷新时必须取 `nil`。
        //
        // `PagedListState.beginLoad` 有意**不动** `nextCursor`（刷新失败时那个游标还有效，
        // 清掉它等于一次刷新失败就让用户永远失去"加载更多"）。所以刷新如果照读游标，
        // 就变成了"下拉刷新 = 取下一页"，而列表会越刷新越长 —— 且长出来的是重复内容。
        let cursor = reset ? nil : state.nextCursor

        var working = state
        working.beginLoad(reset: reset)
        state = working

        do {
            let page = try await loadPage(fullName, cursor)
            var latest = state
            latest.received(page)
            state = latest
        } catch {
            var latest = state
            latest.failed(Self.failure(from: error))
            state = latest
        }
    }

    /// 把任意错误收敛成 `GitHubError`（同其余 ViewModel 的口径：
    /// 映射失败归 `.decoding`，**不是** `.transport` —— 后者会谎称网络问题、
    /// 给出"检查网络"的错误引导）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}
