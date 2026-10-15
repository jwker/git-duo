import Foundation

/// 「最近访问」的存储（PRD §3.13 / TECH_SPEC §9.13）。
///
/// 依据：原型 `scripts/04-search.js`
/// ```js
/// function recordVisit(n){ RECENT = [{n, t:'刚刚'}].concat(RECENT.filter(v=>v.n!==n)).slice(0,6); }
/// ```
/// 三件事一次做完：**去重**（先滤掉同仓库的旧记录）· **置顶**（新的拼在最前）· **裁剪到 6 条**。
///
/// ⚠️ **写入动作不得直接触发首页重绘**（TECH_SPEC §9.13 明写）。
/// 用户点开一个仓库 → 详情页写入 → 若写入立刻通知首页重绘，而重绘又会读取并写回，
/// 就成了一条「写入 → 重绘 → 再写入」的循环。故本协议**刻意不含任何观察 / 回调入口**：
/// 落盘归存储层，首页只在**下次出现时**读取。
public protocol RecentVisitStore: Sendable {

    /// 最多保留几条（PRD §3.13：最多 6 条；也与个人主页置顶上限一致）。
    static var maxCount: Int { get }

    /// 记录一次访问：按 `fullName` 去重后置顶，并裁剪到 `maxCount`。
    ///
    /// - Parameter canWrite: 打开这个仓库时它是否可写 —— **由调用方给出**（它正在渲染的页面
    ///   就是按可写性选出来的），见 `RecentVisit.canWrite`。存下它是为了让首页那一行
    ///   在**下次点开时**还能正确分流（PRD §3.13、铁律 #7）。
    /// - Parameter ownerAvatarURL: 记录**此刻**已知的 owner 头像地址；**此刻还不知道就传
    ///   `nil`**（详情页是"先记访问、再取数"，地址要等取数成功后的**补记**带进来 ——
    ///   补记也走本方法，去重逻辑保证仍只留一条）。`nil` 的行回退首字母兜底圆。
    func record(
        fullName: String,
        canWrite: Bool,
        ownerAvatarURL: URL?,
        at date: Date
    ) async

    /// 读取全部记录，**最新在前**。
    func visits() async -> [RecentVisit]

    /// 清空本机历史（§5.1 清除最近访问确认弹层）。
    ///
    /// ⚠️ 只清本机浏览历史 —— 不影响仓库本身，也不影响首页的**置顶仓库**（那是 GitHub 侧数据）。
    func clear() async
}

extension RecentVisitStore {
    public static var maxCount: Int { 6 }
}

/// 内存实现 —— 供单测与预览使用。
///
/// App 层用的是落盘实现（`UserDefaults` / 文件）。**刻意不把落盘实现放进本包**：
/// 本包是领域层，只定义"该是什么行为"；"存在哪、怎么存"属基础设施，在 App 组合根里装配。
public actor InMemoryRecentVisitStore: RecentVisitStore {

    private var storage: [RecentVisit]

    /// - Parameter seed: 预置记录（测试与预览用）。
    ///
    /// ⚠️ **seed 不假设是有序的**：这里按 `visitedAt` 降序重排、按仓库全名去重（同仓库只留
    /// 最新一条），再裁到 `maxCount`。理由是 `record` 的前提就是"存储是最新在前" ——
    /// 如果 seed 照传入顺序收下，一份从磁盘读回来、顺序乱的旧数据会让**下一次 `record`
    /// 把新访问插到一个错误的位置**，而这种错只在"装过旧版本 App"的用户身上复现。
    /// 让存储自洽，比指望每个调用方都排好序可靠。
    public init(seed: [RecentVisit] = []) {
        var seen = Set<String>()
        var ordered: [RecentVisit] = []
        for visit in seed.sorted(by: { $0.visitedAt > $1.visitedAt }) {
            guard seen.insert(visit.fullName).inserted else { continue }
            ordered.append(visit)
        }
        self.storage = Array(ordered.prefix(Self.maxCount))
    }

    public func record(
        fullName: String,
        canWrite: Bool,
        ownerAvatarURL: URL?,
        at date: Date
    ) async {
        // 先滤掉同仓库的旧记录，再把新记录拼到最前 —— 这就是原型的 concat + filter。
        // 顺序不能反：先拼后滤会把刚写进去的这条自己滤掉。
        //
        // ⚠️ 重新访问会**覆盖** `canWrite`。这是有意的：权限可能变了（用户刚 Fork 过来），
        //    而"最近一次见到它时是什么样"比"第一次见到它时是什么样"更接近事实。
        //    `ownerAvatarURL` 同理 —— 取数成功后的补记会覆盖掉进页时的 `nil`；
        //    反过来，EMU 地址过期后的再一次访问也会换成新地址。
        var next = [RecentVisit(
            fullName: fullName,
            canWrite: canWrite,
            visitedAt: date,
            ownerAvatarURL: ownerAvatarURL
        )]
        next.append(contentsOf: storage.filter { $0.fullName != fullName })
        storage = Array(next.prefix(Self.maxCount))
    }

    public func visits() async -> [RecentVisit] {
        storage
    }

    public func clear() async {
        storage = []
    }
}
