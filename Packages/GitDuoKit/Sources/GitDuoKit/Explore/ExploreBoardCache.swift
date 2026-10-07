import Foundation

/// 榜单结果的**按组合复用缓存**（决策 #37 / TECH_SPEC §9.10.5）。
///
/// ## 为什么它是功能需求，不是优化
///
/// Search 配额**独立且只有 30 次/分钟**（§9.10.1），且与搜索页**共用同一个桶**。
/// 用户在新星 / 活跃 × 4 档日期 × 6 种语言之间来回点几下，一分钟内就会撞配额 ——
/// 而 PRD §4.12 把"来回切换直接命中，不重复拉取"写成了**交互要求**。
///
/// ## 三条硬约束
///
/// | 约束 | 原因 |
/// |---|---|
/// | **纯内存、不落盘** | 探索历史（看过哪个榜、筛了哪种语言）本身就是一条可被读出的用户行为记录 —— 理由与决策 #32 同源 |
/// | 键含**全部**筛选维度 | 少一个维度 ⇒ "切回来却看到上一组筛选的结果"，比不缓存更糟（`ExploreCacheKey` 的注释） |
/// | LRU 上限 12 | 真实使用是少数几个组合反复横跳，12 足够覆盖实际路径（决策 #37） |
///
/// ## 为什么是**值类型**而不是 actor
///
/// LRU 的淘汰顺序是这套东西里唯一容易写错的地方（"最近用过"要重排、淘汰要挑最久未用），
/// 而它**没有并发**：持有者（`LoadTrendingBoard`）才是 actor。做成值类型之后，
/// "连续写入 13 个组合，第 1 个被淘汰""命中一次会让它免于被淘汰"这类断言
/// 可以直接同步写完，不必把测试写成异步。并发保护由持有者负责，不重复做一遍。
public struct ExploreBoardCache: Sendable {

    /// 一个组合下已累计的内容。
    public struct Entry: Sendable, Hashable {

        /// 已加载的榜单行（**累计**，含续页追加的部分）。
        public let rows: [TrendingRow]

        /// 下一页的完整 URL；`nil` = 已到底。
        public let nextCursor: URL?

        /// 已加载的这些页里**是否出现过** `incomplete_results`。
        ///
        /// 取"或"而不是"最后一页的值"：只要有一页少了东西，这份累计列表就不完整，
        /// 而界面上那句话说的是整份列表。
        public let incompleteResults: Bool

        public var hasMore: Bool { nextCursor != nil }

        public init(rows: [TrendingRow], nextCursor: URL?, incompleteResults: Bool) {
            self.rows = rows
            self.nextCursor = nextCursor
            self.incompleteResults = incompleteResults
        }
    }

    /// 上限（决策 #37）。
    public let capacity: Int

    private var storage: [ExploreCacheKey: Entry] = [:]

    /// 最近使用的键，**末尾 = 最近**。淘汰时丢 `first`。
    private var recency: [ExploreCacheKey] = []

    public init(capacity: Int = ExploreBoardPolicy.cacheCapacity) {
        // 传 0 会让下面每次 `store` 都立刻淘汰自己 —— 那等于"缓存永不命中"，
        // 而表现是"切回来又发了一次请求"，看日志才发现。夹到 1，让它至少能用。
        self.capacity = max(1, capacity)
    }

    /// 已缓存的组合数。
    public var count: Int { storage.count }

    /// 全部键，**最久未用在前、最近用在后**（仅供测试与排查）。
    public var keys: [ExploreCacheKey] { recency }

    /// 读一个组合。
    ///
    /// ⚠️ 它是 `mutating`：**命中就算一次使用**，会把该键移到"最近"。
    /// 漏掉这一步，一个天天在用的组合会因为"很久以前写过"而被淘汰 ——
    /// 缓存于是退化成"随机命中"，而它看起来仍在工作。
    public mutating func entry(for key: ExploreCacheKey) -> Entry? {
        guard let entry = storage[key] else { return nil }
        touch(key)
        return entry
    }

    /// 写入（已存在则覆盖并置为最近）。
    public mutating func store(_ entry: Entry, for key: ExploreCacheKey) {
        storage[key] = entry
        touch(key)

        while storage.count > capacity, let evicted = recency.first {
            recency.removeFirst()
            storage[evicted] = nil
        }
    }

    /// 失效一个组合（**下拉刷新只失效当前组合**，§9.10.5 —— 不做整表失效）。
    public mutating func invalidate(_ key: ExploreCacheKey) {
        storage[key] = nil
        recency.removeAll { $0 == key }
    }

    /// 清空（登出时随其余账号数据一并清理，§9.10.5 的"生命周期"一行）。
    public mutating func removeAll() {
        storage.removeAll()
        recency.removeAll()
    }

    // MARK: - 内部

    private mutating func touch(_ key: ExploreCacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}
