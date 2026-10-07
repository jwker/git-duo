import Foundation

/// Issue 卡片 —— `GET /repos/{owner}/{repo}/issues` 的元素（TECH_SPEC §4.6.2、§4.14）。
///
/// ## ⚠️ 这个端点**会混入 PR**
///
/// GitHub 的数据模型里 PR 就是一种 Issue，所以 `GET /issues` 的返回里**夹着 PR 条目**。
/// 带 `pull_request` 字段的就是 PR —— 那是唯一可靠的判据
/// （不要试图用"标题里有 `fix:`""作者是某某"之类的启发式规则）。
///
/// 本类型**原样保留**这个字段（`isPullRequest`）而不在数据层过滤：
/// "哪些算 Issue"是产品口径，属于调用方；数据层擅自丢掉条目会让
/// "这一页 30 条里怎么只有 9 条"变成一个查不出来的谜。
///
/// ## 只声明卡片真正用到的字段
///
/// PRD §4.14 的 Issue 卡片是：状态图标 + 标题 + `#N · {时间} · 由 {作者} 创建`。
/// 所以**没有** `labels` / `body` / `assignees` / `milestone` / `closed_at` ——
/// 那些是 Issue 详情页（切片 7）的事，现在猜进来等于替那时的自己拍板。
public struct IssueDTO: Sendable, Equatable, Decodable {

    /// Issue 编号（仓库内唯一）—— 卡片上的 `#42`，也是跳详情页的键。
    public let number: Int

    public let title: String

    /// 状态原样保留（`open` / `closed`）。
    ///
    /// 用 `String` 而不是枚举：GitHub 在 `state` 之外还引入了 `state_reason`
    /// （`completed` / `not_planned` / `reopened`），枚举化一个仍在演进的取值集合，
    /// 会让"某天多一个取值"表现为**整页解码失败**。解释留给领域层。
    public let state: String

    /// 评论条数（原型卡片里的 `3 条评论`）。
    public let comments: Int

    /// 创建时间 —— 卡片上 `由 {作者} 创建` 那句话对应的时间。
    ///
    /// **用 `created_at` 而不是 `updated_at`**：卡片文案说的是"创建"，
    /// 而两者在活跃的 Issue 上可以差很多天；显示 `updated_at` 却写"创建"是**文案与数据打架**。
    public let createdAt: Date

    /// 作者。**可以是 `null`** —— 账号被删除后，GitHub 把整段 `user` 置为 `null`。
    /// 声明成必需会让"一个已删除用户的 Issue"把整页打崩。
    public let user: Author?

    /// `pull_request` 字段的**存在性**就是判据。
    ///
    /// 只需要知道"在不在"，所以 `PullRequestMarker` **不声明任何字段**：
    /// 它的内容（`url` / `html_url` / `merged_at`）在本切片没有用处，
    /// 而少声明一个字段就少一处会因为它的形状变化而炸的地方。
    public let pullRequest: PullRequestMarker?

    /// 它是 PR 而不是 Issue —— 列表必须按这个过滤（见类型说明）。
    public var isPullRequest: Bool { pullRequest != nil }

    public struct Author: Sendable, Equatable, Decodable {
        public let login: String

        public init(login: String) {
            self.login = login
        }
    }

    public struct PullRequestMarker: Sendable, Equatable, Decodable {
        public init() {}
    }

    public init(
        number: Int,
        title: String,
        state: String,
        comments: Int,
        createdAt: Date,
        user: Author? = nil,
        pullRequest: PullRequestMarker? = nil
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.comments = comments
        self.createdAt = createdAt
        self.user = user
        self.pullRequest = pullRequest
    }

    private enum CodingKeys: String, CodingKey {
        case number
        case title
        case state
        case comments
        case createdAt = "created_at"
        case user
        case pullRequest = "pull_request"
    }
}
