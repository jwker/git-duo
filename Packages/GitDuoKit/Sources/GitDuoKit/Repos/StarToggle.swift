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
    /// 而界面把它当成"新增一颗" ⇒ 显示成 `已 Star · 101` —— 既多算一颗，
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
/// - 按钮文案 `Star · {n}` ↔ `已 Star · {n+1}` 出现在 PRD §4.13 第 1 条里；
/// - toast 两句是"操作真的发生了"的**唯一可见凭证**（harness 那侧断言过它的措辞）。
public enum StarCopy {

    /// 统计按钮上的文案。
    ///
    /// ⚠️ `{n}` 用**千分位全量**（`2,341`），**不缩写**（2026-10-06 用户拍板，TECH_SPEC §9.11）：
    /// 与仓库卡片上的 `2.3k` **有意不同** —— 卡片窄、要省宽度；头部这三个数是用户要读准的。
    /// 原型的数据也是这么分的（卡片侧 `124k`，头部侧 `11,240`，后者超过一万也不缩写）。
    public static func buttonTitle(isStarred: Bool, starCount: Int) -> String {
        let count = GroupedNumber.string(from: starCount)
        return isStarred ? "已 Star · \(count)" : "Star · \(count)"
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
    public static func accessibilityLabel(isStarred: Bool, starCount: Int) -> String {
        isStarred ? "已 Star，\(starCount) 个 Star，点按取消" : "Star，\(starCount) 个 Star，点按加星"
    }
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
