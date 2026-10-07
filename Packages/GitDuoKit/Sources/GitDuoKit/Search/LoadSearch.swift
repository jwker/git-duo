import Foundation

/// 一条查询取回来的一页 —— 领域层与网络层之间的**接缝**。
///
/// ## 为什么接缝收在「行」这一层，而探索榜收在「DTO」那一层
///
/// `RepositorySearchDataSource`（探索榜）让 `LoadTrendingBoard` 自己拿 DTO 去映射，
/// 因为那条路径**只有一个端点、一种 DTO**。搜索这里**四个范围四种结果**：
/// 接缝若按 DTO 开，`LoadSearch` 就要认识四个 DTO 类型、并在自己内部写四段映射 ——
/// 而映射正是"哪些字段有、哪些没有"的业务判断（比如 `text_matches` 缺席时
/// `snippet` 为 `nil`、PR 的"已合并"要靠 `merged_at` 算），
/// 它应该与其余领域规则一起被单测覆盖。
///
/// 收在行这一层 ⇒ `LoadSearch` 只跟 `SearchRow` 打交道，四范围的差异全在适配器里
/// （切片 5.2 的 `GitHubSearchDataSource`），而 `SearchRow` 与它的映射都能单测。
public struct SearchHitPage: Sendable {

    public let rows: [SearchRow]

    /// 服务端 `total_count`：**该条查询**匹配的总数。
    public let totalCount: Int

    /// 下一页的**完整 URL**；`nil` = 这条查询到底了（§4.4）。
    public let nextCursor: URL?

    /// `incomplete_results` —— "这一页少了东西"的唯一信号（同 `SearchRepositoriesResult`）。
    public let incompleteResults: Bool

    public init(rows: [SearchRow], totalCount: Int, nextCursor: URL?, incompleteResults: Bool) {
        self.rows = rows
        self.totalCount = totalCount
        self.nextCursor = nextCursor
        self.incompleteResults = incompleteResults
    }
}

/// 搜索的数据来源接缝。
///
/// 实现只有两个：`GitHubSearchDataSource`（生产，按 `part.scope` 分发到四个真实端点）
/// 与测试里的脚本化替身。**分发与映射都归实现**，`LoadSearch` 只跟 `SearchRow` 打交道。
public protocol SearchDataSource: Sendable {

    /// 发**一条**查询（`SearchQueryPart`）的一页。
    ///
    /// ⚠️ 打哪个端点、占哪个配额桶由 `part.scope` 决定（见 `SearchQueryPart` 的说明）——
    /// 也就是说**实现必须按 scope 分发**，而不是把所有 part 都发到同一个端点。
    /// 漏了这件事不会报错：`q=` 里的 `is:issue` 会让 `/search/users` 返回**空结果**，
    /// 屏幕上表现为"这个范围永远搜不到东西"。
    ///
    /// ⚠️ `part.qualifiers` **不能为空**、代码范围**不能只有限定符** —— 两者服务端都回 422，
    /// 而**那次失败照样扣配额**（代码那一档只有 10 次/分钟）。
    /// 调用方只会在 `SearchQueryReadiness.ready` 之后调这里；本协议自己不做判定，
    /// 因为判定属于领域规则（`SearchQueryBuilder`），而适配器只负责出网与映射。
    /// ⚠️ 每条查询都必须显式声明它自己的配额桶：`.search`，代码范围 `.codeSearch`。
    func search(_ part: SearchQueryPart, perPage: Int, cursor: URL?) async throws -> SearchHitPage
}

/// 取搜索结果（PRD §4.2、TECH_SPEC §9.2、决策 #44 / #45）。
///
/// ## 它把四件事钉在一处
///
/// 1. **拼查询**（`SearchQueryBuilder`，纯逻辑、已单测）；
/// 2. **按 part 分发并合并**（「Issue · PR」是两条查询、两个游标，见 `SearchQuery`）；
/// 3. **累加与去重**（续页追加、按 `SearchRow.id` 去重）；
/// 4. **按「范围 · 关键词」复用**（`cache`，LRU）。
///
/// 四件事必须同时成立才不会出现"数字好看但含义是假的"—— 所以它们在一个类型里，
/// 而不是散在 ViewModel 中（App target 没有测试 target，散过去就等于没人守）。
///
/// ## 它是 actor
///
/// `cache` 是可变状态。"两个连点同时到达"若不加保护，会让同一个组合被写两次、
/// LRU 顺序错乱（与 `LoadTrendingBoard` 同理由）。
///
/// ## ⚠️ 它不做防抖
///
/// 防抖是"用户还在打字，先别发"的**交互策略**，属 ViewModel —— 只有它知道
/// 有没有新的输入到来。本类型只保证"被调一次就正确一次"。
public actor LoadSearch {

    // MARK: - 结果

    /// 某个「范围 · 关键词」下**累计**的结果。
    public struct Result: Sendable, Hashable {

        /// 每条 part 各自的累计状态。**顺序与 `SearchQuery.parts` 一致**（Issue 在前）。
        fileprivate let parts: [Part]

        /// 屏幕上要渲染的行：各 part 依次拼接。
        public var rows: [SearchRow] { parts.flatMap(\.rows) }

        /// 服务端匹配总数 = 各 part 的 `total_count` **之和**。
        ///
        /// 相加是安全的：issue 与 PR 是**不相交**的两个集合（各由一条 `is:` 查询取回），
        /// 不会重复计数 —— 这正是它可以用服务端计数、而探索 Issues 列表不能用
        /// `open_issues_count` 的分野（那边那个数把列表刻意滤掉的东西也算进去，
        /// 见决策 #38）。判据是同一条：**数字必须是对屏幕上的这个列表的真话**。
        public var totalCount: Int { parts.reduce(0) { $0 + $1.totalCount } }

        /// 还有下一页 —— **任一条** part 还有游标就算有。
        public var hasMore: Bool { parts.contains { $0.nextCursor != nil } }

        public var isEmpty: Bool { rows.isEmpty }

        /// 列表说明行（`nil` = 不显示）。
        ///
        /// 与 `ExploreBoardNotice` 同一取向：`incomplete_results` **不是错误态**，
        /// 正确反应是照常渲染已拿到的条目 + 说明一句。
        public var notice: String? {
            parts.contains(where: \.incomplete) ? SearchCopy.incompleteResults : nil
        }
    }

    /// 单条 part 的累计状态。
    fileprivate struct Part: Sendable, Hashable {
        var rows: [SearchRow] = []
        var nextCursor: URL?
        var totalCount: Int = 0
        var incomplete: Bool = false
    }

    // MARK: - 状态

    /// 缓存键的显式类型（不用元组：元组不能 `Hashable` 成字典键的稳定身份）。
    private struct Key: Sendable, Hashable {
        let scope: SearchScope
        let keyword: String
    }

    private let source: any SearchDataSource

    /// 「范围 · 关键词」→ 累计结果。
    ///
    /// 它的存在理由是**功能需求**而不是优化：§4.2 明写切范围"不清空已加载的页"，
    /// 而搜索配额只有 30/min（代码 10/min）—— 来回切一次范围就重发一轮是不可接受的。
    private var cache: [Key: Result] = [:]

    /// 最近使用顺序，**最后 = 最新**。
    private var order: [Key] = []

    /// 最多缓存多少个组合。不设上限的话，一轮里搜十个词就留下十份列表。
    private let capacity: Int

    public init(source: any SearchDataSource, capacity: Int = 12) {
        self.source = source
        self.capacity = max(1, capacity)
    }

    // MARK: - 读缓存

    /// 该组合已缓存的结果（**命中即可直接上屏，不出网、不花配额**）；`nil` = 没搜过。
    ///
    /// ViewModel 用它区分"换到新组合 ⇒ 先上骨架屏"与"切回老组合 ⇒ 秒开"。
    /// 读一次即算用过（LRU 的"最近使用"就应该是**读**的时刻，而不是写入的时刻）。
    public func cached(_ query: SearchQuery) -> Result? {
        let key = Key(scope: query.scope, keyword: query.keyword)
        guard let result = cache[key] else { return nil }
        markUsed(key)
        return result
    }

    // MARK: - 取数

    /// 取下一页。
    ///
    /// - Parameter reset: `true` = 重新搜索（换关键词 / 重搜），从每条 part 的第一页开始；
    ///   `false` = 续「加载更多」（决策 #44 的按钮）。
    ///
    /// - Returns: 该组合**累计**的结果（含本次新增的部分）。
    ///
    /// ## 已经到底就不再出网
    ///
    /// `reset == false` 且每条 part 的游标都已经是 `nil` ⇒ 直接返回缓存，**一发请求都不发**。
    /// 漏掉这道闸门，「加载更多」在到底之后每点一次就白扣配额
    /// （「Issue · PR」范围是**两格**）—— 与 `LoadTrendingBoard` 同一道闸门。
    ///
    /// ## 续页是「追加」而不是「重排」
    ///
    /// 与 §9.10.5 同取向：第 2 页往后**不再把整份列表重排**。重排会把新条目插到
    /// 已渲染列表的中段 —— 「Issue · PR」范围尤其明显（第 2 页的 Issue 会插到
    /// 第 1 页的 PR 之前），用户的滚动位置会当场跳走。
    /// 代价是整份列表并非全局有序，收益是滚动时列表不抖。
    ///
    /// ## 还有游标的那条才发；到底的那条**跳过**
    ///
    /// 「Issue · PR」两条查询的深度通常不一样（Issues 1000 条、PR 30 条就到底了）。
    /// 已经到底的那条再问一次只会拿回空页并白扣一格 ⇒ 直接跳过，用上一次的游标与计数。
    ///
    /// ## 任一条 part 失败 ⇒ 整次失败，且**不改动缓存**
    ///
    /// `try` 抛在写回之前：已加载的内容必须留在屏幕上（§8.5），而清掉游标等于
    /// 一次失败就让用户彻底失去「加载更多」的入口 —— 与 `PagedListState.failed(_:)` 同一取向。
    /// 不做"哪条成功就只写哪条"：那会让「Issue · PR」的计数与游标进入"一半新一半旧"的状态，
    /// 而用户无从判断屏幕上这份列表是哪一版。
    public func load(_ query: SearchQuery, reset: Bool = false) async throws -> Result {
        let key = Key(scope: query.scope, keyword: query.keyword)
        let existing = reset ? nil : cache[key]

        // 已经到底就不再出网。
        if let existing, !existing.hasMore {
            markUsed(key)
            return existing
        }

        // 第一次取、或形状对不上（理论上不会 —— 键里已经含了范围）⇒ 一律按"从头取"办，
        // 免得按过期的下标去索引 parts 而崩在数据不对上。
        let isResetting = reset || existing == nil || existing?.parts.count != query.parts.count

        var parts = isResetting
            ? Array(repeating: Part(), count: query.parts.count)
            : (existing?.parts ?? [])

        for (index, part) in query.parts.enumerated() {
            let cursor: URL?
            if isResetting {
                cursor = nil
            } else {
                cursor = parts[index].nextCursor
                // 这条已经到底 ⇒ 不重发（省下一格配额）。
                if cursor == nil { continue }
            }

            let page = try await source.search(part, perPage: query.perPage, cursor: cursor)

            parts[index].rows.append(contentsOf: page.rows)
            parts[index].nextCursor = page.nextCursor
            // 总数取**这一条 part 最新一次**的回答：它说的是"这条查询匹配多少个"，
            // 与服务端网页端显示的那个数一致，不随我们翻了几页而变化。
            parts[index].totalCount = page.totalCount
            // 累计口径：只要有任何一页报过不完整，这份列表就谈不上完整。
            parts[index].incomplete = parts[index].incomplete || page.incompleteResults
        }

        // 去重：同一页里不该有重复，但翻页期间内容可能变动（比如某条被更新后
        // 换到了后一页的前面），于是它会在两页里各出现一次 ⇒ `ForEach` 拿到两个相同 id。
        // 与 `PagedListState.merged` / `LoadTrendingBoard.merged` 同一取舍：**保留先到的**。
        parts = parts.map(Self.deduplicated)

        let result = Result(parts: parts)
        store(result, for: key)
        return result
    }

    // MARK: - 失效

    /// 清空全部组合（登出时随其余账号数据一并清理，§3.6 ③）。
    public func invalidateAll() {
        cache.removeAll()
        order.removeAll()
    }

    /// 当前缓存的组合数（仅供排查与测试）。
    public var cachedKeyCount: Int { cache.count }

    // MARK: - 内部

    private static func deduplicated(_ part: Part) -> Part {
        var seen = Set<String>()
        var rows: [SearchRow] = []
        rows.reserveCapacity(part.rows.count)
        for row in part.rows where seen.insert(row.id).inserted {
            rows.append(row)
        }
        var next = part
        next.rows = rows
        return next
    }

    private func store(_ result: Result, for key: Key) {
        cache[key] = result
        markUsed(key)
        // LRU：淘汰最久未用的那个（`order` 的首位）。
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            cache[oldest] = nil
        }
    }

    private func markUsed(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
