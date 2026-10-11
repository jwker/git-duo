import Foundation
import GitHubAPI

/// 「当前令牌能对哪些仓库写 Star」—— 一个仓库点得动 / 点不动那颗星标的**唯一**判据。
///
/// 依据：TECH_SPEC **§3.5.5**（真机实测定案）、决策 **#80**、PRD §4.4 / §4.13 / §4.18。
///
/// ## 为什么需要它（一句话版）
///
/// GitHub App 的用户访问令牌，**写 Star 只对「App 安装范围内的仓库」有效** ——
/// 自己的仓库 `PUT` 回 **204**、别人的仓库回 **403**
/// `Resource not accessible by integration`（REST 与 GraphQL 两条路同样被拒）。
/// 而本 App 的安装范围**只是你自己名下的账号** ⇒ 探索页 / 搜索 / 「我的 Star」里的
/// **绝大多数仓库永远写不了**，UI 必须如实说出来，而不是让用户白点一下再收到
/// `操作失败 · 请重试`（那句话把用户送向"重试"，而重试永远不会成功）。
///
/// ## ⚠️ 三种状态，其中两种都**不拦**
///
/// | 状态 | 判据 | 拦不拦 |
/// |---|---|---|
/// | `.unknown`（还没查到 / 拉取失败） | —— | **不拦** |
/// | `.known`，`owner` 命中安装账号名单 | 确定可写 | 不拦 |
/// | `.known`，`owner` 完全没命中 | 确定不可写 | **拦** |
///
/// 只有"**确定不可写**"才拦，这不是偷懒，是取舍算过账的：
/// **误灰一个本来能点的按钮**（用户以为没这功能、就此放弃）比
/// **漏灰一个不能点的按钮**（用户点一下、收到一句准确的话）**糟得多**。
/// 同 §8.5 那条"还没加载出来 ≠ 确实没有"。
///
/// ⚠️ **一个已知的不确定**：安装的 `repository_selection` 可能是 `"selected"`
/// （只勾了部分仓库）。那种情况下我们知道"这个账号装了"、但**不知道这个具体仓库在不在里面**
/// ⇒ 按**可写**处理（乐观）。精确判定要再查
/// `GET /user/installations/{id}/repositories`，**留作技术储备**（同 §3.5.4 那条）。
public enum StarWriteScope: Sendable, Hashable {

    /// **还没查到** —— 未登录、请求失败、或那次请求还没回来。
    ///
    /// ⚠️ 它与「确定不可写」是**两件事**，别折成一个 `false`：
    /// 折掉之后"我们还没问到"会变成"你不能点"，而那是一句**没有依据的断言**。
    case unknown

    /// 查到了：**已安装本 App 的账号登录名**（`GET /user/installations` 的 `account.login`）。
    case known(accounts: Set<String>)

    /// 这个仓库写得动吗。
    ///
    /// - Parameter fullName: `owner/name` 形状的仓库全名。
    /// - Returns: **只有"查到了、且 owner 不在名单里"才返回 `false`**；其余一律 `true`。
    ///
    /// ⚠️ **比较大小写不敏感**：GitHub 的登录名本身大小写不敏感，
    /// 而 `owner/name` 里的大小写是用户/服务端怎么写的就怎么来的
    /// ⇒ 按 `==` 比会让"自己组织名下的仓库"认不出自己，而那一条在屏幕上
    /// **看起来完全正常**（只是按钮莫名其妙是灰的）。
    /// ⚠️ 规范化的责任放在**比较这一侧**（而不是"构造时统一小写"）：
    /// 后者的正确性依赖每一个构造点都记得做，而那是一条**迟早会被违反的不变量**。
    ///
    /// ⚠️ `fullName` 形状不认识时**不拦** —— 走到这里说明界面上已经有一个仓库了，
    /// 而"名字解析不出来"是另一类问题的症状，不该在这里表现成"不能 Star"。
    public func canWrite(fullName: String) -> Bool {
        guard case let .known(accounts) = self else { return true }
        guard let (owner, _) = try? RepositoryMapper.splitFullName(fullName) else { return true }
        return accounts.contains { $0.caseInsensitiveCompare(owner) == .orderedSame }
    }
}

/// 「哪些账号装了 GitDuo」的数据来源 —— 领域层与网络层之间的接缝（写法同 `StarDataSource`）。
///
/// ⚠️ 它是**空扩展体**那一类接缝（`extension GitHubInstallationsEndpoint: StarScopeDataSource {}`），
/// 删掉之后编译照样过、其余测试照样绿 ⇒ 清点在 `RepoEndpointsContractTests`（**新增接缝要同步加一行**）。
public protocol StarScopeDataSource: Sendable {

    /// `GET /user/installations` → 已安装本 App 的**账号登录名**（user 或 org）。
    ///
    /// ⚠️ 端点的响应里还有安装 id、`repository_selection` 等字段，**故意只取 `login`** ——
    /// 判定只需要"哪些账号"这一个集合；多取那些字段会诱使调用方在这里做第二套判断
    /// （而判据只能有一处，就是这个类型上面那个 `canWrite(fullName:)`）。
    func installedAccounts() async throws -> [String]
}

/// 让真实端点满足上面的接缝（协议是我们自己声明的，不是追溯适配 —— 同 `StarDataSource`）。
///
/// ⚠️ **这是一个空的扩展体**：删掉之后**编译照样过、其余测试照样绿**，
/// 一直到组合根装配时才炸。⇒ 清点在 `RepoEndpointsContractTests`。
extension GitHubInstallationsEndpoint: StarScopeDataSource {}

/// 取一次「Star 可写范围」—— 一次请求、一页 100 条（用户装不了几个 App，够用）。
///
/// ## ⚠️ 失败**不抛错**，折叠成 `.unknown`
///
/// 与 `ToggleStar.initialState` 同一处置：这次查询失败**不该让任何页面打不开**
/// （页面上的头部、目录、贡献者与它无关）。而 `.unknown` 的语义恰好就是"不拦"
/// ⇒ 界面照常可点，写请求自己去失败，**那时再给一句准确的话**。
/// 这是"失败不要静默吞掉"的正确落法：**不是**把错误藏起来，
/// 而是把它推迟到"真正需要它的那一步"。
public struct LoadStarWriteScope: Sendable {

    private let source: any StarScopeDataSource

    public init(source: any StarScopeDataSource) {
        self.source = source
    }

    /// 查一次。**不抛错**（见类型说明）。
    public func run() async -> StarWriteScope {
        do {
            let accounts = try await source.installedAccounts()
            return .known(accounts: Set(accounts))
        } catch {
            return .unknown
        }
    }
}

/// 「Star 可写范围」的**会话内缓存** —— 全 App 只有一个实例（组合根装配）。
///
/// ## 为什么要缓存
///
/// 这份名单在一个会话里**基本不变**（它由"你把 GitDuo 装在哪几个账号上"决定），
/// 而每一个仓库详情页都要问它一次 ⇒ 不缓存就是"进一个仓库多一次主桶请求"，
/// 且每次都要等它回来才知道按钮该不该灰。
///
/// ## ⚠️ 只在成功时缓存
///
/// `.unknown` 的语义是"**这次没问到**"。把它缓存下来等于
/// **把一次失败变成永久失败** —— 后面每一屏都按"不知道"处理（而那还好，只是不拦），
/// 真正糟的是它**掩盖了"其实问得到"这件事**：用户断网进了一次详情页，
/// 之后就再也没有一次查询会重试。⇒ 失败不写缓存，下次进页自然会再问一次。
public actor StarWriteScopeCache {

    /// 已经拿到的那一份；`nil` = 还没拿到（或刚被 `clear()`）。
    private var cached: StarWriteScope?

    /// 在途的那一次查询。两个调用点同时进页时**共用它**，不打两次请求。
    private var inFlight: Task<StarWriteScope, Never>?

    /// **代次** —— 每次 `clear()` 加一，用来把"上一代的结果"挡在缓存之外（见 `current()`）。
    private var generation = 0

    private let loader: LoadStarWriteScope

    public init(loader: LoadStarWriteScope) {
        self.loader = loader
    }

    /// 当前这一份；没拿到就去拿一次（同一时刻最多一次在途请求）。
    public func current() async -> StarWriteScope {
        if let cached { return cached }
        if let inFlight { return await inFlight.value }

        let loader = self.loader
        let generation = self.generation
        let task = Task { await loader.run() }
        inFlight = task

        let scope = await task.value
        inFlight = nil

        // ⚠️ **两个条件都不可少**：
        // ① 只在 `.known` 时缓存（见类型说明）；
        // ② 只在**代次没变**时缓存 —— 这一段 await 期间可能发生过 `clear()`
        //    （用户登出），那时这个结果属于**上一个账号**，写回去就是
        //    把上一个账号的授权范围留在新账号的界面上。
        if generation == self.generation, case .known = scope {
            cached = scope
        }
        return scope
    }

    /// 丢掉缓存（**登出时必须调**）。
    ///
    /// ⚠️ 这份名单是**账号数据** —— 换个人登录，能写的仓库也换了（同最近访问 /
    /// 分支记忆，`TECH_SPEC §3.6` 第 ③ 步）。
    ///
    /// ⚠️ 它**不取消在途的那一次请求**（取消一个已经在飞的读没有意义），
    /// 靠的是上面那个**代次**比对把结果挡在外面 —— 这正是那条比对存在的全部理由，
    /// 少了它就会出现"登出之后，上一个账号的范围又被写回缓存"。
    public func clear() {
        cached = nil
        generation += 1
    }
}
