import Foundation
import GitHubAPI
import GitDuoCore

/// 一个仓库的 Star 视图状态（PRD §4.13「Star 按钮」、TECH_SPEC §4.6.2、决策 #41）。
///
/// ## `starCount` 是**展示用的数**，已经含本地 ±1
///
/// §4.6.2 的口径是"客户端本地 +1 / −1，无需重拉" —— 因为 `PUT` / `DELETE
/// /user/starred/{o}/{r}` 两个端点都只回 **204 No Content**，**响应里没有新计数**。
/// 所以本类型里的 `starCount` 是"屏幕上该显示的那个数"，而不是"服务端的数"。
public struct StarState: Sendable, Hashable {

    public let fullName: String

    /// 当前令牌（用户）是否已 Star 这个仓库。
    public let isStarred: Bool

    /// 展示用的星数（**已含本次会话内的本地 ±1**）。
    public let starCount: Int

    /// **基准是否已确认** —— 即"进页时那次 `GET /user/starred/{o}/{r}` 成功了没有"。
    ///
    /// ⚠️ 它是决策 #41 的全部要点：`±1` 必须先知道**操作前的状态**。
    /// 不加这一步的话，一个你已经 Star 过、共 100 星的仓库会按"未 Star"起手显示
    /// `Star · 100`；点一下发出的是**幂等的请求**（服务端什么都没变），
    /// 而界面把它当成"新增一颗" ⇒ 显示成 `Starred · 101` —— 既多算一颗，
    /// 也把"你已经 Star 过"这件事说反了。
    ///
    /// 基准没拿到（断网 / 权限异常）时这里是 `false`：界面**不谎称已 Star**，
    /// 用户下一次点击会先补一次基准查询（见 `ToggleStar.toggle(_:)`）。
    public let baselineConfirmed: Bool

    public init(
        fullName: String,
        isStarred: Bool,
        starCount: Int,
        baselineConfirmed: Bool
    ) {
        self.fullName = fullName
        self.isStarred = isStarred
        self.starCount = max(0, starCount)
        self.baselineConfirmed = baselineConfirmed
    }
}

/// 刚刚发生的那次 Star 操作（用来选 toast 文案）。
public enum StarAction: Sendable, Hashable {
    case starred
    case unstarred
}

/// Star 相关的**可见文案**（PRD §7、原型 `10-explore-repo.js` 的 `toggleXStar`）。
///
/// 放在领域层是因为两处都是契约：
/// - 那颗星的文案 `Star · {n}` ↔ `Starred · {n+1}` 出现在 PRD §4.13 第 1 条里；
/// - toast 两句是"操作真的发生了"的**唯一可见凭证**（harness 那侧断言过它的措辞）。
public enum StarCopy {

    /// 仓库头部那一颗 **Star** 的文案（Watch / Fork 不归本件 —— 它俩是裸信息，见走查第 66 条）。
    ///
    /// ## ⚠️ 名字是 `statTitle` 而不是 `buttonTitle`（2026-10-15，走查第 67 条）
    ///
    /// 它此前叫 `buttonTitle`，因为"那颗星恒是一个按钮"—— 走查第 **67** 条把这个前提改掉了：
    /// **写不了的仓库上不画按钮**，那颗星改用 `StatInfo`（裸信息）。理由与 Watch / Fork
    /// 那次（第 66 条）是同一条：**形状即信号**，一颗点不动的按钮等于承诺一件不会发生的事。
    /// ⇒ 同一个函数现在**两种形状都可能承载**，"按钮"这个词就不再成立了
    /// （同 `breadcrumbMenuAccessibilityLabel` → `operationsMenuAccessibilityLabel` 那次：
    /// 名字不该继续描述一个已经不成立的处境）。
    ///
    /// ⚠️ `{n}` 用**千分位全量**（`2,341`），**不缩写**（2026-10-06 用户拍板，TECH_SPEC §9.11）：
    /// 与仓库卡片上的 `2.3k` **有意不同** —— 卡片窄、要省宽度；头部这三个数是用户要读准的。
    /// 原型的数据也是这么分的（卡片侧 `124k`，头部侧 `11,240`，后者超过一万也不缩写）。
    ///
    /// ⚠️ 已 Star 那一档写的是 `Starred · {n}`（**2026-10-15 用户裁定**，原为 `已 Star · {n}`）：
    /// `Star` 与 `Starred` 是同一个词的原形与过去分词，两颗摆在一起是**同族**的两种形态；
    /// 原先那半句中文与另半句英文拼在一行，反而是两种写法混排。
    public static func statTitle(isStarred: Bool, starCount: Int) -> String {
        let count = GroupedNumber.string(from: starCount)
        return isStarred ? "Starred · \(count)" : "Star · \(count)"
    }

    /// 切换后的轻提示。
    ///
    /// ⚠️ 两句都在陈述**会发生什么**（"仓库计数 +1"），所以只有在计数确实动了的时候才能说 ——
    /// `ToggleStar` 保证"入参已确认基准"才走到这里。
    public static func toast(for action: StarAction) -> String {
        switch action {
        case .starred: "已 Star · 公开星标，仓库计数 +1"
        // 原型这里的减号是 U+2212（真正的减号），不是连字符 —— 与 `+1` 的字宽对称。
        case .unstarred: "已取消 Star · 仓库计数 −1"
        }
    }

    /// 按钮的读屏标签（图标是星形，读屏念不出"已 Star"这个状态）。
    ///
    /// ## ⚠️ `isControl` 决定要不要念「点按…」（2026-10-15，走查第 67 条）
    ///
    /// 写不了的仓库上它**不是控件**（`StatInfo`，见 `statTitle`），
    /// 而一句「点按取消」对一个不是按钮的东西是**错的承诺** —— 读屏用户会去双击它。
    /// ⇒ 只有能写那一档才带「点按…」。
    ///
    /// ⚠️ 屏幕上的字已改成 `Starred`（见 `statTitle`），这里**有意不改**：
    /// 这一句是给耳朵的 —— `Starred` 是个英文过去分词，中文读屏念出来是外语词，
    /// 而「已 Star」才是这句话该有的读音。**可见文案与可听文案本来就允许不同**。
    public static func accessibilityLabel(
        isStarred: Bool,
        starCount: Int,
        isControl: Bool = true
    ) -> String {
        let action = isControl ? (isStarred ? "，点按取消" : "，点按加星") : ""
        return isStarred
            ? "已 Star，\(starCount) 个 Star\(action)"
            : "Star，\(starCount) 个 Star\(action)"
    }

    // MARK: - 写不了这个仓库时（TECH_SPEC §3.5.5、决策 #80）

    /// **写不了这个仓库**时给用户的那一句。
    ///
    /// 出处：PRD §7（2026-10-09 新定）、TECH_SPEC §3.5.5、决策 #80。
    ///
    /// ## ⚠️ 同一句话承担三个角色，所以它必须是一句**成因说明**
    ///
    /// | 用在哪 | 形态 |
    /// |---|---|
    /// | §4.4 / §4.13 的头部大卡 | **置灰说明**（统计行下面一行） |
    /// | 同上那颗按钮 | **读屏标签**（此刻"点按加星"是不成立的，那句要换掉） |
    /// | 三处共用的失败提示 | 用户真的点下去（范围还没查到 / `selected` 那一档）时的那句 toast |
    ///
    /// ## ⚠️ 措辞为什么不是"该仓库所属账号未安装 GitDuo"
    ///
    /// 那句话会**断言过头**：安装确实可能装了、只是安装时勾的是
    /// `repository_selection == "selected"` 而**没勾这个仓库**（`StarWriteScope` 的说明里记着这一档）。
    /// "未被授权访问该仓库"两种情形都说得通，而且**不猜是哪一个**。
    ///
    /// ⚠️ 逐字不许改：它同时出现在两个详情页的头部，改一处就会两页不一致。
    public static let unavailableHint = "GitDuo 未被授权访问该仓库，暂不能 Star"

    /// 写 Star 失败时该说哪一句。
    ///
    /// ## ⚠️ 为什么不能一律用 `ActionCopy.failed`
    ///
    /// 那一句是 `操作失败 · 请重试`，而**这一种失败重试永远不会成功**
    /// （仓库不在安装范围里，范围不会自己变）—— 说"请重试"是把用户送向一条死路。
    /// 所以这里按**成因**分流：说得更准的成因就说那一句，其余回落通用句
    /// （同 `ActionCopy` 类型说明里那条"具体的失败成因各操作自己说得更准"）。
    ///
    /// ## ⚠️ 匹配的是**响应体里的那句话**，代价如实登记
    ///
    /// `Resource not accessible by integration` 是 GitHub 对"App 令牌越出安装范围 / 权限不足"
    /// 的标准措辞（2026-10-09 真机实测，两个写请求的体逐字都是它）。
    /// **它是唯一**能把"范围不足"与"二级限流 / 主桶耗尽 / 其余 403"分开的信号
    /// （后三者由 `GitHubError.from` 优先归一化掉，落到这里的 403 已经不是配额问题）。
    ///
    /// ⚠️ 代价：**GitHub 改措辞时会失配** ⇒ 退化成通用句。
    /// **最坏情况就是回到今天的样子**，不会更糟 —— 这是能接受失配的前提。
    /// ⚠️ 别把它改成"凡 403 就说这句"：那样"你没有权限"会被说成"GitDuo 没被授权"，
    /// 而在**别人的私有仓库**上这是两句意思相反的话。
    public static func failureMessage(for error: any Error) -> String {
        guard
            let githubError = error as? GitHubError,
            case let .forbidden(message) = githubError,
            message == integrationDeniedMessage
        else {
            return ActionCopy.failed
        }
        return unavailableHint
    }

    /// GitHub 对「App 令牌权限不足 / 越出安装范围」的标准措辞（2026-10-09 实测逐字）。
    private static let integrationDeniedMessage = "Resource not accessible by integration"
}

/// Star 的数据来源 —— 领域层与网络层之间的接缝。
public protocol StarDataSource: Sendable {

    /// `GET /user/starred/{owner}/{repo}`：**204 ⇒ 已 Star，404 ⇒ 没 Star**。
    func isStarred(owner: String, repo: String) async throws -> Bool

    /// `PUT /user/starred/{owner}/{repo}`（幂等）。
    func star(owner: String, repo: String) async throws

    /// `DELETE /user/starred/{owner}/{repo}`（幂等）。
    func unstar(owner: String, repo: String) async throws
}

/// 让真实端点满足上面的接缝（协议是我们自己声明的，不是追溯适配）。
extension GitHubStarEndpoint: StarDataSource {}

/// Star 的领域用例：**先确认基准，再幂等切换**（决策 #41）。
///
/// ## 为什么两个动作要在一起
///
/// "±1 该以什么为基准"只有一处答案，而它同时被"进页"（`initialState`）与"点击"
/// （`toggle`）用到。拆成两个类型，两处就会各自决定一次"基准是什么"。
public struct ToggleStar: Sendable {

    private let source: any StarDataSource

    public init(source: any StarDataSource) {
        self.source = source
    }

    /// 进页时确认基准（决策 #41：**只是进页确认一次**，不是每次操作都问）。
    ///
    /// ## 为什么失败**不抛错**
    ///
    /// 这次查询失败（断网 / 缺 `Starring` 权限 / 配额）不该让整个详情页打不开 ——
    /// 页面上的头部、语言构成、贡献者与它无关。所以失败被折叠成
    /// `baselineConfirmed == false`：界面**不谎称已 Star**（显示未激活的 `Star · {n}`），
    /// 而用户下一次点击会**先补一次基准查询**，仍然拿不到就以失败提示收场
    /// （见 `toggle(_:)`）。这是"失败不要静默吞掉"的正确落法：
    /// **不是**把错误藏起来，而是把它推迟到"真正需要它的那一步"。
    public func initialState(fullName: String, starCount: Int) async -> StarState {
        do {
            let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
            let isStarred = try await source.isStarred(owner: owner, repo: repo)
            return StarState(
                fullName: fullName,
                isStarred: isStarred,
                starCount: starCount,
                baselineConfirmed: true
            )
        } catch {
            return StarState(
                fullName: fullName,
                isStarred: false,
                starCount: starCount,
                baselineConfirmed: false
            )
        }
    }

    /// 切换一次。**先确保基准已确认，再发写请求。**
    ///
    /// - Parameter state: 当前状态（可能来自 `initialState` 的降级结果）。
    /// - Returns: 切换后的状态与刚发生的动作。
    /// - Throws: 基准查询或写请求的失败。**调用方据此把按钮恢复可点并给 toast**
    ///   （TECH_SPEC §8.5「操作类」一行）；失败时**不改变任何计数**。
    ///
    /// ## 为什么基准未确认时"先补一次查询"而不是"直接写"
    ///
    /// 直接写虽然也能把服务端改成目标状态，但那会让**计数**失去依据：
    /// 我们不知道它原本是不是已经在目标状态上（`PUT` 是幂等的），
    /// 于是 ±1 就成了猜。宁可多花一格主桶配额（5,000/小时，不紧张），
    /// 也不要往屏幕上放一个没有依据的数字。
    public func toggle(_ state: StarState) async throws -> (state: StarState, action: StarAction) {
        let (owner, repo) = try RepositoryMapper.splitFullName(state.fullName)

        var current = state
        if !current.baselineConfirmed {
            let isStarred = try await source.isStarred(owner: owner, repo: repo)
            current = StarState(
                fullName: state.fullName,
                isStarred: isStarred,
                starCount: state.starCount,
                baselineConfirmed: true
            )
        }

        if current.isStarred {
            try await source.unstar(owner: owner, repo: repo)
            return (
                StarState(
                    fullName: current.fullName,
                    isStarred: false,
                    // `−1` 的下限由 `StarState.init` 夹到 0：
                    // 服务端计数与本地显示的 0 星之间可能有一段"取数之后别人也没 Star"的窗口，
                    // 显示 `Star · -1` 是绝对不能发生的事。
                    starCount: current.starCount - 1,
                    baselineConfirmed: true
                ),
                .unstarred
            )
        }

        try await source.star(owner: owner, repo: repo)
        return (
            StarState(
                fullName: current.fullName,
                isStarred: true,
                starCount: current.starCount + 1,
                baselineConfirmed: true
            ),
            .starred
        )
    }
}
