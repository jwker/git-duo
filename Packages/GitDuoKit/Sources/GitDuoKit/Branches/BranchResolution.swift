import Foundation
import GitHubAPI

/// 进入一个仓库时，当前分支怎么定 —— TECH_SPEC §9.4.1、PRD §3.10。
///
/// ## 为什么不是"一个全局 `currentBranch`"
///
/// 全局变量会造出一个**未定义状态**：从 A 仓库切到 `feature/x`，再进 B 仓库，
/// B 也显示 `feature/x` —— 而 B 根本没有这条分支。此时页面上没有任何东西是错的
/// （分支名是个合法字符串），它只是**不属于这个仓库**，所以不会报错、
/// 只会在某一次点文件时 404。
///
/// 记忆因此按**仓库全名**分桶（`BranchMemoryStore`），解析规则只有三条（§9.4.1 表）。
///
/// ## 为什么解析必须是**两段式**（决策 #55）
///
/// "记忆值是否仍存在"要等 `GET …/branches` 回来才知道，而首屏的 contents 请求
/// **不能**等它 —— 那是一个纯粹的、什么都不换来的 RTT。所以：
///
/// 1. `initial(remembered:defaultBranch:)` —— **立即**拿一个值去发请求（不串行等待）；
/// 2. `resolved(remembered:available:defaultBranch:)` —— 分支列表回来后校正；
/// 3. `shouldSilentlyRetry(after:attemptedBranch:defaultBranch:)` —— 第 1 步那次
///    若因 `ref` 不存在吃了 404，**静默重发一次**（见下）。
public enum BranchResolver {

    /// 第一段：**立即**决定用哪条分支发首屏请求（无记忆 ⇒ 默认分支）。
    ///
    /// 不做任何"是否仍存在"的校验 —— 那正是第二段的事，此刻拿不到依据。
    public static func initial(remembered: String?, defaultBranch: String) -> String {
        guard let remembered, !remembered.isEmpty else { return defaultBranch }
        return remembered
    }

    /// 第二段：分支列表到手后的校正（§9.4.1 表的三条）。
    ///
    /// | 情形 | 结果 |
    /// |---|---|
    /// | 记忆的分支仍在列表里 | 沿用 |
    /// | 记忆的分支已不存在 | 回落 `defaultBranch`，`didFallBack == true` |
    /// | 无记忆 | `defaultBranch`，`didFallBack == false` |
    ///
    /// ⚠️ **"无记忆"不算回落** —— 它俩都返回 `defaultBranch`，但只有前者需要
    /// "失效该仓库的 contents / commits 缓存"。把两者合成一个"反正都是默认分支"
    /// 会让首次进入仓库时白清一次缓存（用户会看到多一次加载）。
    public static func resolved(
        remembered: String?,
        available: [String],
        defaultBranch: String
    ) -> BranchResolution {
        guard let remembered, !remembered.isEmpty else {
            return BranchResolution(branch: defaultBranch, didFallBack: false)
        }
        // ⚠️ 空列表视为"**无法验证**"，不是"什么都不存在"。
        //    若把空列表当成"记忆值不存在"，一个临时的空响应就会把用户的记忆值清掉，
        //    而清掉的动作是**写盘**的（`forget`）—— 那是一次不会自愈的损失。
        //    真出现空列表（仓库确实没有任何分支）时，`defaultBranch` 也会随之失效，
        //    那属于仓库本身的状态被外部改坏，不是这里该吸收的。
        guard !available.isEmpty else {
            return BranchResolution(branch: remembered, didFallBack: false)
        }
        if available.contains(remembered) {
            return BranchResolution(branch: remembered, didFallBack: false)
        }
        return BranchResolution(branch: defaultBranch, didFallBack: true)
    }

    /// 第三段：首屏那次 contents 吃了 404，**要不要静默重发一次**（决策 #55 第 3 条）。
    ///
    /// ## 为什么需要这一条
    ///
    /// 两段式的第 1 步是"拿记忆值先发"——若那条分支**刚被删掉**，这次请求会回 404。
    /// 不重发的话，用户看到的是"不存在或无权访问"（§4.3：404 与无权限在 GitHub 侧
    /// **被混同**，文案只能笼统），然后**下一帧自己好了**。那个自愈过程对用户
    /// 表现为"这个 App 报错、然后又没事了"，而它本该被回落规则**无声吸收**。
    ///
    /// ## ⚠️ 判据里必须有 `attemptedBranch != defaultBranch`
    ///
    /// 否则：用默认分支请求 → 404 → 回落"到默认分支" → 再发一次 → 又 404 → ……
    /// `defaultBranch` 本身吃 404 意味着**仓库整体不可达**（或没权限），
    /// 那种情况必须**如实报错**，不能靠重试把它藏起来。
    public static func shouldSilentlyRetry(
        after error: GitHubError,
        attemptedBranch: String,
        defaultBranch: String
    ) -> Bool {
        guard case .notFound = error else { return false }
        return attemptedBranch != defaultBranch
    }
}

/// 一次分支解析的结论。
public struct BranchResolution: Equatable, Sendable {

    /// 该仓库当前该用的分支名。
    public let branch: String

    /// 记忆值失效、回落到了默认分支。
    ///
    /// ⚠️ 调用方拿到 `true` 时有两件事要做（都不是可选的）：
    /// ① `BranchMemoryStore.forget(fullName:)` —— 把失效的记忆清掉；
    /// ② 失效该仓库的 contents / commits 缓存并重取 ——
    /// 否则会继续按那条已不存在的 `ref` 请求，稳定 404。
    public let didFallBack: Bool

    public init(branch: String, didFallBack: Bool) {
        self.branch = branch
        self.didFallBack = didFallBack
    }
}

/// 当前分支的**按仓库记忆**（PRD §3.10）。
///
/// ## 存储形状：仓库全名 → 分支名
///
/// 不是"一个当前分支 + 一个所属仓库" —— 那样在"切回上一个仓库"时无法恢复现场，
/// 而那正是 PRD §3.10 要的"按仓库分别记忆"。
///
/// ## 它与 `RecentVisitStore` / `SearchHistoryStore` 的两处**有意相同**
///
/// 1. 协议在领域层、落盘实现在 App 组合根（"该是什么行为"与"存在哪"分开）；
/// 2. **写入不触发任何回调 / 观察** —— 记录分支发生在页面渲染路径上，
///    若写入立刻通知重绘，就成了一条「写入 → 重绘 → 再写入」的循环。
///
/// ⚠️ 它是**账号绑定数据**：分支名会暴露私有仓库的结构 ⇒ `signOut()` 的
/// ③ 步必须 `clear()`（TECH_SPEC §3.6）。
public protocol BranchMemoryStore: Sendable {

    /// 该仓库上次用的分支；从未记过则为 `nil`。
    func branch(for fullName: String) async -> String?

    /// 记下该仓库当前用的分支（用户切分支、或解析出结论时写）。
    func remember(branch: String, for fullName: String) async

    /// 抹掉该仓库的记忆（记忆值已失效、或该分支被删）。
    ///
    /// 与 `remember` 分开而不是"写一个空字符串"：空串与"从没记过"在读取侧
    /// 走的是同一条路（`initial` 对两者都返回默认分支），但**存进去的值不同** ——
    /// 落盘实现里空串会占一个键，而"没记过"不该占。
    func forget(fullName: String) async

    /// 清空全部记忆（登出）。
    func clear() async
}

/// 内存实现 —— 单测与预览用；App 层用落盘实现。
public actor InMemoryBranchMemoryStore: BranchMemoryStore {

    private var storage: [String: String]

    /// - Parameter seed: 预置记忆（测试与预览用）。
    public init(seed: [String: String] = [:]) {
        self.storage = seed
    }

    public func branch(for fullName: String) async -> String? {
        storage[fullName]
    }

    public func remember(branch: String, for fullName: String) async {
        storage[fullName] = branch
    }

    public func forget(fullName: String) async {
        storage[fullName] = nil
    }

    public func clear() async {
        storage = [:]
    }
}
