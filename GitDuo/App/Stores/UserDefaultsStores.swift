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

    func record(fullName: String, canWrite: Bool, at date: Date) async {
        await backing.record(fullName: fullName, canWrite: canWrite, at: date)
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
