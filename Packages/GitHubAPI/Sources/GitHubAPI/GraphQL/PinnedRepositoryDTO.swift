import Foundation

/// 首页置顶卡片用的仓库对象（**GraphQL 形状**）—— TECH_SPEC §9.1、§4.6.5、§13.2。
///
/// ## 为什么它不能复用 `RepositoryDTO`
///
/// 置顶**只有 GraphQL 有**（REST 完全没有置顶端点，§4.6.5），于是同一个概念在两种接口下
/// 是两套命名。最容易写错的一处：**GraphQL 是 `stargazerCount`（单数）**，
/// 而 REST 是 `stargazers_count`（复数）—— 写错了不会编译报错，
/// 只会在运行时表现为"这个字段拿不到"，然后整条查询报一个指向别处的错误。
///
/// ## 有意**不取**的三个字段
///
/// - `primaryLanguage.color`：GraphQL 的 `Language` 类型确实给色值。**不用它**是因为
///   卡片上的语言点必须与探索榜、仓库列表**同色**，而那几处的数据源（REST search、
///   `/languages`）只给语言名、给不了色值 ⇒ 颜色只能来自本机那份映射表
///   （`GitDuoDesign` 的 `LanguageColor`）。两处混用会让同一种语言在两张卡上两个颜色。
/// - `pinnedItemsRemaining` / `viewerCanChangePinnedItems`：§4.6.5 提到用它们"判状态"，
///   但本切片没有任何一处呈现这两个状态 —— 空态由 `nodes` 为空决定，
///   「管理」入口恒为跳个人主页（官方无置顶写接口，§9.1）。多取一个字段就多一份要维持的契约。
///
/// ## 一个真实存在的形状陷阱
///
/// 置顶的仓库若被删除、或安装时没勾选它所在的仓库，GraphQL 会在 `nodes` 里回一个 **`null`**
/// （schema 里 `PinnedItemsConnection.nodes` 是 `[PinnableItem]`，**元素本身可空**）。
/// 若把 nodes 解成 `[PinnedRepositoryDTO]`，**一个失效置顶会让整个首页拿不到数据** ——
/// 所以端点把元素声明为可选并 `compactMap` 掉（见 `GitHubPinnedItemsEndpoint`）。
public struct PinnedRepositoryDTO: Sendable, Equatable, Decodable {

    /// `owner/name`。GitHub 保证它有且只有一个 `/`。
    public let nameWithOwner: String

    /// 仓库简介。**可以是 `null`**（未填简介的仓库很常见）。
    public let description: String?

    public let isPrivate: Bool

    public let starCount: Int

    public let forkCount: Int

    /// 主语言。**可以是 `null`**（空仓库、或只有配置文件）。
    public let primaryLanguage: PrimaryLanguage?

    /// 当前令牌对该仓库的权限 —— GraphQL 原生枚举
    /// `ADMIN` / `MAINTAIN` / `WRITE` / `TRIAGE` / `READ` / `NONE`（TECH_SPEC §9.1）。
    ///
    /// ## 为什么是 `String?` 而不是一个 Swift 枚举
    ///
    /// 与 `IssueDTO.state` 同一个理由：这是**仍在演进的取值集合**。枚举化之后，
    /// GitHub 哪天多一个权限档，表现就是**整个首页解码失败**（而不是"那一项降级"）。
    /// `String` 至少能让它平安走过解码，把解释权留给 `RepoSummaryMapper` ——
    /// 那里对认不出的取值给 `nil`（= 不知道），而不是猜一个。
    ///
    /// ## 它为什么必须在这里
    ///
    /// 首页置顶卡与最近访问行**要在进入详情页之前**定下是"自己的仓库"还是"他人仓库"
    /// （铁律 #7：只读态显式传参）。REST 侧的 `permissions.push` 在 GraphQL 里
    /// 没有对应对象，只有这个等价的枚举 —— 而它是**标量字段**，
    /// 加进来不会让这次查询的预扣点数从 1 变成 100（§13.2）。
    public let viewerPermission: String?

    /// GraphQL 的 `Language` 对象 —— 只取 `name`，理由见类型说明。
    public struct PrimaryLanguage: Sendable, Equatable, Decodable {
        public let name: String

        public init(name: String) {
            self.name = name
        }
    }

    public init(
        nameWithOwner: String,
        description: String? = nil,
        isPrivate: Bool,
        starCount: Int,
        forkCount: Int,
        viewerPermission: String? = nil,
        primaryLanguage: PrimaryLanguage? = nil
    ) {
        self.nameWithOwner = nameWithOwner
        self.description = description
        self.isPrivate = isPrivate
        self.starCount = starCount
        self.forkCount = forkCount
        self.viewerPermission = viewerPermission
        self.primaryLanguage = primaryLanguage
    }

    /// ⚠️ 这是全包**唯一**需要显式映射键名的 GraphQL DTO —— 因为只有它把
    /// GraphQL 的驼峰名改成了本包统一的 `starCount` / `forkCount`。
    /// 其余 GraphQL DTO 若字段名与 JSON 同名，一律不写 `CodingKeys`（少一处会写歪的地方）。
    private enum CodingKeys: String, CodingKey {
        case nameWithOwner
        case description
        case isPrivate
        // ⚠️ 单数 `stargazer`（GraphQL），**不是** REST 的复数 `stargazers_count`
        case starCount = "stargazerCount"
        case forkCount
        case viewerPermission
        case primaryLanguage
    }
}
