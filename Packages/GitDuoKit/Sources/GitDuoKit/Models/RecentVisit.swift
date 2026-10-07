import Foundation
import GitDuoCore

/// 一条"最近访问"记录（PRD §3.13 / TECH_SPEC §9.13）。
///
/// 依据：原型 `scripts/04-search.js` 的 `recentRow(v)` —— `{n: 仓库全名, t: 相对时间}`。
/// 差别在于：原型把**显示串**（`'刚刚'` / `'昨天'`）直接存进数组，本类型存**时刻**，
/// 文案由 `RelativeTime` 现算 —— 否则一条"刚刚"会永远停在"刚刚"（App 挂着不动时尤其明显）。
public struct RecentVisit: Identifiable, Sendable, Hashable, Codable {

    /// 仓库全名（`owner/name`）。**它就是主键** —— 同一仓库反复访问只留最新一条。
    public let fullName: String

    /// 访问时刻。
    public let visitedAt: Date

    /// **打开这条记录时，那个仓库是不是可写的**（2026-10-06 补，PRD §3.13）。
    ///
    /// ## 为什么它必须存下来
    ///
    /// 首页那一行点进去要分流到「自己的仓库详情」（§4.4）还是「他人只读页」（§4.13），
    /// 而**只读态必须在进入之前定下**（铁律 #7）。本机只存全名的话，这份归属就丢了 ——
    /// 剩下的只有"拿全名去猜"，而那种猜法在 Fork / 组织仓库 / 协作者仓库上都会判错。
    ///
    /// ## 为什么不需要任何额外请求
    ///
    /// **写入方本来就知道**：它正在渲染的那个页面就是由路由按可写性选出来的
    /// （`.repoDetail` ⇒ `true`，`.exploreRepoDetail` ⇒ `false`）。所以这是"把当时已知的
    /// 一个事实顺手记下"，不是"事后补一次查询"。
    ///
    /// ⚠️ 它记录的是**访问当时**的归属。用户后来 Fork 了这个仓库、或权限被改掉，
    /// 这一行会沿用旧值 —— 那没关系：他再打开一次就会刷新成新值，
    /// 而点进去看到的页面本身还会做一次真实的权限校验（这是"入口的提示"与"出口的权威"
    /// 之间正常的强弱关系）。
    public let canWrite: Bool

    /// 去重依据 = 仓库全名（原型 `RECENT.filter(v => v.n !== n)`）。
    public var id: String { fullName }

    /// - Parameter canWrite: **必须显式给出**（没有默认值）。给一个默认值意味着
    ///   "忘了传"也能编译通过，而那个默认值会让首页永远分错流 —— 而且看起来完全正常。
    public init(fullName: String, canWrite: Bool, visitedAt: Date) {
        self.fullName = fullName
        self.canWrite = canWrite
        self.visitedAt = visitedAt
    }

    /// 相对文案（`刚刚` / `昨天` / `2 天前`…）。
    public func timeLabel(now: Date) -> String {
        RelativeTime.string(from: visitedAt, now: now)
    }
}

// MARK: - 落盘编解码

extension RecentVisit {

    /// 落盘用的编码（TECH_SPEC §7.1：**UserDefaults + JSON**）。
    ///
    /// ## 为什么编解码写在领域层，而不是 App 的落盘实现里
    ///
    /// App target 没有测试 target。而"存进去的东西取不回来"是**最安静的一类故障**：
    /// 不报错、不崩溃，只是每次冷启动后最近访问都是空的。
    /// 两个方向写在同一处（且在本包里），才能让 `RecentVisitStoreTests` 用一次往返把它钉住。
    ///
    /// ⚠️ **两个方向必须用同一份配置** —— `JSONEncoder` / `JSONDecoder` 都取默认值
    /// （日期走 `deferredToDate`）。分开写就会有一天某人只把编码那侧改成 ISO8601，
    /// 而解码那侧照旧：症状是"历史记录全部消失"，且没有任何提示。
    public static func encodeList(_ visits: [RecentVisit]) -> Data? {
        try? JSONEncoder().encode(visits)
    }

    /// 落盘数据的解码。**解不出就返回空数组**，不抛错。
    ///
    /// 理由：这不值得让首页打不开。旧版本写下的格式、被外部改坏的文件、
    /// 系统清理掉一半的数据 —— 任何一种都只该让"最近访问"退化成空态，
    /// 而不是把整个首页变成错误屏。
    public static func decodeList(from data: Data) -> [RecentVisit] {
        (try? JSONDecoder().decode([RecentVisit].self, from: data)) ?? []
    }
}
