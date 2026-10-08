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
/// PRD §4.14 的 Issue 卡片是：状态图标 + 标题 + `#N · {时间} · 由 {作者} 创建`；
/// 仓库详情（§4.4 分区二，决策 #61）**多一枚标签胶囊** ⇒ 切片 7 补了 `labels`。
/// 仍然**没有** `body` / `assignees` / `milestone` / `closed_at` ——
/// 那几样是 Issue **详情**页的事，而详情走的是另一个端点（`GET …/issues/{n}`，
/// 见 `IssueDetailDTO`）；卡片不需要它们。
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
    ///
    /// ⚠️ 类型是顶层的 `AuthorDTO`（切片 7 从本类型里提出去的）：Issue 详情、评论、PR、评审
    /// 四处都用同一个形状，嵌在各自的 DTO 里迟早长岔。
    public let user: AuthorDTO?

    /// 标签（**切片 7 新增**）。
    ///
    /// ## 为什么是**可选**的
    ///
    /// 合成的 `init(from:)` 对**非可选**字段缺一个 key 就整页解码失败 ——
    /// 而"少一组标签"远不该值这个代价（与 `state` 那条不同：那一次是为"取值集合还会变"
    /// 留余地，这一次是为"形状可能不带"留的）。领域层按空数组处理。
    ///
    /// ## 为什么数据层也带上它（探索页并不画它）
    ///
    /// PRD §4.4 分区二的 Issue 卡片写了「标签胶囊」，而探索页的卡片没有
    /// （原型 `10-explore-repo.js` 的卡片只有两行）。同一份 DTO 两处共用 ⇒
    /// 差异表达在**消费端**（卡片画不画），而不是在数据形状上 ——
    /// 这也正是"同形必分叉"的正面用法：让一处定义承担两种用法，
    /// 而不是复制一份 DTO。
    public let labels: [LabelDTO]?

    /// `pull_request` 字段的**存在性**就是判据。
    ///
    /// 只需要知道"在不在"，所以 `PullRequestMarker` **不声明任何字段**：
    /// 它的内容（`url` / `html_url` / `merged_at`）在本切片没有用处，
    /// 而少声明一个字段就少一处会因为它的形状变化而炸的地方。
    public let pullRequest: PullRequestMarker?

    /// 它是 PR 而不是 Issue —— 列表必须按这个过滤（见类型说明）。
    public var isPullRequest: Bool { pullRequest != nil }

    public struct PullRequestMarker: Sendable, Equatable, Decodable {
        public init() {}
    }

    public init(
        number: Int,
        title: String,
        state: String,
        comments: Int,
        createdAt: Date,
        user: AuthorDTO? = nil,
        labels: [LabelDTO]? = nil,
        pullRequest: PullRequestMarker? = nil
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.comments = comments
        self.createdAt = createdAt
        self.user = user
        self.labels = labels
        self.pullRequest = pullRequest
    }

    private enum CodingKeys: String, CodingKey {
        case number
        case title
        case state
        case comments
        case createdAt = "created_at"
        case user
        case labels
        case pullRequest = "pull_request"
    }
}
