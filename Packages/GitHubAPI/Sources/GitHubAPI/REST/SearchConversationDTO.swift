import Foundation

/// 会话（Issue / PR）搜索结果 —— `GET /search/issues` 的 `items` 元素
/// （TECH_SPEC §4.6.2、§9.2、PRD §4.2、决策 #47）。
///
/// ## ⚠️ 为什么**不复用** `IssueDTO`
///
/// 三处不同，每一处单列都足以另开一个类型：
///
/// | | `IssueDTO`（仓库内的 Issue 列表） | 本类型（跨仓库搜索） |
/// |---|---|---|
/// | 时间字段 | 只有 `created_at`（卡片写"由 {作者} 创建"） | 需要 `updated_at`（结果行写 `· 2 小时前`） |
/// | 仓库 | 不需要（调用方已知仓库） | 从 **`repository_url`** 解出来 —— 搜索跨仓库 |
/// | PR 标记 | **不声明任何字段**（列表要靠它过滤掉 PR） | **必须读 `merged_at`** —— 结果行要画"已合并" |
///
/// 第二处尤其不能凑：`repository_url` 是 `https://api.github.com/repos/{owner}/{repo}`，
/// 而"从 URL 里解出仓库全名"是一条**契约**（解错了那一行的 `id` 与去向全错），
/// 它有唯一的实现与单测（`SearchRowMapper.repositoryFullName`）。
///
/// ## `pull_request` 的**存在性**就是"这是 PR"的判据
///
/// 与 `IssueDTO` 同源：GitHub 的数据模型里 PR 就是一种 Issue，`pull_request` 字段
/// 是唯一可靠的判据（不要试图用标题、作者之类的启发式规则）。
/// 本类型与 `IssueDTO` 的差别只在**多声明了一个 `merged_at`**，而它是`已合并`
/// 唯一算得出来的原料（GitHub 没有独立的 `merged` 状态，§4.6.2）。
///
/// ⚠️ 官方 schema 里 `pull_request` **不在** required 列表里 ⇒ 它只在 PR 上出现，
/// 声明成可选是它的真实形状，不是防御。
public struct SearchConversationDTO: Sendable, Equatable, Decodable {

    /// 编号（仓库内唯一）—— 卡片上的 `#42`，也是跳详情页的键。
    public let number: Int

    public let title: String

    /// 原样保留（`open` / `closed`）。**不要**拿它判断"已合并"，见 `PullRequestMarker.mergedAt`。
    ///
    /// 用 `String` 而不是枚举：GitHub 在 `state` 之外还引入了 `state_reason`，
    /// 枚举化一个仍在演进的取值集合会让"某天多一个取值"表现为**整页解码失败**。
    public let state: String

    /// 最近更新时刻 —— 结果行副标题的 `· 2 小时前`。
    ///
    /// 官方 schema 把它列为**必需**，所以**不写可选分支**：真缺了就该整页报错
    /// （那是"响应的含义变了"），而不是留一条永远走不到的 `if let`。
    public let updatedAt: Date

    /// 所属仓库的 API 地址 `https://api.github.com/repos/{owner}/{repo}`。
    ///
    /// ⚠️ 官方 schema 把 `repository_url` 列为**必需**，而 `repository`（整个仓库对象）
    /// 是**可选**的 ⇒ 取必需的那个。解出 `owner/repo` 的规则见
    /// `SearchRowMapper.repositoryFullName(fromRepositoryURL:)`（唯一实现）。
    public let repositoryURL: URL

    /// PR 才有的标记。**它的存在性 = 这是一条 PR**。
    public let pullRequest: PullRequestMarker?

    /// 它是 PR 而不是 Issue —— 结果行的类型由**响应**决定，不由我们发出的查询决定。
    ///
    /// 我们确实按 `is:issue` / `is:pull-request` 分两次问（决策 #47），
    /// 但"这一行到底是什么"仍以服务端的回答为准：万一服务端把一条 PR 混进
    /// `is:issue` 的结果里，按请求去贴标签就会把它画成 Issue，而响应里有现成的答案。
    public var isPullRequest: Bool { pullRequest != nil }

    public init(
        number: Int,
        title: String,
        state: String,
        updatedAt: Date,
        repositoryURL: URL,
        pullRequest: PullRequestMarker? = nil
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.updatedAt = updatedAt
        self.repositoryURL = repositoryURL
        self.pullRequest = pullRequest
    }

    /// `pull_request` 字段。
    ///
    /// 只声明 `merged_at`：`diff_url` / `patch_url` / `url` 在本切片没有用处，
    /// 而少声明一个字段就少一处会因为它的形状变化而炸的地方
    /// （同 `IssueDTO.PullRequestMarker` 的判据）。
    public struct PullRequestMarker: Sendable, Equatable, Decodable {

        /// 合并时间。**可以是 `null`**（PR 还开着、或关闭但未合并）。
        ///
        /// ⚠️ 官方 schema 里它**不在**该对象的 required 列表里（required 的是另外四个 URL）。
        /// `state == "closed"` 且它有值 ⇒ 已合并；有 `state` 却拿不到它时只能判成"已关闭"
        /// —— 那正是"关闭但没合并"的样子，没有第三种可能。
        public let mergedAt: Date?

        public init(mergedAt: Date? = nil) {
            self.mergedAt = mergedAt
        }

        private enum CodingKeys: String, CodingKey {
            case mergedAt = "merged_at"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case number
        case title
        case state
        case updatedAt = "updated_at"
        case repositoryURL = "repository_url"
        case pullRequest = "pull_request"
    }
}
