import Foundation

/// 一条查询取回来的一页（PRD §4.21、决策 #73）。
///
/// ## 为什么不像搜索页那样复用 `SearchHitPage`
///
/// 因为这一页**只有一种行**。`SearchHitPage.rows` 是 `[SearchRow]`（四范围的联合），
/// 用它就要在展示层再解一层 `.conversation(hit)` —— 而这一页**不可能**出现仓库行、
/// 用户行或代码行。"解不开怎么办"这个分支永远走不到，却永远有人要读它。
/// 直接给 `[ConversationHit]`，那种状态就不存在。
public struct MyConversationHitPage: Sendable {

    public let hits: [ConversationHit]

    /// 服务端 `total_count`（说明行里的 `{N} 个结果`）。
    public let totalCount: Int

    /// 下一页的**完整 URL**；`nil` = 到底了。
    public let nextCursor: URL?

    /// `incomplete_results` —— "这一页少了东西"的唯一信号（同 `SearchHitPage`）。
    public let incompleteResults: Bool

    public init(
        hits: [ConversationHit],
        totalCount: Int,
        nextCursor: URL?,
        incompleteResults: Bool
    ) {
        self.hits = hits
        self.totalCount = totalCount
        self.nextCursor = nextCursor
        self.incompleteResults = incompleteResults
    }
}

/// 「我的 PR / 我的 Issue」的数据来源 —— 领域层与网络层之间的**接缝**。
///
/// ## ⚠️ 实现必须带排序参数
///
/// `sort=updated&order=desc`（见 `MyConversationsQuery.sortParameter` / `sortOrder`）。
/// 漏了**不会报错**，只会安静地按服务端的相关度排 —— 而屏幕上看起来完全正常
/// （列表有内容、条数也对），只有用户会发现"顺序怪"。所以它写在协议说明里，
/// 由本包的单测断言"这条路径确实按最近更新排"（替身按游标返回，顺序由它自己决定；
/// 真实排序由 9.2 的适配器负责，`REVIEW-CHECKLIST` 第 147 条会目视核对）。
///
/// ## 为什么按 `kind` 分发（而不是收一个 `SearchQueryPart`）
///
/// 因为这一页**一次只问一类**（决策 #73），而 `SearchQueryPart` 是为"一次多条"
/// 设计的（它带着 `scope` 以便接缝分发）。收 `kind` 意味着调用方**不可能**
/// 传进一个"两条 part"的东西 —— 这页刻意不要那个形状。
public protocol MyConversationsDataSource: Sendable {

    /// 发一条查询的一页。
    ///
    /// - Throws: 数据层归一化后的 `GitHubError`。**调用方据此给失败态 + 重试**。
    func search(
        kind: ConversationKind,
        perPage: Int,
        cursor: URL?
    ) async throws -> MyConversationHitPage
}

/// 取「我的 PR / 我的 Issue」的列表（PRD §4.21、决策 #73 / #44）。
///
/// ## 为什么**不**复用 `LoadSearch`
///
/// 看着很像（都是"一页一页取、累计、去重、按钮续页"），但有两处对不上：
///
/// 1. **缓存键**：`LoadSearch` 的键是「范围 · 关键词」。这一页范围恒为 `.issues`、
///    关键词恒为空 ⇒ **两类共用同一个键**，切到「我的 Issue」会拿到 PR 那份缓存。
///    而它的键里不能塞进 `kind`（那是搜索页的类型，改它是替那一页做决定）。
/// 2. **`SearchQuery` 造不出来**：它的 `init` 是 memberwise（模块内可见），
///    而它表达的"一次多条 part"在这里是多余的。
///
/// 两处都不是"想要不一样"，而是**那个类型服务的是另一个形状的事**。
/// 于是这里写一个同构但更小的实现（单一 part ⇒ 少一层 parts 数组），
/// 保留同样的三条纪律：**到底了就不再出网**、**失败不动缓存**、**按 `id` 去重**。
///
/// ## 它是 actor
///
/// `cache` 是可变状态。"两个连点同时到达"若不加保护，会让同一类被写两次 ——
/// 与 `LoadSearch` / `LoadTrendingBoard` 同理由。
public actor LoadMyConversations {

    /// 某一类**累计**到现在的状态。
    public struct Result: Sendable, Hashable {

        /// 屏幕上要渲染的行（**最近更新降序**，是服务端给的顺序）。
        public let hits: [ConversationHit]

        /// 服务端匹配总数（`{N} 个结果`）。
        public let totalCount: Int

        /// 下一页的**完整 URL**；`nil` = 到底了。
        ///
        /// ⚠️ 它是**唯一的真相**，`hasMore` 由它**派生**（同 `PagedListState` 那条纪律：
        /// `nextCursor` 是唯一真相、`canLoadMore` 由它算出来）。
        ///
        /// 曾经这里存的是 `hasMore: Bool`，续页时再想要游标就没有了 —— 那不是"少写一个字段"，
        /// 而是**两份状态**：一旦某条路径只更新了其中一份，就会出现"`hasMore` 说还有、
        /// 游标却是 `nil`"这种自相矛盾，而它的可见后果是「加载更多」每次点击都发一条
        /// `cursor=nil` 的请求（**回到第一页**）⇒ 屏幕上原地打转、配额白扣。
        /// 只存游标，那种状态就**写不出来**。
        public let nextCursor: URL?

        /// 还有下一页吗。**派生**，不单独存。
        public var hasMore: Bool { nextCursor != nil }

        /// 有没有哪一页报过 `incomplete_results`。
        ///
        /// 累计口径：**只要有任何一页报过不完整，这份列表就谈不上完整**。
        public let incomplete: Bool

        public var isEmpty: Bool { hits.isEmpty }

        /// 列表说明行（`nil` = 不显示）。
        ///
        /// `incomplete_results` **不是错误态**：正确反应是照常渲染已拿到的条目 + 说明一句
        /// （与 `ExploreBoardNotice` / `LoadSearch.Result.notice` 同一取向）。
        public var notice: String? {
            incomplete ? MyConversationsCopy.incompleteResults : nil
        }
    }

    private let source: any MyConversationsDataSource

    /// 两类（PR 一页、Issue 一页）各自的累计结果。
    ///
    /// ⚠️ 只有两个可能的键 ⇒ 上限就是 2，不需要 LRU（同 `ExploreBoardCache` 的判据：
    /// 淘汰策略是为"组合数不可枚举"设计的，这里可以枚举）。
    private var cache: [ConversationKind: Result] = [:]

    public init(source: any MyConversationsDataSource) {
        self.source = source
    }

    /// 这一类已缓存的结果（**命中即可直接上屏，不出网、不花配额**）；`nil` = 没取过。
    public func cached(_ kind: ConversationKind) -> Result? { cache[kind] }

    /// 取下一页。
    ///
    /// - Parameter reset: `true` = 重新取第一页（进页 / 下拉刷新）；
    ///   `false` = 续「加载更多」。
    ///
    /// - Returns: 这一类**累计**的结果（含本次新增的部分）。
    ///
    /// ## 已经到底就不再出网
    ///
    /// `reset == false` 且没有游标 ⇒ 直接返回缓存，**一发请求都不发**。
    /// 漏掉这道闸门，「加载更多」在到底之后每点一次就白扣一格格配额
    /// （这个桶只有 30 次/分钟）—— 与 `LoadSearch` / `LoadTrendingBoard` 同一道闸门。
    ///
    /// ## 失败**不动缓存**
    ///
    /// `try` 抛在写回之前：已加载的内容必须留在屏幕上（§8.5），
    /// 而清掉游标等于一次失败就让用户彻底失去「加载更多」的入口
    /// —— 与 `PagedListState.failed(_:)` 同一取向。
    public func load(_ kind: ConversationKind, reset: Bool = false) async throws -> Result {
        let existing = reset ? nil : cache[kind]

        if let existing, !existing.hasMore {
            return existing
        }

        let cursor = reset ? nil : existing?.nextCursor
        let page = try await source.search(
            kind: kind,
            perPage: MyConversationsQuery.pageSize,
            cursor: cursor
        )

        // 续页是**追加**，不是重排（同 §9.10.5 与 `LoadSearch`）：
        // 重排会把新条目插到已渲染列表的中段，用户的滚动位置会当场跳走。
        let hits = reset
            ? page.hits
            : Self.deduplicated((existing?.hits ?? []) + page.hits)

        let result = Result(
            hits: hits,
            // 总数取**最新一次**回答：它说的是"这条查询匹配多少个"，
            // 与服务端网页端显示的那个数一致，不随我们翻了几页而变化。
            totalCount: page.totalCount,
            nextCursor: page.nextCursor,
            // 累计口径：只要有任何一页报过不完整，这份列表就谈不上完整。
            incomplete: (existing?.incomplete ?? false) || page.incompleteResults
        )
        cache[kind] = result
        return result
    }

    /// 清空两类缓存（登出时随其余账号数据一并清理，§3.6 ③）。
    ///
    /// ⚠️ 不清的话，换个账号进来点「我的 Pull Request」，屏幕上会是**上一个账号**提的 PR。
    public func invalidateAll() {
        cache.removeAll()
    }

    /// 当前缓存的类数（仅供排查与测试）。
    public var cachedKindCount: Int { cache.count }

    // MARK: - 内部

    /// 追加并按 `id` 去重，**保留先到的**。
    ///
    /// 去重不是洁癖：列表按 `sort=updated` 排，**翻页期间某条被更新了一次**
    /// 就会让它从第 2 页挪到第 1 页，于是两页里各出现一次 ⇒
    /// `ForEach` 拿到两个相同的 id（渲染告警 + 视觉上是重复行）。
    /// 保留先到的那份是为了不让已经渲染过的行被换掉
    /// —— 与 `PagedListState.merged` / `LoadSearch` 同一取舍。
    private static func deduplicated(_ hits: [ConversationHit]) -> [ConversationHit] {
        var seen = Set<String>()
        var result: [ConversationHit] = []
        result.reserveCapacity(hits.count)
        for hit in hits where seen.insert(hit.id).inserted {
            result.append(hit)
        }
        return result
    }
}
