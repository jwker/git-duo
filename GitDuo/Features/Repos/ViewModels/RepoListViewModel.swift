import Foundation
import GitHubAPI
import GitDuoKit

/// 仓库列表页的状态（PRD §4.3 / TECH_SPEC §4.4、§9.3）。
///
/// ## 它只做三件事
///
/// 1. 持有一份 **`PagedListState`**（状态机在 `GitDuoKit`，因此可被单测覆盖 —— App target 没有测试 target）；
/// 2. 把用户动作翻成 `LoadRepositoriesPage` 的调用；
/// 3. 按当前分段现算可见条目（§9.3 的"本地过滤"）。
///
/// **它不认识 SwiftUI，也不认识路由**：视图拿 `visibleItems` 渲染，点哪一行由视图决定。
@MainActor
@Observable
final class RepoListViewModel {

    /// 当前选中的分段。改动请走 `select(_:)` —— 它负责"该段还没数据时补一次请求"。
    private(set) var segment: RepoListSegment = .all

    /// 「我的仓库」这份累计（§9.3：全部 / 公开 / 私有三段共用）。
    private var reposState = PagedListState<Repository>()

    /// 「Starred」这份累计（§9.3：另一份数据源，独立分页）。
    private var starredState = PagedListState<Repository>()

    private let loader: LoadRepositoriesPage

    init(loader: LoadRepositoriesPage) {
        self.loader = loader
    }

    // MARK: - 供视图读取

    /// 当前分段下可见的条目。
    var visibleItems: [Repository] {
        currentState.visibleItems(segment: segment)
    }

    /// 主区域的渲染形态（骨架 / 内容 / 继续加载 / 空态 / 失败）。
    var content: PagedListContent {
        currentState.content(segment: segment)
    }

    var isLoading: Bool { currentState.isLoading }

    var canLoadMore: Bool { currentState.canLoadMore }

    /// 最近一次失败。**与 `visibleItems` 并存** —— 有内容时它只驱动底部的重试行。
    var error: GitHubError? { currentState.error }

    // MARK: - 用户动作

    /// 首次出现时按需加载。
    ///
    /// ⚠️ 已经有数据的分段**不重新请求**（§9.3【已定】）—— 切段只是换过滤条件。
    func loadIfNeeded() async {
        guard !currentState.hasLoaded else { return }
        await load(reset: false)
    }

    /// 下拉刷新：重新取第一页并**整体替换**。
    func refresh() async {
        await load(reset: true)
    }

    /// 「加载更多」/ 滚到底自动加载。
    ///
    /// 空列表时的自动加载永远不会被触发（没有可滚的内容），
    /// 所以那种情况由视图渲染一个显式的「继续加载」按钮 —— 见 `PagedListContent.needsMore`。
    func loadMore() async {
        guard currentState.canLoadMore, !currentState.isLoading else { return }
        await load(reset: false)
    }

    /// 切换分段。若该段所属的数据源还没拉过（例如首次进入 Starred），补一次请求。
    func select(_ newSegment: RepoListSegment) async {
        guard newSegment != segment else { return }
        segment = newSegment
        await loadIfNeeded()
    }

    // MARK: - 内部

    private var currentState: PagedListState<Repository> {
        state(for: segment.source)
    }

    private func state(for source: RepoListSource) -> PagedListState<Repository> {
        switch source {
        case .repos: reposState
        case .starred: starredState
        }
    }

    private func store(_ newState: PagedListState<Repository>, for source: RepoListSource) {
        switch source {
        case .repos: reposState = newState
        case .starred: starredState = newState
        }
    }

    private func load(reset: Bool) async {
        // ⚠️ 先锁定"这次请求属于哪一个数据源"：请求在途时用户可能切了分段，
        //    若回来后写进"当前段"的状态里，两份累计就串了 —— 而界面看上去只是"数据不对"。
        let source = segment.source
        guard !state(for: source).isLoading else { return }

        var working = state(for: source)
        // 只有刷新才从头取；其余一律接着上次的游标。
        let cursor = reset ? nil : working.nextCursor
        working.beginLoad(reset: reset)
        store(working, for: source)

        do {
            let page = try await loader.load(source: source, cursor: cursor)
            var latest = state(for: source)
            latest.received(page)
            store(latest, for: source)
        } catch {
            var latest = state(for: source)
            latest.failed(Self.failure(from: error))
            store(latest, for: source)
        }
    }

    /// 把任意错误收敛成 `GitHubError`。
    ///
    /// ⚠️ 映射失败归 `.decoding`（响应形状不对），**不是** `.transport`：
    ///    报成网络问题会让界面提示"检查网络"，而网络其实是好的 ——
    ///    这正是"不要编造结论"要挡住的那类误导。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}
