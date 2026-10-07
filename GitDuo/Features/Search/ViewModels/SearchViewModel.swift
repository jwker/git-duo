import Foundation
import GitHubAPI
import GitDuoKit

/// 搜索页的状态（PRD §4.2、TECH_SPEC §9.2；决策 #44–#48）。
///
/// ## 它把四件事管住
///
/// 1. **防抖**：用户还在打字时先把前一次的请求取消掉，只让**最后一次输入**真的出网
///    （间隔取 `SearchDebounce.interval(for:)` —— 代码范围 500ms，其余 300ms）；
/// 2. **取消**：「新输入 ⇒ 上一次的响应作废」（`SearchRequestToken`）。
///    光有防抖不够 —— 先输 `swi` 再输 `swiftui`，若 `swi` 的响应后到，
///    屏幕上留下的是 `swi` 的结果，而输入框里明明写着 `swiftui`；
/// 3. **缓存优先**：切回搜过的「范围 · 关键词」直接上屏、**不出网、不花配额**
///    （PRD §4.2 要求切范围"不清空已加载的页"）；
/// 4. **分页**：底部「加载更多」按钮（决策 #44 —— 不滚到底自动加载）。
///
/// ## 它不实现缓存本身
///
/// 缓存在 `LoadSearch`（actor，LRU 12）里 —— 那是"取数"的一部分，
/// 而且它要跟"合并两路查询、累加、去重"在同一个类型里才不会出现"数字好看但含义是假的"。
/// 本类型只负责**问它有没有**、以及把用户动作翻成对它的调用。
///
/// ## 防抖为什么在 ViewModel 而不在取数层
///
/// 防抖是"用户还在打字，先别发"的**交互策略** —— 只有这里才知道有没有新的输入到来。
/// `LoadSearch` 的保证是"被调一次就正确一次"（其类型说明也这么写了）。
///
/// ## ⚠️ 内容与组合**绑在一起存**
///
/// `Load.loaded` 把结果与"它属于哪个组合"一起带着。两者若分开存，会出现
/// "关键词已经换成新的、屏幕上还是上一个关键词的结果"那一帧 ——
/// 而它看起来完全正常（有内容、有标题、不报错），只是**结果不对**。
@MainActor
@Observable
final class SearchViewModel {

    // MARK: - 结果区的渲染形态

    /// 六态可辨（TECH_SPEC §8.5）。
    enum Content: Equatable {
        /// 未输入关键词 ⇒ 空闲态（最近搜索 + 热门关键词）。**不是**"没有结果"。
        case idle
        /// 代码范围只填了限定符（如 `language:go`）⇒ 说一句「先输入关键词」，**不发请求**。
        case needsKeyword
        /// 首屏加载中。
        case skeleton
        /// 有结果（可能还有下一页）。
        case rows
        /// 确实没有匹配。
        case empty
        /// 首屏失败（已有内容时的续页失败走底部那一行）。
        case failure(GitHubError)
    }

    // MARK: - 输入

    private(set) var scope: SearchScope = .repositories

    /// 输入框里的**原文**。
    ///
    /// ⚠️ 只能经 `updateKeyword(_:)` 改，不要直接赋值 —— 改值必须同时调度一次取数，
    /// 而"赋值"与"调度"分成两步时，总有一条新加的路径只做了前一步
    /// （症状：输入框里字变了、结果一动不动，且不报错）。
    private(set) var keyword: String = ""

    // MARK: - 内容

    private enum Load: Equatable {
        case idle
        case loading
        case loaded(LoadSearch.Result, combo: Combo)
        case failed(GitHubError, combo: Combo)
    }

    /// 「范围 · 关键词」—— 缓存与结果归属的键。
    private struct Combo: Equatable {
        let scope: SearchScope
        let keyword: String
    }

    private var load: Load = .idle

    /// 续页在途（驱动底部按钮的内联 loading）。
    private(set) var isPaging = false

    /// 续页失败（驱动底部那一行错误 + 重试）。**与已加载的内容并存**（§8.5）。
    private(set) var pageFailed = false

    /// 当前这份结果的到达时刻。相对时间（`· 2 小时前`）用它算 ——
    /// 由模型在结果落地那一刻取一次，**不在 `body` 里取**：
    /// 那会让每次重绘都拿到略微不同的值，于是相对时间变成渲染时机的一部分。
    private(set) var loadedAt = Date()

    // MARK: - 空闲态

    /// 最近搜索，最新在前（顺序由存储保证）。
    private(set) var history: [String] = []

    /// 热门关键词（决策 #45：内置静态词表，GitHub 没有这个数据源）。
    let hotKeywords = SearchHotKeywords.all

    // MARK: - 依赖

    private let loader: LoadSearch
    private let store: any SearchHistoryStore

    /// 在途的那一次（防抖 + 取消用它）。
    private var pending: Task<Void, Never>?

    /// 「新输入 ⇒ 上一次的响应作废」的那道闸门。
    private var token = SearchRequestToken()

    init(loader: LoadSearch, store: any SearchHistoryStore) {
        self.loader = loader
        self.store = store
    }

    // MARK: - 供视图读取

    var rows: [SearchRow] { result?.rows ?? [] }

    /// 当前组合的累计结果；`nil` = 屏幕上这一份不属于当前组合（或还没有）。
    var result: LoadSearch.Result? {
        if case let .loaded(result, combo) = load, combo == currentCombo { return result }
        return nil
    }

    /// 结果标题：`{范围名} · {N} 个结果`；`nil` = 不显示（真没结果时由空态说话）。
    ///
    /// ⚠️ `N` 是 `total_count`（服务端匹配总数，与 GitHub 网页端一致），
    /// **不是**屏幕上已加载的条数 —— 决策 #44 与 `LoadSearch.Result.totalCount` 的说明。
    var listTitle: String? {
        result.map { SearchCopy.resultsTitle(scope: scope, totalCount: $0.totalCount) }
    }

    /// `incomplete_results` 的说明行（`nil` = 不显示）。**不是错误态**。
    var notice: String? { result?.notice }

    /// 还有下一页 ⇒ 显示「加载更多」。
    var hasMore: Bool { result?.hasMore ?? false }

    var emptyTitle: String {
        SearchCopy.noResultsTitle(scope: scope, keyword: trimmedKeyword)
    }

    var content: Content {
        switch SearchQueryBuilder.readiness(scope: scope, keyword: keyword) {
        case .emptyKeyword:
            return .idle
        case .needsBareTerm:
            return .needsKeyword
        case .ready:
            break
        }

        if case let .loaded(result, combo) = load, combo == currentCombo {
            return result.rows.isEmpty ? .empty : .rows
        }
        if case let .failed(error, combo) = load, combo == currentCombo {
            return .failure(error)
        }
        // 还没开始 / 正在加载 / 手上这份属于**别的**组合 —— 三者都该显示骨架屏：
        // 最后一种正是"输入框里已经换了词"的那一段，不显示骨架就会把旧结果留在屏幕上。
        return .skeleton
    }

    // MARK: - 输入动作

    /// 输入框里的文字变了。
    func updateKeyword(_ text: String) {
        guard text != keyword else { return }
        keyword = text
        schedule()
    }

    /// 切范围。**只按新范围重筛当前关键词**，不丢输入（PRD §4.2）——
    /// 已加载的页也不丢：它们留在 `LoadSearch` 的缓存里，切回来是秒开。
    func select(scope newScope: SearchScope) {
        guard newScope != scope else { return }
        scope = newScope
        schedule()
    }

    /// 点一条历史 / 一个热词 —— 直接把关键词填进去（原型 `useHistory` / `useHot`）。
    func use(term: String) {
        keyword = term
        schedule()
    }

    /// 回车（PRD §4.2）。
    ///
    /// - Returns: 要显示的提示文案。关键词为空时说 `先输入关键词`，否则记一笔并回
    ///   `搜索「{关键词}」`。**返回文案而不是自己弹提示**：提示通道挂在 `MainTabView` 上，
    ///   由视图层转发（与 `ExploreViewModel.select(range:)` 返回 `ExploreFilterChange` 同一分工）。
    func submit() async -> String {
        let term = trimmedKeyword
        guard !term.isEmpty else { return SearchCopy.needsKeyword }

        await record(term: term)
        return SearchCopy.submittedToast(keyword: term)
    }

    /// 点开一条结果时记一笔 —— **两处都记**（PRD §4.2 2026-10-07 校正）：
    /// 回车与点开结果。点开才是"这条搜索有用"的真实信号。
    ///
    /// ⚠️ 它是**同步**的，落盘在内部起一个不等候的任务。这不是偷懒：调用它的那一刻
    /// 页面就要跳走了，而且用户回来之后很可能立刻改关键词 —— 若把这个词读到 `Task` 里再读，
    /// 读到的会是**改过之后**的那个词，于是"最近搜索"里留下一条从没搜过的词。
    /// 所以关键词必须在**这一刻**取下来。
    ///
    /// 不返回文案：点开之后页面就跳走了，提示反而会盖在新页面上。
    func recordCurrentTerm() {
        let term = trimmedKeyword
        guard !term.isEmpty else { return }
        Task { await record(term: term) }
    }

    // MARK: - 历史

    func loadHistory() async {
        history = await store.terms()
    }

    /// 清空本机记录。**不弹确认层**（PRD §4.2、`SearchHistoryStore` 的说明）。
    func clearHistory() async {
        await store.clear()
        history = []
    }

    // MARK: - 分页与失败

    /// 底部「加载更多」（决策 #44：搜索**不**滚到底自动加载）。
    func loadMore() async {
        guard let result, result.hasMore, !isPaging else { return }
        guard let query = readyQuery else { return }
        await perform(query, token: token.current, paging: true)
    }

    /// 首屏失败后的重试。
    func retry() {
        // 先立刻切回骨架屏 —— 否则点了重试之后还会有一小段"原样不动"，看起来像没反应。
        load = .loading
        schedule()
    }

    // MARK: - 内部

    private var trimmedKeyword: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentCombo: Combo {
        Combo(scope: scope, keyword: trimmedKeyword)
    }

    /// 拼好的查询；`nil` = 还不该发（空关键词 / 代码范围只有限定符）。
    private var readyQuery: SearchQuery? {
        SearchQueryBuilder.readiness(scope: scope, keyword: keyword).query
    }

    /// 调度一次取数：**取消在途 → 缓存命中即秒开 → 否则防抖后取数**。
    private func schedule() {
        pending?.cancel()

        // 上一次的号就此作废：它的响应即使回来也不许上屏。
        let requestToken = token.issue()

        guard let query = readyQuery else {
            // 空闲态 / 门槛没过：不出网，**也不该继续显示别的组合的结果**。
            load = .idle
            isPaging = false
            pageFailed = false
            return
        }

        pending = Task { [weak self] in
            guard let self else { return }

            // ① 缓存命中：直接上屏，不出网、不花配额，**也不做防抖**
            //    （它本来就不花代价，"等 300ms 再显示已有内容"只是平白发顿）。
            if let cached = await loader.cached(query) {
                guard token.isCurrent(requestToken) else { return }
                apply(cached, combo: Combo(scope: query.scope, keyword: query.keyword))
                return
            }

            guard token.isCurrent(requestToken) else { return }

            // ② 没命中：先整块换成骨架屏（否则用户会对着上一个关键词的结果等新结果）。
            load = .loading
            isPaging = false
            pageFailed = false

            // ③ 防抖：用户还在打字就先别发。
            try? await Task.sleep(for: SearchDebounce.interval(for: query.scope))
            guard !Task.isCancelled, token.isCurrent(requestToken) else { return }

            await perform(query, token: requestToken, paging: false)
        }
    }

    /// 真的出一趟网。
    ///
    /// - Parameters:
    ///   - requestToken: 发起时领的号。回来时若已不是最新的 ⇒ 整份丢掉。
    ///   - paging: `true` = 续页（底部按钮），`false` = 首屏。
    private func perform(_ query: SearchQuery, token requestToken: UInt64, paging: Bool) async {
        // ⚠️ 组合在发起时就固定下来：`await` 期间用户可能已经改了关键词或切了范围。
        let combo = Combo(scope: query.scope, keyword: query.keyword)

        if paging {
            isPaging = true
            pageFailed = false
        }

        do {
            let result = try await loader.load(query, reset: false)
            // 回来后**再确认一次**：号没作废、组合没变。
            guard token.isCurrent(requestToken), combo == currentCombo else { return }
            apply(result, combo: combo)
        } catch is CancellationError {
            // 取消不是失败（用户自己改了输入），**不要**把它渲染成"加载失败"。
            if paging { isPaging = false }
        } catch {
            guard token.isCurrent(requestToken), combo == currentCombo else { return }

            if paging {
                // 续页失败：已加载的内容留在屏幕上，只在底部多一行（§8.5）。
                isPaging = false
                pageFailed = true
            } else {
                load = .failed(Self.failure(from: error), combo: combo)
            }
        }
    }

    private func apply(_ result: LoadSearch.Result, combo: Combo) {
        load = .loaded(result, combo: combo)
        loadedAt = Date()
        isPaging = false
        pageFailed = false
    }

    private func record(term: String) async {
        await store.record(term: term)
        // 立刻回读，而不是本地拼一份：去重 / 置顶 / 裁到 8 条那三件事的**唯一实现**
        // 在存储里（`InMemorySearchHistoryStore.record` 就是原型 `recordTerm` 的逐字移植），
        // 在这里再算一遍等于把规则抄了两份。
        history = await store.terms()
    }

    /// 把任意错误收敛成 `GitHubError`（同其余 ViewModel 的口径：
    /// 映射失败归 `.decoding`，**不是** `.transport` —— 后者会谎称网络问题、
    /// 给出"检查网络"的错误引导）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}
