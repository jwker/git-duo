import Foundation
import GitDuoKit

/// 「最近访问」的**落盘实现**（TECH_SPEC §7.1 存储表：`UserDefaults` + JSON）。
///
/// ## 它为什么在 App 组合根这一层
///
/// `RecentVisitStore` 的协议注释写明了这条分工：领域包只定义"该是什么行为"，
/// "存在哪、怎么存"属基础设施，在组合根装配。所以本类型不进 `GitDuoKit`。
///
/// ## ⚠️ 它**不重写**任何语义
///
/// 去重 / 置顶 / 裁到 6 条这三件事已经在 `InMemoryRecentVisitStore` 里被单测钉住
/// （`RecentVisitStoreTests`）。本类型只做"读出来 → 交给它 → 存回去"。
/// 如果在这里再实现一遍那三件事，就等于有了两份实现 —— 而落盘这一份**没有测试**
/// （App target 没有测试 target），于是它会成为那个没人看守、却每次冷启动都要走的分支。
///
/// 同理，编解码也走 `RecentVisit.encodeList` / `decodeList`（领域层，有往返测试）。
///
/// ## 多账号预留
///
/// `namespace` 就是 TECH_SPEC §7.2 说的命名空间前缀 —— 将来多账号切换到哪个账号就传哪个 `login`，
/// 存储结构不必改。本期只有单账号，因此由组合根传一个常量。
actor UserDefaultsRecentVisitStore: RecentVisitStore {

    /// 落盘键的前缀（`GitDuo.` 前缀避免与别的框架 / 扩展写的键撞名）。
    static let keyPrefix = "GitDuo.recentVisits"

    private let defaults: UserDefaults
    private let key: String
    private let backing: InMemoryRecentVisitStore

    /// - Parameter namespace: 账号命名空间（见类型说明的「多账号预留」）。
    init(defaults: UserDefaults = .standard, namespace: String = "default") {
        self.defaults = defaults
        self.key = "\(Self.keyPrefix).\(namespace)"
        self.backing = InMemoryRecentVisitStore(seed: Self.load(from: defaults, key: key))
    }

    func record(
        fullName: String,
        canWrite: Bool,
        ownerAvatarURL: URL?,
        at date: Date
    ) async {
        await backing.record(
            fullName: fullName,
            canWrite: canWrite,
            ownerAvatarURL: ownerAvatarURL,
            at: date
        )
        // ⚠️ 存的是**对方归一化之后**的内容（去重 / 置顶 / 裁剪都已生效），
        //    而不是"我刚传进去的那一条" —— 否则落盘内容会与内存内容分叉。
        persist(await backing.visits())
    }

    func visits() async -> [RecentVisit] {
        await backing.visits()
    }

    func clear() async {
        await backing.clear()
        persist([])
    }

    // MARK: - 落盘

    /// 整份覆盖，不做增量。
    ///
    /// 列表最多 6 条，整份写的成本可以忽略；而增量更新要自己维护"删哪条、插到哪"，
    /// 那正是上面说的"重写语义"。
    ///
    /// ⚠️ **不放在 `Task {}` 里异步写**：那样"方法返回了"与"内容真的落盘了"之间会有一个窗口，
    /// 而用户完全可能在这之后立刻杀进程 —— 你写的时候不 await，丢的就是他刚打开过的那一条。
    /// 这里在 actor 内同步完成（`UserDefaults` 的写入本身很快，且在它自己的队列上）。
    private func persist(_ visits: [RecentVisit]) {
        if visits.isEmpty {
            // 清空时把键删掉，而不是留一份 `[]`：设备上少留一条"他用过这个 App"的痕迹。
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = RecentVisit.encodeList(visits) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [RecentVisit] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return RecentVisit.decodeList(from: data)
    }
}

/// 「最近搜索」的**落盘实现**（TECH_SPEC §7.1 存储表：`UserDefaults` + JSON）。
///
/// 与 `UserDefaultsRecentVisitStore` 完全同一分工：去重 / 置顶 / 裁到 8 条那三件事
/// 在领域包（`InMemorySearchHistoryStore`，逐字移植原型 `recordTerm`），
/// 编解码走 `SearchHistoryCoding`（有往返测试）。本类型只做"读出来 → 交给它 → 存回去"。
///
/// ## ⚠️ 键名前缀必须与「最近访问」不同
///
/// `GitDuo.searchHistory` vs `GitDuo.recentVisits`。两者是两份独立数据，
/// 共用前缀只是在等一次"清 A 顺手清掉 B"的事故（`signOut()` 里那几行紧挨着）。
///
/// 除此之外它与 `UserDefaultsRecentVisitStore` 逐条同构 —— 包括 `clear()` 删键而不是
/// 留一份 `[]`（读取端分辨不出这两者，能不落痕就不落痕）。
actor UserDefaultsSearchHistoryStore: SearchHistoryStore {

    static let keyPrefix = "GitDuo.searchHistory"

    private let defaults: UserDefaults
    private let key: String
    private let backing: InMemorySearchHistoryStore

    /// - Parameter namespace: 账号命名空间（多账号预留，同 `UserDefaultsRecentVisitStore`）。
    init(defaults: UserDefaults = .standard, namespace: String = "default") {
        self.defaults = defaults
        self.key = "\(Self.keyPrefix).\(namespace)"
        self.backing = InMemorySearchHistoryStore(seed: Self.load(from: defaults, key: key))
    }

    func record(term: String) async {
        await backing.record(term: term)
        // ⚠️ 与最近访问同一理由：存的是**对方归一化之后**的顺序，不是"我刚传进去的那一条"。
        persist(await backing.terms())
    }

    func terms() async -> [String] {
        await backing.terms()
    }

    func clear() async {
        await backing.clear()
        // 与 `UserDefaultsRecentVisitStore.clear()` 一样删键：留一份 `[]` 与"从没搜过"
        // 在读取端没有区别，能不落痕就不落痕。
        defaults.removeObject(forKey: key)
    }

    private func persist(_ terms: [String]) {
        guard let data = SearchHistoryCoding.encode(terms) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [String] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return SearchHistoryCoding.decode(from: data)
    }
}

/// 分支记忆的**落盘实现**（TECH_SPEC §9.4.1、决策 #55、PRD §3.10）。
///
/// 与「最近访问」「最近搜索」两条同一分工：行为在领域包（`BranchMemoryStore`
/// 的协议 + `InMemoryBranchMemoryStore` 的参照实现），本类型只管存取。
///
/// ## ⚠️ 与前两个 store 的一处**关键不同**
///
/// 前两个的行为是"去重 / 置顶 / 裁到 N 条"——那需要把整份列表交给领域实现再过一遍，
/// 所以它们持有一个 `InMemory…` 的实例。**本类型不能那么做**：
/// `BranchMemoryStore` 只有四个方法，**没有任何"读出全部"的入口**
/// （协议的形状是"按仓库查一条"，那不是缺陷 —— 界面从不需要整份映射）。
/// 于是这里直接持有 `[String: String]`，四个方法各自维护它。
///
/// 这也意味着 `InMemoryBranchMemoryStore` 在这里**用不上** —— 它只服务测试与预览，
/// 而两者对同一份数据的两套实现必须保持行为一致（都只有"读一条 / 写一条 / 删一条 / 清空"，
/// 分支记忆本身没有去重与排序可言）。
///
/// ## 存储形状：`[仓库全名: 分支名]`
///
/// 用 `UserDefaults` 的原生字典（plist 支持），不走 JSON —— 类型就是 `[String: String]`，
/// 中间加一层编解码只会多一处能出错的地方（前两个 store 需要自定义编码是因为
/// 它们的元素是**结构体**）。
///
/// ⚠️ **已知缺口，待评审**：本映射**没有容量上限**（另外两个 store 分别裁到 6 / 8 条）。
/// 规格（PRD §3.10 / §9.4.1）没有给上限，所以这里**不擅自加**一个
/// —— 加一个数字就是替用户拍板。代价是重度使用者会攒下几千个键
/// （每条几十字节，实际影响很小）。
///
/// ⚠️ 它是**账号绑定数据**：分支名会暴露私有仓库的结构 ⇒ `signOut()` 的 ③ 步必须
/// `clear()`（§3.6）。
actor UserDefaultsBranchMemoryStore: BranchMemoryStore {

    static let keyPrefix = "GitDuo.branchMemory"

    private let defaults: UserDefaults
    private let key: String
    private var storage: [String: String]

    /// - Parameter namespace: 账号命名空间（多账号预留，同 `UserDefaultsRecentVisitStore`）。
    init(defaults: UserDefaults = .standard, namespace: String = "default") {
        self.defaults = defaults
        self.key = "\(Self.keyPrefix).\(namespace)"
        self.storage = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    func branch(for fullName: String) async -> String? {
        storage[fullName]
    }

    func remember(branch: String, for fullName: String) async {
        storage[fullName] = branch
        persist()
    }

    /// ⚠️ 与 `remember(branch:for:)` 分开是协议就定下的（见 `BranchMemoryStore`）：
    /// "从没记过"与"记了一个空串"在读取侧走同一条路，但**存进去的东西不同** ——
    /// 这里把键真的删掉，而不是写一个空串。
    func forget(fullName: String) async {
        storage[fullName] = nil
        persist()
    }

    func clear() async {
        storage = [:]
        // 与另外两个 store 一样删键而不是留一份空字典：读取端分辨不出这两者，
        // 能不落痕就不落痕。
        defaults.removeObject(forKey: key)
    }

    /// 整份覆盖（同 `UserDefaultsRecentVisitStore.persist` 的取舍：增量更新要自己维护
    /// "删哪条、插到哪"，而那是把语义重写一遍）。
    ///
    /// ⚠️ 同样是**同步写完再返回**：不放进 `Task {}` 的话，"方法返回了"与"真的落盘了"
    /// 之间会有一个窗口，而用户完全可能在这之后立刻切分支 / 杀进程。
    private func persist() {
        if storage.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(storage, forKey: key)
    }
}

/// 评论草稿的**落盘实现**（决策 #59、TECH_SPEC §7.1 存储表：`UserDefaults` + JSON）。
///
/// 与「最近访问」「最近搜索」「Star 基线」三条同一分工：语义在领域包
/// （`InMemoryCommentDraftStore` —— 含"正文变空即删"那条），编解码走
/// `CommentDraft.encodeList` / `decodeList`（有往返测试）。本类型只做
/// "读出来 → 交给它 → 存回去"。
///
/// ## ⚠️ 为什么要包一层内存实现，而不是直接维护一个字典
///
/// `BranchMemoryStore` 那条**不能**这么做的理由（协议没有"读出全部"的入口）
/// 在这里不成立：本协议有四个方法，而领域层额外给了 `InMemoryCommentDraftStore.allDrafts()`
/// 供落盘取整份。既然能借到，就必须借 —— `save` 的那条"空即删"规则
/// 若在本类型里再实现一遍，就成了第二份实现，而落盘这一份**没有测试**
/// （App target 没有测试 target），它会成为那个没人看守的分支。
///
/// ## 存储形状：整份数组
///
/// 同 `UserDefaultsStarSnapshotStore`：草稿天然是一个整体（登出时整份清掉、
/// 读到坏的整份作废），拆成 N 条键反而要处理"清了一半"的中间态。
///
/// ⚠️ 它是**账号绑定数据**：草稿里可能有还没发布的正文（一段私事、
/// 一个未公开的漏洞描述）⇒ `signOut()` 的 ③ 步必须 `clear()`（§3.6）。
actor UserDefaultsCommentDraftStore: CommentDraftStore {

    static let keyPrefix = "GitDuo.commentDrafts"

    private let defaults: UserDefaults
    private let key: String
    private let backing: InMemoryCommentDraftStore

    /// - Parameter namespace: 账号命名空间（多账号预留，同 `UserDefaultsRecentVisitStore`）。
    init(defaults: UserDefaults = .standard, namespace: String = "default") {
        self.defaults = defaults
        self.key = "\(Self.keyPrefix).\(namespace)"
        self.backing = InMemoryCommentDraftStore(seed: Self.load(from: defaults, key: key))
    }

    func draft(fullName: String, number: Int) async -> CommentDraft? {
        await backing.draft(fullName: fullName, number: number)
    }

    func save(fullName: String, number: Int, body: String, at date: Date) async {
        await backing.save(fullName: fullName, number: number, body: body, at: date)
        // ⚠️ 存的是**对方归一化之后**的内容（"空即删"已生效），不是"我刚传进去的那一条"
        //    —— 否则落盘内容会与内存内容分叉（同 `UserDefaultsRecentVisitStore.record`）。
        await persistCurrent()
    }

    func discard(fullName: String, number: Int) async {
        await backing.discard(fullName: fullName, number: number)
        await persistCurrent()
    }

    func clear() async {
        await backing.clear()
        // 与另外几个 store 一样删键而不是留一份 `[]`：读取端分辨不出这两者，
        // 能不落痕就不落痕 —— 而这一份留痕的代价格外高（正文级别的隐私）。
        defaults.removeObject(forKey: key)
    }

    private func persistCurrent() async {
        persist(await backing.allDrafts())
    }

    /// 整份覆盖（同 `UserDefaultsRecentVisitStore.persist` 的取舍）。
    ///
    /// ⚠️ **不放进 `Task {}` 里异步写**：那样"方法返回了"与"内容真的落盘了"之间
    /// 会有一个窗口，而用户完全可能在这之后立刻杀进程 ——
    /// 丢掉的正是他刚敲进去的那几个字（也正是 `draft` 的 `didSet` 要解决的同一件事）。
    private func persist(_ drafts: [CommentDraft]) {
        if drafts.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = CommentDraft.encodeList(drafts) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [CommentDraft] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return CommentDraft.decodeList(from: data)
    }
}

/// Star 基线的**落盘实现**（TECH_SPEC §7.1 / §9.10.2）。
///
/// 与 `UserDefaultsRecentVisitStore` 同一分工：语义在领域包（`InMemoryStarSnapshotStore`），
/// 本类型只管存取。
///
/// ⚠️ 它属于**账号数据** —— 登出时必须清掉（`AppEnvironment.signOut`），
/// 否则换账号登录会拿着别人的基线算出凭空出现的增幅。
actor UserDefaultsStarSnapshotStore: StarSnapshotStore {

    static let keyPrefix = "GitDuo.starSnapshots"

    private let defaults: UserDefaults
    private let key: String
    private let backing: InMemoryStarSnapshotStore

    init(defaults: UserDefaults = .standard, namespace: String = "default") {
        self.defaults = defaults
        self.key = "\(Self.keyPrefix).\(namespace)"
        self.backing = InMemoryStarSnapshotStore(seed: Self.load(from: defaults, key: key))
    }

    func snapshot(for fullName: String) async -> StarSnapshot? {
        await backing.snapshot(for: fullName)
    }

    func record(fullName: String, stars: Int, at date: Date) async {
        await backing.record(fullName: fullName, stars: stars, at: date)
        persist(await backing.allSnapshots())
    }

    func clear() async {
        await backing.clear()
        defaults.removeObject(forKey: key)
    }

    private func persist(_ snapshots: [StarSnapshot]) {
        guard let data = StarSnapshot.encodeList(snapshots) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [StarSnapshot] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return StarSnapshot.decodeList(from: data)
    }
}
