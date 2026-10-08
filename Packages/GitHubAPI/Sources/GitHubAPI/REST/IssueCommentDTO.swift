import Foundation

/// 一条会话评论 —— `GET /repos/{owner}/{repo}/issues/{n}/comments`
/// （TECH_SPEC §9.8 / §9.9、PRD §4.9 / §4.11）。
///
/// ## ⚠️ PR 的时间线**也用这个端点**
///
/// GitHub 的数据模型里 PR 是一种 Issue，所以 PR 的会话评论**不在** `/pulls/{n}/` 下面 ——
/// 取评论用 `GET …/issues/{n}/comments`，发评论用 `POST …/issues/{n}/comments`
/// （§4.6.2 与 §9.9 都写明了）。本类型因此**同时**服务 Issue 详情与 PR 详情的"对话"分区。
///
/// ## ⚠️ 它**不含**任何审批状态
///
/// 原型评论上那枚「已批准」胶囊来自**另一个端点** —— `GET …/pulls/{n}/reviews`
/// （决策 #60，被外部事实推翻文档写法的那一条）：`/pulls/{n}/comments` 是**行内评论**
/// （带 `path` / `line`，那是 diff 上的批注），`reviews` 才有
/// `APPROVED` / `CHANGES_REQUESTED` / … 的 `state`。
/// ⇒ 两者在领域层按"作者 + 时间"合进**同一条时间线**，本类型只负责其中一半。
///
/// ## 为什么不收 `html_url` / `node_id` / `reactions`
///
/// 没有任何界面要用它们；`Reactions` 是本项目本期不做的一块（§16）。
public struct IssueCommentDTO: Sendable, Equatable, Decodable {

    /// 评论 id（仓库内不唯一，但全局唯一）—— 列表去重与 `ForEach` 的键。
    public let id: Int

    /// 正文（Markdown 源文）。
    ///
    /// ⚠️ 声明成**必需**：评论没有正文就没有存在的意义（与 `IssueDetailDTO.body` 不同，
    /// 那个可以为空是因为 Issue 允许只写标题）。官方 schema 里它也是 required。
    public let body: String

    /// 作者。**可以是 `null`**（账号已删除）—— 声明成必需会让整段讨论打不开。
    public let user: AuthorDTO?

    /// 发表时刻。
    public let createdAt: Date

    public init(
        id: Int,
        body: String,
        user: AuthorDTO? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.body = body
        self.user = user
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case body
        case user
        case createdAt = "created_at"
    }
}
