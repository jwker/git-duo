import Foundation

/// 「最近搜索」的存储（PRD §4.2、TECH_SPEC §9.2）。
///
/// 依据：原型 `scripts/04-search.js`
/// ```js
/// function recordTerm(){
///   const q = searchState.q.trim(); if(!q) return;
///   SEARCH_HISTORY = [q].concat(SEARCH_HISTORY.filter(x=>x!==q)).slice(0,8);
/// }
/// ```
/// 四件事一次做完：**空白不记** · **去重**（先滤掉同词的旧记录）· **置顶**（新的拼在最前）· **裁到 8 条**。
/// 任一漏掉的表现都很具体：不去重 ⇒ 连按两次回车出现两条一样的；
/// 不置顶 ⇒ 复用一个旧词后它仍停在原位，用户找不到"我刚搜过"；
/// 不裁剪 ⇒ 越用越长。
///
/// ## ⚠️ 与 `RecentVisitStore` 同规矩：协议**刻意不含任何观察 / 回调入口**
///
/// 落盘归存储层，界面只在**下次出现时**读取。写入若直接触发重绘，
/// 就成了一条「写入 → 重绘 → 再写入」的循环。
///
/// ## ⚠️ 与「最近访问」的**有意不同**：「清除」不弹确认层（§9.2）
///
/// 那是浏览足迹（用户没打算留的东西），这是用户**显式输入**的关键词 ——
/// 意图明确，再问一次只是拦路。原型 `clearSearchHistory` 也是直接清 + toast。
public protocol SearchHistoryStore: Sendable {

    /// 最多保留几条（PRD §4.2：最多 8 条）。
    static var maxCount: Int { get }

    /// 记一条：去重后置顶，并裁到 `maxCount`。**空白输入不记**（原型 `if(!q) return`）。
    func record(term: String) async

    /// 读取全部，**最新在前**。
    func terms() async -> [String]

    /// 清空本机记录。
    func clear() async
}

extension SearchHistoryStore {
    public static var maxCount: Int { 8 }
}

/// 内存实现 —— 供单测与预览使用。
///
/// 落盘实现（`UserDefaults` + JSON）按 `RecentVisitStore` 的先例放在 App 组合根：
/// 本包是领域层，只定义"该是什么行为"；"存在哪、怎么存"属基础设施。
public actor InMemorySearchHistoryStore: SearchHistoryStore {

    private var storage: [String]

    /// - Parameter seed: 预置记录（测试与预览用）。
    ///
    /// ⚠️ **不假设有序、也不假设干净**：逐条去空白、丢掉空串、按精确匹配去重（保留先出现的），
    /// 再裁到 `maxCount`。理由是 `record` 的前提就是"存储里最新在前" ——
    /// 若照传入顺序收下一份顺序乱的旧数据，下一次 `record` 就会把新词插到错误的位置，
    /// 而这种错只在"装过旧版本 App"的用户身上复现。
    public init(seed: [String] = []) {
        var seen = Set<String>()
        var ordered: [String] = []
        for term in seed {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            ordered.append(trimmed)
        }
        self.storage = Array(ordered.prefix(Self.maxCount))
    }

    public func record(term: String) async {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 先滤掉同词的旧记录，再把新词拼到最前 —— 这就是原型的 concat + filter。
        // 顺序不能反：先拼后滤会把刚写进去的这条自己滤掉。
        var next = [trimmed]
        next.append(contentsOf: storage.filter { $0 != trimmed })
        storage = Array(next.prefix(Self.maxCount))
    }

    public func terms() async -> [String] { storage }

    public func clear() async { storage = [] }
}

/// 「最近搜索」的落盘编解码（TECH_SPEC §7.1：**UserDefaults + JSON**）。
///
/// ## 为什么这个也要放进领域层
///
/// 与 `RecentVisit.encodeList` 同源：App target **没有测试 target**，
/// 而"存进去取不回来"是**最安静的一类故障** —— 不报错、不崩溃，
/// 只是每次冷启动后「最近搜索」都空着，且很难想到是编码问题。
/// 两个方向写在同一处，才能让 `SearchHistoryTests` 用一次往返把它钉住。
public enum SearchHistoryCoding {

    public static func encode(_ terms: [String]) -> Data? {
        try? JSONEncoder().encode(terms)
    }

    /// **解不出就返回空数组**，不抛错：旧格式、被外部改坏的数据，
    /// 都只该让"最近搜索"退化成空态，而不是让整个搜索页打不开。
    public static func decode(from data: Data) -> [String] {
        (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
