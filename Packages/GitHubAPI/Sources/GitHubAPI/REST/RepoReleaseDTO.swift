import Foundation

/// 最新版本 —— `GET /repos/{owner}/{repo}/releases/latest`（TECH_SPEC §9.11、§4.6.3）。
///
/// ## ⚠️ 这个端点用 **404 表示"没有发布过版本"**
///
/// 官方文档写得很清楚：很多仓库有 tag 但**没有** published release，
/// 此时端点回 **404** —— 与"仓库不存在"是同一个状态码。
/// 所以调用方（`GitHubRepoInsightsEndpoint.latestRelease`）**必须把 404 解释成 `nil`**，
/// 而不是往上抛一个"仓库不存在"。这一步不做的后果很具体：
/// 一个只是没发过版本的仓库，整个详情页会显示成"加载失败"。
///
/// 这也是 `GitHubError` 的注释里那条纪律的**唯一例外**——"404 不得替用户断定是哪一种"
/// 在这里**可以**确定：因为同一屏的 `GET /repos/{owner}/{repo}` 已经成功过，
/// 仓库存在且可见这件事已经被证实了。
///
/// ## 不声明 `isDraft` / `isPrerelease`
///
/// 本端点返回的就是"最新的**正式**版本"（GitHub 自动排除草稿与预发布），
/// 那两个字段在这里恒为 `false` —— 解了也没人用，还要各自维持一份契约。
public struct RepoReleaseDTO: Sendable, Equatable, Decodable {

    /// 版本标签（如 `v2.1.0`）—— PRD §4.13 的「版本胶囊」显示它。
    public let tagName: String

    /// 版本标题。**可以是 `null`**（只打了 tag 没写标题的 release 很常见），
    /// 所以界面上以 `tagName` 为准、`name` 只在有值时作为补充。
    public let name: String?

    /// 版本说明（Markdown 正文）。
    ///
    /// **可以是 `null`**：发版本时正文留空是常态。它**不是** Markdown 渲染的输入之一
    /// —— 本切片按纯文本展示（自研渲染器是另一个模块，§11.1）。
    public let body: String?

    /// 发布时间。**可以是 `null`**（`published_at` 在 release 对象里本就是可空字段）。
    /// 界面遇到 `nil` 就不渲染时间，而不是拿当前时间顶上。
    public let publishedAt: Date?

    /// 附件资产 —— **只用来计数**。
    public let assets: [Asset]

    /// 资产条数（PRD §4.13 的「资产 (3)」按钮文案）。
    public var assetCount: Int { assets.count }

    /// 资产条目。
    ///
    /// ## 为什么是一个"没有字段"的结构体
    ///
    /// 本切片对资产的唯一需求是 **个数**；「下载源码」「资产」两个按钮在 PRD §4.13
    /// 里都标着 ⏳（行为待细化）。资产对象很大（`name` / `size` / `download_count` /
    /// `browser_download_url` / `content_type`…），现在把字段猜进来，
    /// 等于替"实现下载"那一刻的自己拍板 —— 而字段一旦写进 DTO，后面的人会以为它已经定过了。
    ///
    /// 空结构体的 `Decodable` 实现（编译器合成）不读任何键，于是 `[{…},{…}]` 解出 2 个元素、
    /// 且**任何一个资产的形状变化都不会让版本卡片整块失败**。等实现下载时再补字段。
    public struct Asset: Sendable, Equatable, Decodable {
        public init() {}
    }

    public init(
        tagName: String,
        name: String? = nil,
        body: String? = nil,
        publishedAt: Date? = nil,
        assets: [Asset] = []
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.publishedAt = publishedAt
        self.assets = assets
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case publishedAt = "published_at"
        case assets
    }
}
