import Foundation
import GitHubAPI
import GitDuoKit

/// 「我的 Pull Request / 我的 Issue」页的状态（PRD §4.21、决策 #73 / #44）。
///
/// ## 两页共用一个类型，只有"问哪一类"不同
///
/// PRD §4.21 逐字：「两个菜单项、同一个页面，只有标题与筛选口径不同」。
/// `kind` 一路透给 `LoadMyConversations`（它按类各存一份缓存），
/// 而这一层不碰查询串 —— 那两段限定符是决策 #73 的产物，只有一个实现。
///
/// ## ⚠️ 分页是**「加载更多」按钮**，不是滚到底
///
/// 与搜索页同一条理由（决策 #44）：两者走**同一个** Search 桶（30 次/分钟），
/// 滚动手势一次能连发好几发，一旦 403，整个搜索页（四个范围共用）会一起瘫掉。
/// ⚠️ 它与「我的 Star」**有意不同** —— 那一页是主桶 5,000/小时，滚到底没关系。
///
/// ## ⚠️ 失败分两档，因为它们要留的东西不同
///
/// | | 什么时候 | 屏幕上 |
/// |---|---|---|
/// | `error`（首屏 / 刷新） | 手上还没有内容，或下拉刷新失败 | 没内容 ⇒ 整页失败态；有内容 ⇒ 底部那一行 |
/// | `pageFailed`（续页） | 已经有一屏内容，往下翻时失败 | 内容留着，只在底部多一行（§8.5） |
///
/// 两档都是"**失败不遮挡已加载的内容**"，但**重试的动作不同**：
/// 首屏/刷新失败要重新取**第一页**，续页失败要接着取**下一页**。
/// 合成一个布尔量的话，那个按钮总有一半的时候按下去是在做另一件事。
@MainActor
@Observable
final class MyConversationsViewModel {

    /// 主区域的四态（可辨 —— §8.5）。
    enum Content: Equatable {
        case skeleton
        case rows
        case empty
        case failure(GitHubError)
    }

    let kind: ConversationKind

    /// 这一类**累计**的结果；`nil` = 还没取到过。
    private(set) var result: LoadMyConversations.Result?

    /// 首屏 / 刷新失败。
    private(set) var error: GitHubError?

    /// 续页在途（底部转圈）。
    private(set) var isPaging = false

    /// 续页失败（底部那一行 + 重试）。
    private(set) var pageFailed = false

    /// 这一份结果的到达时刻。相对时间（`· 2 小时前`）用它算 ——
    /// 由模型在结果落地那一刻取一次，**不在 `body` 里取**：那会让每次重绘
    /// 拿到略微不同的值，于是相对时间变成渲染时机的一部分（同 `SearchViewModel`）。
    private(set) var loadedAt = Date()

    /// 首屏在途。
    ///
    /// ⚠️ 它必须与 `isPaging` 分开：`isPaging` 只管"底部那个转圈"，
    /// 而首屏在途时底部**什么都不该显示**（屏幕上已经是骨架了）。
    /// 用一个布尔量表达两件事，会让首屏那一下在底部多转一个圈。
    private var isFirstLoadInFlight = false

    private let loader: LoadMyConversations

    init(kind: ConversationKind, loader: LoadMyConversations) {
        self.kind = kind
        self.loader = loader
    }

    // MARK: - 供视图读取

    /// 推入页标题 —— 与「我的」页那两条菜单**逐字相同**（取 `ProfileCopy` 那一份）。
    var title: String { MyConversationsCopy.title(for: kind) }

    var rows: [ConversationHit] { result?.hits ?? [] }

    /// 说明行：`{N} 个结果`。`nil` = 不显示（真没结果时由空态说话）。
    var listTitle: String? {
        result.map { MyConversationsCopy.resultsCount($0.totalCount) }
    }

    /// `incomplete_results` 的说明行（`nil` = 不显示）。**不是错误态**。
    var notice: String? { result?.notice }

    var hasMore: Bool { result?.hasMore ?? false }

    var emptyTitle: String { MyConversationsCopy.emptyTitle(for: kind) }
    var emptyHint: String { MyConversationsCopy.emptyHint(for: kind) }

    /// 底部要不要显示"重试"那一行（见类型说明那张表）。
    var showsRetryRow: Bool {
        pageFailed || (error != nil && result != nil)
    }

    var content: Content {
        if let result { return result.isEmpty ? .empty : .rows }
        if let error { return .failure(error) }
        // 还没开始 / 正在取第一页。
        return .skeleton
    }

    // MARK: - 生命周期

    /// 进页：**先看缓存**（命中即上屏，不出网、不花配额）。
    ///
    /// 与搜索页同一条：`LoadMyConversations` 就是拿这个理由存在的
    /// （切到「我的 Issue」再切回来不该重发一轮，那个桶只有 30 次/分钟）。
    func loadIfNeeded() async {
        guard result == nil else { return }
        if let cached = await loader.cached(kind) {
            apply(cached)
            return
        }
        await load(reset: true)
    }

    /// 下拉刷新：重取第一页。
    func refresh() async {
        await load(reset: true)
    }

    /// 底部「加载更多」。
    func loadMore() async {
        guard hasMore, !isPaging else { return }
        await load(reset: false)
    }

    /// 首屏 / 刷新失败后的重试。
    ///
    /// ⚠️ 先**立刻清掉错误**再取：不清的话点完重试还会有一小段"原样不动"
    /// （屏幕上是那块失败态，看起来像没反应）—— 同 `SearchViewModel.retry()`。
    func retry() async {
        error = nil
        await load(reset: true)
    }

    /// 底部那一行"重试"按下去该做什么 —— **两档动作不同**（见类型说明）。
    func retryFromFooter() async {
        if pageFailed {
            await load(reset: false)
        } else {
            await retry()
        }
    }

    // MARK: - 内部

    private func load(reset: Bool) async {
        // ⚠️ 一次只允许一发在途：下拉刷新与续页会在同一个 `await` 点上交错，
        //    后返回的那发覆盖先返回的 ⇒ 表现是"刷新之后列表少了一半"，
        //    而屏幕上看起来完全正常（有内容、不报错、分页行也在）。
        guard !isPaging, !isFirstLoadInFlight else { return }

        if reset {
            isFirstLoadInFlight = true
        } else {
            isPaging = true
            pageFailed = false
        }
        // ⚠️ `defer` 必须包住**整个函数体**。原先它写在 `if` / `else` 的分支里，
        //    而那两处都在分支末尾 ⇒ 它**在离开那个分支的一瞬间就执行了**，
        //    闸门等于没上（编译器给的正是这条警告：`'defer' statement at end of scope
        //    always executes immediately`）。两个标志合起来放在这里收尾，
        //    因为离开这个函数只有一条路。
        defer {
            isFirstLoadInFlight = false
            isPaging = false
        }

        do {
            apply(try await loader.load(kind, reset: reset))
        } catch is CancellationError {
            // 取消不是失败（用户自己把页面关了），**不要**渲染成"加载失败"。
        } catch {
            if reset {
                // ⚠️ `self.` **不能省**：`catch` 自带一个叫 `error` 的隐式绑定，
                //    不写 `self.` 时左边那个 `error` 指的是它（一个 `let`），
                //    编译器会说"cannot assign to value: 'error' is immutable"。
                self.error = Self.failure(from: error)
            } else {
                // 续页失败：**已加载的内容留在屏幕上**，只在底部多一行（§8.5）。
                pageFailed = true
            }
        }
    }

    private func apply(_ loaded: LoadMyConversations.Result) {
        result = loaded
        error = nil
        pageFailed = false
        loadedAt = Date()
    }

    /// 把任意错误收敛成 `GitHubError`（同其余 ViewModel 的口径：
    /// 映射失败归 `.decoding`，**不是** `.transport` —— 后者会谎称网络问题、
    /// 给出"检查网络"的错误引导）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}
