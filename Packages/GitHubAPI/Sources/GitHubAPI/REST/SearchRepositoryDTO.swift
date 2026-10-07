import Foundation

/// 探索榜卡片用的仓库对象 —— `GET /search/repositories` 的 `items` 元素（TECH_SPEC §9.10.1、§4.6.3）。
///
/// ## 为什么**不复用** `RepositoryDTO`
///
/// 两个理由，第二个是决定性的：
///
/// 1. **字段集不同**。榜单卡片要 `created_at`（新星榜的 `🆕 08-05 创建`）与
///    `pushed_at`（活跃榜的 `⚡ 30 分钟前推送`），而仓库列表卡片两样都不要。
/// 2. ⚠️ **`permissions` 的语义在这里会骗人**。搜索响应**不返回** `permissions`，
///    于是 `RepositoryDTO.permissions` 恒为 `nil`、`Repository.canWrite` 恒为 `false`。
///    对他人仓库恰好正确，但**搜索结果里也可能是你自己的仓库**（公开仓库人人搜得到）——
///    那一刻"不可写"就是个错值，而它长得和一个正常结果一模一样。
///    `RepositoryDTO` 的注释里写明了"缺失必须解释成不可写"，那条纪律成立的前提是
///    "缺失 = 真的问不到权限"；搜索这里缺失只是**接口不给**，两者不是一回事。
///
/// 所以本类型**根本不声明可写性相关字段**：它承载的是"别处看到一个仓库的摘要"，
/// 要判定可写性得去 `GET /repos/{owner}/{repo}`。少一个字段，就少一次判错的机会。
public struct SearchRepositoryDTO: Sendable, Equatable, Decodable {

    /// `owner/name`。GitHub 保证它有且只有一个 `/`。
    public let fullName: String

    /// 仓库简介。**可以是 `null`**。
    public let description: String?

    /// 主语言。**可以是 `null`**（空仓库、或只有配置文件）。
    public let language: String?

    public let starCount: Int

    /// 创建时间 —— 新星榜的 `🆕 MM-DD 创建`。
    ///
    /// **必需**（非可选）：仓库的创建时间恒存在，它缺了说明响应形状变了，
    /// 此时"整页报错"比"静默少一个日期"诚实。而下面的 `pushedAt` 就不一样了。
    public let createdAt: Date

    /// 最近推送时间 —— 活跃榜的 `⚡ N 分钟前推送`。
    ///
    /// **可以是 `null`**：刚创建、还没推过任何提交的仓库就是这样（§9.10.1 的 `pushed:` 限定符
    /// 会把绝大多数这类仓库挡在外面，但它不是空集）。视图遇到 `nil` 时应当不渲染这条指标，
    /// 而不是拿 `createdAt` 顶上 —— 那会把"创建于"显示成"推送于"。
    public let pushedAt: Date?

    public init(
        fullName: String,
        description: String? = nil,
        language: String? = nil,
        starCount: Int,
        createdAt: Date,
        pushedAt: Date? = nil
    ) {
        self.fullName = fullName
        self.description = description
        self.language = language
        self.starCount = starCount
        self.createdAt = createdAt
        self.pushedAt = pushedAt
    }

    private enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case description
        case language
        case starCount = "stargazers_count"
        case createdAt = "created_at"
        case pushedAt = "pushed_at"
    }
}

/// `GET /search/repositories` 的完整结果（§4.6.3、决策 #37）。
///
/// 搜索的响应是**一个对象**（`{ total_count, incomplete_results, items }`）而不是裸数组，
/// 所以它装不进 `Page<T>` —— 这里手工拼出"列表 + 下一页"的形状，
/// 下一页仍走 `Page.nextCursor(from:)`（`Link` 头的解析只有一处，别在这里另写一遍）。
public struct SearchRepositoriesResult: Sendable {

    public let items: [SearchRepositoryDTO]

    /// 下一页的**完整 URL**；`nil` 表示已到底（§4.4）。
    public let nextCursor: URL?

    /// ⚠️ GitHub 在**计算超时**时会返回一个不完整的结果集，并用这个标记说出来
    /// （`incomplete_results: true`）。它不影响解码，所以很容易被忽略 ——
    /// 但它是"这一页少了一些本该在里面的仓库"的唯一信号。
    ///
    /// 本切片只把它带出来，**尚未**在界面上呈现（那是 4.4 的决定）；
    /// 丢掉它就等于把这个信号永久删掉，之后想提示也没得提示了。
    public let incompleteResults: Bool

    public var hasMore: Bool { nextCursor != nil }

    public var isEmpty: Bool { items.isEmpty }

    public init(
        items: [SearchRepositoryDTO],
        nextCursor: URL?,
        incompleteResults: Bool
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.incompleteResults = incompleteResults
    }
}
