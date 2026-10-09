import Foundation
import GitHubAPI

/// Issue 详情操作区的三档（PRD §4.9、TECH_SPEC §9.8、决策 **#79**）。
///
/// | 条件 | 操作区 |
/// |---|---|
/// | 我**不是**作者、且对这个仓库没有写权限 | 一行提示（**没有按钮**） |
/// | 可以管 + 仍然开放 | 「关闭 Issue」→ 确认弹层（§5.18） |
/// | 可以管 + 已关闭 | 「重新打开 Issue」（**不弹确认**） |
///
/// ## 为什么做成枚举而不是让视图写两个 `if`
///
/// 与 `PullOperationAvailability` 同一条理由：判据是"能不能管 + 状态"的**组合**，
/// 散在视图里会写成 `if canManage && isOpen { … } else if canManage { … }` ——
/// 它有一个**看不出来的**失败模式：漏掉某一档时那个分支什么都不画，
/// 而"操作区是空的"看起来像一个正常状态。收成枚举之后 `switch` 是穷尽的，漏一档编译不过。
///
/// ## ⚠️ 判据是**两个条件的析取**（决策 #79）
///
/// 依据是 GitHub 的规则（官方原文逐字）：*"Anyone can close an issue they opened.
/// Repository owners, collaborators on repositories owned by a personal account, and people
/// with triage permissions or greater on repositories owned by an organization can close
/// issues opened by others."*
///
/// ⇒ **我是作者** ∨ **我对这个仓库有写权限**。两条都不能少：
/// - 少了"**我是作者**"：「我的 Issue」页里那些**落在别人仓库**的 Issue 会变成只读
///   —— 而"从我的 Issue 进去改不了状态"正是用户报回来的那一条；
/// - 少了"**有写权限**"：自己的仓库里**别人提的** Issue 关不掉，而那是维护者的日常。
///
/// ⚠️ 两个输入里，`readOnly` 来自**入口**（铁律 #7：可写性在进入详情页之前就定下，
/// 不许在页面里靠"仓库全名像不像我的"去猜）；`isAuthor` 来自**详情自己**
/// （`IssueDetail.authorLogin` 与当前登录名比）。
public enum IssueOperationAvailability: Sendable, Hashable {

    /// 两个条件都不成立：不能管这条 Issue，操作区只有一行提示。
    case readOnly

    /// 可以管，且它仍然开放 ⇒ 「关闭 Issue」（→ 确认弹层 §5.18）。
    case close

    /// 可以管，且它已关闭 ⇒ 「重新打开 Issue」。
    ///
    /// ⚠️ **这一档不弹确认**（与 `close` 有意不对称）：关掉之后所有关注这个仓库的人
    /// 都会看到"已关闭"，而重开只是把状态还原、没有可损失的东西（PRD §4.9 操作区末条）。
    case reopen

    /// 判据（唯一一处）。
    ///
    /// ⚠️ **顺序**：`isAuthor` 先于 `readOnly` —— 作者身份**本身就是权限**。
    /// 反过来先判 `readOnly` 会让"他人仓库里我提的 Issue"落进 `.readOnly`，
    /// 而那正是决策 #79 要修的那一条（屏幕上看起来完全正常，只是少一颗按钮）。
    public static func decide(
        readOnly: Bool,
        isAuthor: Bool,
        isOpen: Bool
    ) -> IssueOperationAvailability {
        guard isAuthor || !readOnly else { return .readOnly }
        return isOpen ? .close : .reopen
    }
}

/// Issue 操作的接缝 —— 由 `GitHubAPI` 的 `GitHubRepoIssuesEndpoint` 空扩展体满足。
public protocol IssueActionDataSource: Sendable {

    /// `PATCH /repos/{o}/{r}/issues/{n}` —— `state` 只允许 `open` / `closed`。
    func updateIssueState(
        owner: String,
        repo: String,
        number: Int,
        state: String
    ) async throws -> IssueDetailDTO
}

/// 让真实端点满足上面的接缝。空扩展体能成立，靠的是**方法签名逐字一致**。
///
/// ⚠️ 签名漂了**不会报错**（协议实现是静态派发的，少一个方法才报错），
/// 所以接缝的条数在 `RepoEndpointsContractTests` 上数着 —— 新增一条要同步加一行。
extension GitHubRepoIssuesEndpoint: IssueActionDataSource {}

/// Issue 的两个操作：关闭 / 重新打开（PRD §4.9 操作区、TECH_SPEC §9.8、决策 #79）。
///
/// ## ⚠️ 两个操作都**返回新的详情**，不让调用方自己改字段
///
/// `PATCH` 的响应是**完整的 Issue 对象** ⇒ 直接用服务端那一份。
/// 本地改一个 `state` 字段的下场是"界面说已关闭、服务端说还开着"成为可能
/// （另一个客户端刚重新打开了它），而这种不一致只会在下一次刷新时才暴露。
/// 与 `PullAction` 的关闭 / 重开是**逐字同一条**处置。
public struct IssueAction: Sendable {

    private let source: any IssueActionDataSource

    public init(source: any IssueActionDataSource) {
        self.source = source
    }

    /// 关闭 Issue（§4.9 操作区）。
    public func close(fullName: String, number: Int) async throws -> IssueDetail {
        try await update(fullName: fullName, number: number, state: "closed")
    }

    /// 重新打开 Issue（§4.9 操作区）。
    public func reopen(fullName: String, number: Int) async throws -> IssueDetail {
        try await update(fullName: fullName, number: number, state: "open")
    }

    // MARK: - 私有

    /// 两个操作唯一的差别就是那个 `state` 字符串 ⇒ 一条路径，不复制两遍。
    ///
    /// ⚠️ 那两个字符串**只出现在这里**（不在视图、不在调用方）：
    /// `updateIssueState` **故意不校验**取值（数据层照发、把服务端的话带回来），
    /// 所以拼错一个 `"close"` 不会有任何编译期或运行期提示 ——
    /// 只会发一个服务端认不出的值。收成这两行是唯一的防线。
    private func update(fullName: String, number: Int, state: String) async throws -> IssueDetail {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let dto = try await source.updateIssueState(
            owner: owner,
            repo: repo,
            number: number,
            state: state
        )
        return Self.detail(from: dto)
    }

    /// 与 `LoadIssueDetail` 里那份**逐字相同**的映射。
    ///
    /// ⚠️ 它是重复的（同一套字段映射出现两处），这是**有意**的取舍 —— 与 `PullAction`
    /// 里那份一模一样：两处的来源不同（一个来自进页取数、一个来自写操作响应），
    /// 硬抽一个共用函数会把"进页"与"改完"这两条路径绑在一起，而它们将来会因为
    /// 不同的理由变化。代价是改字段要改两处 —— 而 `IssueActionTests` 断言了
    /// 改完之后**状态真的跟着服务端走了**，那一处漏改会被它抓住。
    private static func detail(from dto: IssueDetailDTO) -> IssueDetail {
        IssueDetail(
            number: dto.number,
            title: dto.title,
            // ⚠️ 读 `state` 而不是写死 `true`：PATCH 之后服务端回的就是新状态，
            //    写死的话"关闭成功但界面还写着开放"会当场发生。
            isOpen: dto.state == "open",
            body: dto.body,
            authorLogin: dto.user?.login,
            createdAt: dto.createdAt,
            closedAt: dto.closedAt
        )
    }
}
