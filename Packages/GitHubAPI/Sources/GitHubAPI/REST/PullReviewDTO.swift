import Foundation

/// 一条 **评审** —— `GET /repos/{owner}/{repo}/pulls/{n}/reviews`（决策 #60、TECH_SPEC §9.9）。
///
/// ## ⚠️ 它与「行内评论」是两个端点，别再混回去
///
/// §9.9 原文曾把"评审状态"记在 `/pulls/{n}/comments` 上 —— **那条写法是错的**
/// （2026-10-08 核实，性质同决策 #47 / #53：外部事实推翻文档写法）：
///
/// | 端点 | 是什么 | 带不带审批状态 |
/// |---|---|---|
/// | `GET …/pulls/{n}/comments` | **行内评论**（带 `path` / `line`，挂在 diff 的某一行上） | **不带** |
/// | `GET …/pulls/{n}/reviews` | **评审**（本类型） | **带**：`state` |
///
/// 原型评论上那枚「已批准」胶囊来自后者（`08-pr.js:43` 的 `<span class="pill merged">已批准</span>`）。
/// 两者按**作者 + 时间**合进同一条时间线 —— 会话评论（`IssueCommentDTO`）与评审在屏幕上
/// 本来就是一条流，这个合并在领域层做。
///
/// ## 为什么不取 `html_url` / `commit_id` / `_links`
///
/// 没有消费端。特别是 `commit_id`：它指的是"针对哪个提交审的"，
/// 而界面只显示"谁、什么时候、批没批、说了什么"。
public struct PullReviewDTO: Sendable, Equatable, Decodable {

    /// 评审 id。
    public let id: Int

    /// 评审人。**可以是 `null`**（账号已删除）。
    public let user: AuthorDTO?

    /// 原样保留字符串 —— 官方枚举 `PullRequestReviewState` 有五个取值：
    /// `APPROVED` / `CHANGES_REQUESTED` / `COMMENTED` / `DISMISSED` / `PENDING`。
    ///
    /// ⚠️ **不在这里枚举化**：界面只用到 `APPROVED` 这一个（那枚「已批准」胶囊），
    /// 其余五档的呈现口径 PRD 没给 ⇒ 枚举化等于替界面拍板。
    /// 领域层按需判定，兜底一律"不出胶囊"。
    public let state: String

    /// 评审意见正文。**可以是 `null`**（只点批准、不写话 —— 那是常态）。
    public let body: String?

    /// 提交评审的时刻。
    ///
    /// ⚠️ **可以是 `null`**：`PENDING` 状态的评审还没提交，官方 schema 里这一字段是 nullable。
    /// 领域层在它为 `nil` 时**不渲染时间那一截**（而不是编一个"刚刚"）。
    public let submittedAt: Date?

    public init(
        id: Int,
        user: AuthorDTO? = nil,
        state: String,
        body: String? = nil,
        submittedAt: Date? = nil
    ) {
        self.id = id
        self.user = user
        self.state = state
        self.body = body
        self.submittedAt = submittedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case user
        case state
        case body
        case submittedAt = "submitted_at"
    }
}
