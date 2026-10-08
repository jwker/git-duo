import Foundation
import GitHubAPI

/// PR 详情操作区的四档（PRD §4.11 的表格、TECH_SPEC §9.9）。
///
/// | 条件 | 操作区 |
/// |---|---|
/// | 他人仓库 | 文字提示（无按钮） |
/// | 自己的仓库 + 开放 | 合并 + 关闭 |
/// | 自己的仓库 + 已关闭 | 重新打开 |
/// | 自己的仓库 + 已合并 | **无操作按钮** |
///
/// ## 为什么做成枚举而不是让视图写四个 `if`
///
/// 四个分支各自的判据是"可写性 + 状态"的**组合**，而组合在视图里会散成
/// `if !readOnly && state == .open { … } else if !readOnly && state == .closed { … }`
/// 这种写法 —— 它有一个**看不出来的**失败模式：漏掉某一档时那个分支什么都不画，
/// 而"操作区是空的"看起来像一个正常状态。
/// 收成枚举之后，`switch` 是穷尽的，漏一档编译不过。
///
/// ⚠️ **可写性来自路由参数**（`Route.prDetail(readOnly:)`），不是在这里查权限：
/// 铁律 #7 —— 必须在**进入详情页之前**就定下"自己的仓库"还是"他人仓库"，
/// 否则会先画出一个能点的合并按钮、再在请求失败时改口。
public enum PullOperationAvailability: Sendable, Hashable {

    /// 他人仓库：只有一句文字提示。
    case readOnly

    /// 自己的仓库 + 开放：合并（弹层）/ 关闭。
    case mergeAndClose

    /// 自己的仓库 + 已关闭（未合并）：重新打开。
    case reopen

    /// 自己的仓库 + 已合并：**没有任何操作按钮**。
    ///
    /// ⚠️ 它与 `readOnly` 不是一回事：一个说"你没权限"，一个说"这个 PR 已经结束了"。
    /// 两者的区别在屏幕上就是"有没有那句提示"。
    case noOperations

    /// 判据（唯一一处）。
    ///
    /// ⚠️ **顺序**：先判 `readOnly` —— 他人仓库的 PR 即使是开放的，也只能评论
    /// （PRD §4.11 第一行写的是"文字提示"，没有任何按钮）。
    /// 反过来写会让他人仓库的开放 PR 长出合并按钮。
    public static func decide(readOnly: Bool, state: PullRequestState) -> PullOperationAvailability {
        if readOnly { return .readOnly }
        switch state {
        case .open: return .mergeAndClose
        case .closed: return .reopen
        case .merged: return .noOperations
        }
    }
}

/// 合并的结局（**领域层的**，与数据层的 `PullMergeOutcome` 分开）。
///
/// ## 为什么要再包一层
///
/// 数据层的 `PullMergeOutcome` 说的是"服务端怎么回的"（`sha` / `merged`）。
/// 而界面要的是"**这次合并的结局**" —— 合上了之后它需要更新本地那三样：
/// `state = .merged`、`mergedAt = ?`、对话锁上。
///
/// 那个 `mergedAt` 从哪来是个真问题：**合并的响应体里没有时间**
/// （只有 `sha` / `merged` / `message`，见 `PullMergeResultDTO`）。
/// 唯一诚实的取值是"客户端在收到成功响应这一刻的时间" ——
/// 而它必须由**一个地方**决定（这里），不能散到调用方去各写一个 `Date()`：
/// 那样写出来的两个时间会差几毫秒，而"明明刚合并却显示 3 分钟前"没人查得出来。
public enum PullMergeResult: Sendable, Hashable {

    /// 真的合了。
    ///
    /// - Parameter at: **客户端**在收到成功响应那一刻的时间。
    ///   ⚠️ 它不是服务端的 `merged_at`（响应体里没有那个字段）——
    ///   界面上那句 `已由 X 于 {时间} 合并进 main` 因此是"我们这边的时钟说的"，
    ///   误差是这一次往返的时长。下拉刷新之后详情端点会给回服务端那个准确值。
    /// - Parameter sha: 合并提交的 SHA。**可以是 `nil`**（服务端可能不给）。
    case merged(at: Date, sha: String?)

    /// **这个 PR 现在不能被合并**（405，或 200 但响应体的 `merged` 是 `false`）。
    ///
    /// 成因（已合并过 / draft / 有冲突）在服务端是同一档，**这里不细分** ——
    /// 客户端分不出来（`mergeable` 字段可能已过期，故不取，见 `PullDetailDTO`）。
    case notMergeable
}

/// PR 操作的接缝 —— 由 `GitHubAPI` 的 `GitHubRepoPullsEndpoint` 空扩展体满足。
public protocol PullActionDataSource: Sendable {

    /// `PUT /repos/{o}/{r}/pulls/{n}/merge`。
    ///
    /// ⚠️ **写操作不自动重试**（`HTTPMethod.isSafelyRetryable` 只认 GET）：
    /// 合并重放会真的产生第二个合并提交。
    func mergePull(
        owner: String,
        repo: String,
        number: Int,
        method: PullMergeMethod
    ) async throws -> PullMergeOutcome

    /// `PATCH /repos/{o}/{r}/pulls/{n}` —— `state` 只允许 `open` / `closed`。
    func updatePullState(
        owner: String,
        repo: String,
        number: Int,
        state: String
    ) async throws -> PullDetailDTO
}

/// 让真实端点满足上面的接缝。空扩展体能成立，靠的是**方法签名逐字一致**。
extension GitHubRepoPullsEndpoint: PullActionDataSource {}

/// PR 的三个操作：合并（三方式）/ 关闭 / 重新打开（PRD §4.11 / §5.3、TECH_SPEC §9.9）。
///
/// ## 关闭与重新打开**返回新的详情**，而不是让调用方自己改字段
///
/// `PATCH` 的响应是**完整的 PR 对象** ⇒ 直接用服务端那一份。
/// 本地改一个 `state` 字段的下场是"界面说已关闭、服务端说还开着"成为可能
/// （另一个客户端刚重新打开了它），而这种不一致只会在下一次刷新时暴露。
///
/// ⚠️ 合并**没有**这样的响应可用（`PUT /merge` 只回 `sha` / `merged` / `message`），
/// 所以它只能走本地更新 —— 见 `PullMergeResult.merged(at:sha:)` 对那个时间的说明。
public struct PullAction: Sendable {

    private let source: any PullActionDataSource

    public init(source: any PullActionDataSource) {
        self.source = source
    }

    /// 合并 PR（§5.3 的三种方式）。
    ///
    /// - Parameter now: 收到成功响应那一刻的时间。**必传** ——
    ///   它要进 `PullMergeResult.merged(at:)`，而让本类型内部取 `Date()`
    ///   等于给测试关上了一扇门（"合并后显示刚刚"这条断言就写不出来）。
    /// - Returns: 见 `PullMergeResult`。
    /// - Throws: 409（冲突）/ 403 / 404 / 网络错误照常抛 ——
    ///   ⚠️ 那三样与"不能合"是**不同的事**，§9.9 要求分开说。
    ///   409 单独有一句提示（`PullCopy.mergeConflictToast`），
    ///   因为冲突是**可以修的**：在网页端解掉再回来合即可。
    public func merge(
        fullName: String,
        number: Int,
        method: PullMergeMethod,
        now: Date
    ) async throws -> PullMergeResult {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let outcome = try await source.mergePull(
            owner: owner,
            repo: repo,
            number: number,
            method: method
        )
        switch outcome {
        case let .merged(result):
            // ⚠️ 走 `merged(at:)` 而不是把 `PullMergeResultDTO` 直接透出去：
            //    `.merged` 这个 case 的**存在本身**就是"200 也要看响应体"那条口径的证据
            //    （数据层已经把 `merged == false` 折成 `.notMergeable` 了）。
            return .merged(at: now, sha: result.sha)
        case .notMergeable:
            return .notMergeable
        }
    }

    /// 关闭 PR（§4.11 操作区）。
    public func close(fullName: String, number: Int) async throws -> PullDetail {
        try await update(fullName: fullName, number: number, state: "closed")
    }

    /// 重新打开 PR（§4.11 操作区）。
    public func reopen(fullName: String, number: Int) async throws -> PullDetail {
        try await update(fullName: fullName, number: number, state: "open")
    }

    // MARK: - 私有

    /// 两个操作唯一的差别就是那个 `state` 字符串 ⇒ 一条路径，不复制两遍。
    ///
    /// ⚠️ 那两个字符串**只出现在这里**（不在视图、不在调用方）：
    /// `updatePullState` **故意不校验**取值（数据层照发、把服务端的话带回来），
    /// 所以拼错一个 `"close"` 不会有任何编译期或运行期提示 ——
    /// 只会发一个服务端认不出的值。收成这两行是唯一的防线。
    private func update(fullName: String, number: Int, state: String) async throws -> PullDetail {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let dto = try await source.updatePullState(
            owner: owner,
            repo: repo,
            number: number,
            state: state
        )
        return Self.detail(from: dto)
    }

    /// 与 `LoadPullDetail` 里那份**逐字相同**的映射。
    ///
    /// ⚠️ 它是重复的（同一套字段映射出现两处），这是**有意**的取舍：
    /// 两处的来源不同（一个来自进页取数、一个来自写操作响应），
    /// 硬抽一个共用函数会把"进页"与"改完"这两条路径绑在一起，
    /// 而它们将来会因为不同的理由变化（前者可能加字段，后者不会）。
    /// 代价是改字段要改两处 —— 而 `PullActionTests` 断言了改完之后
    /// **状态真的跟着服务端走了**，那一处漏改会被它抓住。
    private static func detail(from dto: PullDetailDTO) -> PullDetail {
        PullDetail(
            number: dto.number,
            title: dto.title,
            state: PullRequestState(state: dto.state, mergedAt: dto.mergedAt),
            headRef: dto.head.ref,
            baseRef: dto.base.ref,
            authorLogin: dto.user?.login,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            mergedAt: dto.mergedAt,
            body: dto.body,
            additions: dto.additions,
            deletions: dto.deletions,
            changedFiles: dto.changedFiles
        )
    }
}
