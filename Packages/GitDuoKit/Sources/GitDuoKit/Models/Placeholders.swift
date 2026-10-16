import Foundation

/// 占位数据 —— 官方骨架方案 `.redacted(reason: .placeholder)` 的配套（NATIVE-MIGRATION P1）。
///
/// ## 为什么要有这一份
///
/// SwiftUI 的官方占位方案**不是**"画一堆灰条"，而是**拿真实布局渲染一遍、再把内容遮成灰块**：
///
/// ```swift
/// RepoCard(repository: .placeholder).redacted(reason: .placeholder)
/// ```
///
/// 它的好处正是自绘骨架屏做不到的那一条：**尺寸永远与真实布局一致**（§8.5 第 1 条
/// 那条"改了真实卡片忘了改骨架 ⇒ 数据到达时整屏跳一下"的问题从此消失，因为根本
/// 没有第二份布局可写）。代价是需要一份假数据来喂真实布局 —— 就是本文件。
///
/// ## 三条纪律
///
/// 1. **只允许出现在 `.redacted` 之下** —— 这些字符串是"凑出合适宽度的填料"，
///    不是文案，任何一处让它露出来都是 bug（红act 之后读屏也读不到它：
///    SwiftUI 会把 redacted 视图当作占位，读屏念的是"正在加载"那类系统话术）。
/// 2. **填料长度挑的是"一行放得下、看起来像一行字"**，不是随便写 ——
///    块宽就是文字宽，写太短会看到一排小方块，写太长会顶到边界。
/// 3. ⚠️ **不要给它加本地化 / 不要进文案层**（`*Copy` 那一族）—— 它永远不该被看见，
///    一旦进了可译资源，就等于承认它会出现在屏幕上。
public enum Placeholders {

    /// 一条"看起来像一句话"的填料。
    ///
    /// ⚠️ 不用真实词（"正在加载…"那种）—— 有人的第一反应是"这句是不是该翻译"，
    /// 而它根本不该被读。用重复字是为了让宽度稳定、且一眼看出它是填料。
    public static let line = "占位占位占位占位占位"

    /// 一条短一些的（副标题 / 第二行）。
    public static let shortLine = "占位占位占位"

    /// 一个固定时刻。**不要在这里取 `Date()`** —— 占位数据是值，每次渲染都变会让
    /// 相对时间（`#42 · 3 天前`）在 redacted 下也跟着变，且无从稳定。
    public static let date = Date(timeIntervalSince1970: 0)
}

extension Repository {

    /// 仓库列表（`RepoCard`）与「我的 Star」（`StarRow`）的占位。
    public static let placeholder = Repository(
        owner: "placeholder",
        name: "placeholder",
        description: Placeholders.line,
        isPrivate: false,
        language: "Placeholder",
        starCount: 0,
        forkCount: 0
    )
}

extension RepoSummary {

    /// 首页置顶（`PinRow`）与探索榜（`TrendCard`）的占位。
    public static let placeholder = RepoSummary(
        fullName: "placeholder/placeholder",
        description: Placeholders.line,
        language: "Placeholder",
        starCount: 0
    )
}

extension RepositoryHit {

    /// 搜索结果行的占位（四种结果行里最宽的那种 —— 骨架只铺一种，见 `SearchResultsSkeleton`）。
    public static let placeholder = RepositoryHit(
        fullName: "placeholder/placeholder",
        description: Placeholders.shortLine,
        language: "Placeholder",
        starCount: 0
    )
}

extension IssueRow {

    /// Issue / PR 列表卡片（`IssueCard` / `PullCard`）的占位。
    public static let placeholder = IssueRow(
        number: 0,
        title: Placeholders.line,
        isOpen: true,
        comments: 0,
        createdAt: Placeholders.date,
        authorLogin: "placeholder"
    )
}

extension TreeEntry {

    /// 文件树一行的占位（`RepoFileRow`）。
    ///
    /// ⚠️ `path` 用 `RepoPath(path:)`（那条**不校验**的通道）：占位不来自用户输入，
    /// 也没必要为了它去走一遍 `appending(_:)` 的合法性检查。
    public static let placeholder = TreeEntry(
        name: Placeholders.shortLine,
        path: RepoPath(path: "placeholder"),
        kind: .directory,
        size: 0,
        sha: ""
    )
}

extension StarState {

    /// 「我的 Star」那一行的状态占位。
    ///
    /// `baselineConfirmed: false` —— 占位不该声称"已确认已 Star"，
    /// 而 redacted 之下这个区别本来就看不见；取 `false` 是保守那一侧。
    public static func placeholder(fullName: String = "placeholder/placeholder") -> StarState {
        StarState(fullName: fullName, isStarred: false, starCount: 0, baselineConfirmed: false)
    }
}
