import Foundation

/// 一次 Star 数的快照（TECH_SPEC §9.10.2）。
///
/// GitHub 的任何接口都**不给 star 增速** —— 只能自己留一份基线，下次再看时相减。
public struct StarSnapshot: Sendable, Hashable, Codable {

    public let fullName: String
    public let stars: Int

    /// 采样的时刻。保留它是为了将来能判断"这份基线有多旧"（目前只用于排查）。
    public let fetchedAt: Date

    public init(fullName: String, stars: Int, fetchedAt: Date) {
        self.fullName = fullName
        self.stars = stars
        self.fetchedAt = fetchedAt
    }
}

// MARK: - 落盘编解码

extension StarSnapshot {

    /// 落盘用的编码（`{fullName: [StarSnapshot]}` 的数组形态，TECH_SPEC §7.1）。
    ///
    /// ⚠️ 整份基线**当成一个数组存**，不是逐仓库一条键：它天然是一个整体
    /// （登出时整份清掉、读到坏的整份作废），拆成 N 条键反而要处理"清了一半"的中间态。
    public static func encodeList(_ snapshots: [StarSnapshot]) -> Data? {
        try? JSONEncoder().encode(snapshots)
    }

    /// 解码；解不出返回空数组（同 `RecentVisit.decodeList` 的取向：
    /// 基线读丢了只会让增幅**这一轮不显示**，不该让探索页打不开）。
    public static func decodeList(from data: Data) -> [StarSnapshot] {
        (try? JSONDecoder().decode([StarSnapshot].self, from: data)) ?? []
    }
}

/// Star 基线的存储（TECH_SPEC §9.10.2：`StarSnapshotStore`，`{fullName: (stars, fetchedAt)}`）。
///
/// ⚠️ 它属于**账号数据** —— 登出时随其余本地数据一并清理（§9.13 的清理口径）。
/// 否则换账号登录会拿着别人的基线算出**凭空出现的增幅**。
public protocol StarSnapshotStore: Sendable {

    func snapshot(for fullName: String) async -> StarSnapshot?

    /// 记录基线。**首次见到某仓库时只写基线、不显示增幅**（§9.10.2）。
    func record(fullName: String, stars: Int, at date: Date) async

    func clear() async
}

/// 内存实现 —— 单测与预览用；App 层用落盘实现。
public actor InMemoryStarSnapshotStore: StarSnapshotStore {

    private var storage: [String: StarSnapshot]

    public init(seed: [StarSnapshot] = []) {
        self.storage = Dictionary(uniqueKeysWithValues: seed.map { ($0.fullName, $0) })
    }

    public func snapshot(for fullName: String) async -> StarSnapshot? {
        storage[fullName]
    }

    /// 全部基线，**按仓库全名升序**。
    ///
    /// 落盘实现要用它把整份基线写出去（`StarSnapshotStore` 协议上没有"列出全部"，
    /// 因为领域层不需要这个能力 —— 但"存一份东西"需要一个确定的顺序）。
    ///
    /// ⚠️ 排序不是洁癖：`Dictionary` 的迭代顺序**每次运行都可能不同**，
    /// 直接写出去会让"同一份基线两次落盘得到两个不同字节序列"，
    /// 而任何按内容比对的地方（测试、去重、将来可能的同步）都会因此变成间歇性失败。
    public func allSnapshots() async -> [StarSnapshot] {
        storage.values.sorted { $0.fullName < $1.fullName }
    }

    public func record(fullName: String, stars: Int, at date: Date) async {
        storage[fullName] = StarSnapshot(fullName: fullName, stars: stars, fetchedAt: date)
    }

    public func clear() async {
        storage = [:]
    }
}
