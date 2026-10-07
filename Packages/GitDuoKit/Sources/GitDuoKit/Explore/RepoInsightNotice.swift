import Foundation

/// 探索仓库详情（§4.13）里**三个「数据拿到了但是空的」状态**的文案
/// （2026-10-06 用户拍板，PRD §4.13 / §7）。
///
/// ## 为什么这三句要放在领域层
///
/// 与 `ExploreBoardNotice` / `PullListIndicator` 同源的理由：它们是**可见契约**，
/// 而"什么时候该说这句话"是一条产品规则（分区保留、标题下的那一行），不是排版选择。
/// 放进 `GitDuoKit` 才能被单测钉住 —— App target 没有测试 target。
///
/// ## 为什么是"分区保留 + 一行空态"，而不是把分区整块抹掉
///
/// 分区在不在**本身也是一条信息**：
/// - 「语言构成」空着 ⇒ 这是个空仓库或只有配置文件；
/// - 「Latest Release」空着 ⇒ 这个仓库从没发过版本；
/// - 「贡献者」空着 ⇒ 还没有人参与。
///
/// 整块消失会让这三条判断都失去依据（用户分不清"没有"与"App 不显示这一块"）。
///
/// ⚠️ 三句都**不得**退化成"看起来有数据"的样子：语言构成不能画一根全灰的条
/// （那看起来像"100% 是某种语言"），贡献者不能画一排 `?` 占位头像。
public enum RepoInsightNotice {

    /// 语言构成：空仓库 / 只有配置文件（`GET …/languages` 回 `{}`）。
    public static let noLanguages = "暂无语言数据"

    /// Latest Release：从没发过版本（`GET …/releases/latest` 回 404 ⇒ 领域层是 `nil`）。
    public static let noRelease = "还没有发布过版本"

    /// 贡献者：一个也没有。
    public static let noContributors = "暂无贡献者"

    /// 贡献者分区的**空名单标题** —— 不带计数。
    ///
    /// ⚠️ 空名单时不写 `贡献者 · 0 位`：它与正文那句「暂无贡献者」说的是同一件事，
    /// 叠在一起只是啰嗦；而有数据时那个计数是 PRD §4.13 第 8 条点名的内容，必须带上。
    /// 所以判据是"名单空不空"，收在 `ContributorRoster.displayTitle` 一处。
    public static let contributorsSectionTitle = "贡献者"
}
