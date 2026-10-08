import Foundation

/// Issue 详情 —— `GET /repos/{owner}/{repo}/issues/{n}`（TECH_SPEC §9.8、PRD §4.9）。
///
/// ## 与 `IssueDTO` 是两个类型，不是"加了一堆可选字段的那一个"
///
/// 列表项与详情**语义不同**：列表项回答"这一行画什么"，详情回答"这个 Issue 是什么"。
/// 合成一个类型的下场与切片 6 的 `CommitListItemDTO` / `CommitDetailDTO` 那条一样 ——
/// "列表里怎么没有 `body`"会变成每次都要回忆一遍的事。
///
/// ## 为什么**不收** `labels`
///
/// 标签是**卡片**上的东西（PRD §4.4 分区二、决策 #61）；§4.9 的详情头部
/// 只有"状态胶囊 + 说明 + 标题 + 元信息"，原型 `06-files.js:113` 的 `SCR.issueDetail`
/// 里也没有标签。少声明一个字段就少一处会因为它的形状变化而炸的地方。
///
/// ## 为什么**不收** `state_reason`
///
/// `open` / `closed` 之外，GitHub 还有 `state_reason`（`completed` / `not_planned` / `reopened`），
/// 但 §4.9 的状态说明只有两句（`该 Issue 仍然开放` / `已于 {时间}关闭`）⇒ 它没有消费端。
/// 与 `IssueDTO.state` 保留原始 `String` 的理由不同：那里是"取值集合还会变"，
/// 这里是"这一层根本用不上"。
public struct IssueDetailDTO: Sendable, Equatable, Decodable {

    /// Issue 编号（仓库内唯一）—— 头部那句 `#42` 与路由的键。
    public let number: Int

    public let title: String

    /// 原样保留（`open` / `closed`）。判定留给领域层的
    /// `PullRequestState.init(state:mergedAt:)`（Issue 没有 `mergedAt` ⇒ 只会取到 `.open` / `.closed`）。
    public let state: String

    /// 正文（Markdown 源文）。
    ///
    /// ⚠️ **可以是 `null`**（建 Issue 时可以只写标题），也**可以是空串**。
    /// 界面上的差别是"这一条要不要渲染成一条评论"—— 原型把正文画成**作者发的第一条评论**
    /// （`06-files.js` 的第一条 `.comment` 就是 `reviewer-a` 的正文）。
    /// 那份判断（空正文要不要出气泡）属于领域层，本层原样带出去。
    public let body: String?

    /// 创建者。**可以是 `null`**（账号已删除）。
    public let user: AuthorDTO?

    /// 创建时刻 —— 头部那句 `由 {创建者} 创建于 {时间}`。
    public let createdAt: Date

    /// 关闭时刻。**可以是 `null`**（仍然开放 —— 也可能"已关闭但没有这个字段"，
    /// 官方 schema 里它是 nullable 的）。领域层在它为 `nil` 时**只说"已关闭"、不编一个时间**。
    public let closedAt: Date?

    public init(
        number: Int,
        title: String,
        state: String,
        body: String? = nil,
        user: AuthorDTO? = nil,
        createdAt: Date,
        closedAt: Date? = nil
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.body = body
        self.user = user
        self.createdAt = createdAt
        self.closedAt = closedAt
    }

    private enum CodingKeys: String, CodingKey {
        case number
        case title
        case state
        case body
        case user
        case createdAt = "created_at"
        case closedAt = "closed_at"
    }
}
