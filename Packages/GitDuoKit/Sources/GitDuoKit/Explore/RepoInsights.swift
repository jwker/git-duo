import Foundation
import GitHubAPI
import GitDuoCore

/// 最新版本（`GET /repos/{o}/{r}/releases/latest` 的领域形态，PRD §4.13 第 4 条）。
///
/// ## 为什么"没有最新版本"是 `nil` 而不是错误
///
/// 很多仓库有 tag 但**没有** published release，端点此时回 **404** ——
/// 与"仓库不存在"同一个状态码。判定它只能是"没有版本"的理由是可以确定的：
/// 同屏的 `GET /repos/{o}/{r}` 已经成功过，仓库存在且可见已被证实
/// （TECH_SPEC §9.11，这是"404 不得替用户断定"那条纪律的**唯一例外**）。
public struct LatestRelease: Sendable, Hashable {

    /// 版本标签（如 `v2.1.0`）—— 版本胶囊里显示它。
    public let tagName: String

    /// 版本标题。**可以是 `nil`**（只打了 tag 没写标题的 release 很常见）——
    /// 所以界面上**以 `tagName` 为准**，`name` 只在有值时作为补充。
    public let name: String?

    /// 版本说明。**可以是 `nil`**（发版本时正文留空是常态）。
    /// 本切片按**纯文本**展示（自研 Markdown 渲染器是另一个模块，§11.1）。
    public let notes: String?

    /// 发布时间。**可以是 `nil`** —— 界面遇到 `nil` **不渲染时间**，
    /// 而不是拿当前时间顶上（那会把"发布时间未知"显示成"刚刚发布"）。
    public let publishedAt: Date?

    /// 附件资产条数（PRD §4.13 的「资产 (3)」按钮文案）。
    ///
    /// 只保留**个数**：本切片对资产的唯一需求就是它，字段猜进来等于替"实现下载"
    /// 那一刻的自己拍板（见 `RepoReleaseDTO.Asset`）。
    public let assetCount: Int

    /// 「下载源码」按钮文案（PRD §4.13 第 4 条原文）。
    public static let sourceCodeButtonTitle = "下载源码"

    public init(
        tagName: String,
        name: String? = nil,
        notes: String? = nil,
        publishedAt: Date? = nil,
        assetCount: Int = 0
    ) {
        self.tagName = tagName
        self.name = name
        self.notes = notes
        self.publishedAt = publishedAt
        self.assetCount = assetCount
    }

    /// 发布时间文案；`publishedAt` 为空时返回 `nil`（视图据此**不渲染**这一段）。
    public func publishedLabel(now: Date) -> String? {
        publishedAt.map { RelativeTime.string(from: $0, now: now) }
    }

    /// `资产 (3)` —— 与原型 `资产 (${…})` 逐字一致。
    public var assetsButtonTitle: String { "资产 (\(assetCount))" }

    /// 版本说明为空（或只有空白）时**不渲染正文**，而不是渲染一个空盒子。
    public var hasNotes: Bool {
        !(notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 一位贡献者（`GET /repos/{o}/{r}/contributors` 的元素）。
///
/// ## 两个字段都可空，而且这是**必须**的
///
/// GitHub 的贡献者按提交邮箱归并，只有前 500 个邮箱能关联到账号，其余会以
/// **匿名贡献者**出现（没有 `login`、没有 `avatar_url`）。把它们声明成必需，
/// **一个匿名贡献者就会让整块贡献者区域消失**（解码失败），而它其实只差一个名字。
public struct Contributor: Sendable, Hashable {

    /// 登录名。**可以是 `nil`**（匿名贡献者）。
    public let login: String?

    /// 头像地址。**可以是 `nil`**（匿名贡献者，或账号没设头像）。
    public let avatarURL: URL?

    public init(login: String? = nil, avatarURL: URL? = nil) {
        self.login = login
        self.avatarURL = avatarURL
    }
}

/// 贡献者概览（PRD §4.13 第 8 条、决策 #40）。
///
/// ## 总数的口径
///
/// `GET /contributors` **不返回总数**（官方没有 count 字段）。本项目的做法是
/// **一页取回 100 条**（端点上限）：
/// - **没有下一页 ⇒ 条目数就是精确总数**（绝大多数仓库走这条）；
/// - **有下一页 ⇒ 只能说"100 位以上"**（一个下界，不是猜测）。
///
/// 备选方案是额外打一次 `?per_page=1` 读 `Link` 的 `rel=last` 页号拿精确值，
/// 代价是多花一格主桶配额 —— 2026-10-06 用户拍板取前者。
///
/// ## 与原型的一处有意不同
///
/// 原型写的是 `以及另外 ${t.contrib-8} 位贡献者`，而 `t.contrib` 是演示数据里手写的数。
/// 真实数据里 `contrib` 可能小于 8（新仓库），那一减就成了**负数** ——
/// "以及另外 −3 位贡献者"。所以这里在"全都画出来了"时返回 `nil`（**不渲染那一行**）。
public struct ContributorRoster: Sendable, Hashable {

    /// 已取回的贡献者（**服务端已按贡献次数降序** —— 顺序即语义，不要重排）。
    public let contributors: [Contributor]

    /// 服务端是否还有下一页 ⇒ 上面的条目数只是**下界**。
    public let hasMore: Bool

    public var loadedCount: Int { contributors.count }

    /// 精确总数；`nil` = 还有下一页，只能说"以上"。
    public var exactCount: Int? { hasMore ? nil : contributors.count }

    public init(contributors: [Contributor] = [], hasMore: Bool = false) {
        self.contributors = contributors
        self.hasMore = hasMore
    }

    /// 分区标题 —— `贡献者 · 23 位` / `贡献者 · 100 位以上`
    /// （原型 `<div class="section-label">贡献者 · ${t.contrib} 位</div>`）。
    public var sectionTitle: String {
        guard let exactCount else { return "贡献者 · \(loadedCount) 位以上" }
        return "贡献者 · \(exactCount) 位"
    }

    /// **界面上真正该显示的那个标题**：名单为空时退成不带计数的 `贡献者`。
    ///
    /// "贡献者 · 0 位"与正文那句「暂无贡献者」（`RepoInsightNotice.noContributors`）
    /// 说的是同一件事，叠在一起只是啰嗦。判据收在这里，视图直接读它 ——
    /// 否则"空名单要不要带计数"就成了每个调用点各自的一念之差。
    public var displayTitle: String {
        contributors.isEmpty ? RepoInsightNotice.contributorsSectionTitle : sectionTitle
    }

    /// 头像排下方那行 `以及另外 {N} 位贡献者`。
    ///
    /// - Parameter visibleLimit: 头像排**实际画得出**几个 —— 由视图传进来（它才知道
    ///   一行放得下几个 / `AvatarStack` 的档位）。领域层不猜这个数：猜了就会与头像排
    ///   画出来的个数对不上，而"说了另外 15 位、数一数却有 17 个头像"是用户一眼能看出的错。
    /// - Returns: `nil` = 全都画出来了，**不渲染这一行**（不要输出"以及另外 0 位"）。
    public func remainingLabel(visibleLimit: Int) -> String? {
        let limit = max(0, visibleLimit)
        guard let exactCount else {
            // 还有下一页：已取回的这 100 条里能说准"画不下的那部分至少有多少"。
            let remaining = loadedCount - limit
            guard remaining > 0 else { return nil }
            return "以及另外 \(remaining) 位以上贡献者"
        }
        let remaining = exactCount - limit
        guard remaining > 0 else { return nil }
        return "以及另外 \(remaining) 位贡献者"
    }
}

/// 他人仓库详情页的四路数据（TECH_SPEC §9.11、PRD §4.13 的 ①③④⑧ 四个分区）。
///
/// 语言构成是**已经算好的分段**（`LanguageComposition`，决策 #42）：
/// 领域层收口"切几段、百分比怎么取整"，视图只负责画。
public struct RepoInsights: Sendable, Hashable {

    public let detail: RepositoryDetail

    /// 语言构成分段（**空数组 = 空仓库 / 只有配置文件** ⇒ 视图渲染空态，不是一根全灰的条）。
    public let languages: [LanguageShare]

    /// 最新版本；`nil` = 这个仓库没有发布过版本（不是错误）。
    public let release: LatestRelease?

    public let contributors: ContributorRoster

    public init(
        detail: RepositoryDetail,
        languages: [LanguageShare] = [],
        release: LatestRelease? = nil,
        contributors: ContributorRoster = ContributorRoster()
    ) {
        self.detail = detail
        self.languages = languages
        self.release = release
        self.contributors = contributors
    }
}

/// 仓库洞察的数据来源 —— 领域层与网络层之间的**接缝**（同 `RepositoryDataSource`）。
public protocol RepoInsightsDataSource: Sendable {

    /// `GET /repos/{owner}/{repo}`。
    func repository(owner: String, repo: String) async throws -> RepositoryDetailDTO

    /// `GET /repos/{owner}/{repo}/languages` —— 返回**字节数**（`{语言: 字节}`）。
    func languages(owner: String, repo: String) async throws -> LanguageBytes

    /// `GET /repos/{owner}/{repo}/releases/latest`；`nil` = 没有发布过版本。
    func latestRelease(owner: String, repo: String) async throws -> RepoReleaseDTO?

    /// `GET /repos/{owner}/{repo}/contributors?per_page=100`。
    func contributors(owner: String, repo: String) async throws -> Page<RepoContributorDTO>
}

/// 让真实端点满足上面的接缝（协议是我们自己声明的，不是追溯适配）。
extension GitHubRepoInsightsEndpoint: RepoInsightsDataSource {}

/// 取他人仓库详情的四路数据（TECH_SPEC §9.11）。
///
/// ## 四个请求**并发**发出
///
/// 它们互不依赖（没有后一个需要前一个的结果），串行发等于把四次往返的延迟叠起来。
/// `async let` 是**结构化并发**：任一路抛出时其余几路会被自动取消，不会有孤儿请求
/// 悄悄占着配额。
///
/// ## 一路失败 ⇒ 整页失败（有意如此）
///
/// 看起来"分别降级"更友好（语言失败就只空着语言那一段），但 §8.5 把加载 / 失败态
/// **三档统一**了、并明写"各页面不得自行发挥"：首屏失败就是整屏失败 + 一个重试出口
/// （与 `ReposView.failureState` 完全一致）。分区块各自失败要再定义一套"块级失败态"，
/// 那是新的产品口径，不该由实现顺手定。
///
/// 唯一的例外是 `latestRelease`：它的 **404 在端点里已被翻译成 `nil`**
/// （见 `GitHubRepoInsightsEndpoint.latestRelease`），所以"没发过版本"不会让整页失败。
public struct LoadRepoInsights: Sendable {

    private let source: any RepoInsightsDataSource

    public init(source: any RepoInsightsDataSource) {
        self.source = source
    }

    /// - Parameter now: 显式传入，不内部取 `Date()`（相对文案要它，且必须可测）。
    /// - Throws: `RepositoryMappingError.malformedFullName`（`fullName` 不是 `owner/name`）
    ///   与四路请求里**除 404-release 外**的任何错误。
    public func load(fullName: String, now: Date) async throws -> RepoInsights {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)

        async let detailTask = source.repository(owner: owner, repo: repo)
        async let languagesTask = source.languages(owner: owner, repo: repo)
        async let releaseTask = source.latestRelease(owner: owner, repo: repo)
        async let contributorsTask = source.contributors(owner: owner, repo: repo)

        let (detailDTO, languageBytes, releaseDTO, contributorsPage) = try await (
            detailTask, languagesTask, releaseTask, contributorsTask
        )

        return RepoInsights(
            // ⚠️ 头部映射走 `RepositoryDetailMapper` —— 切片 6 的仓库详情页（§4.4）
            //    用的是**同一份**。曾经这里是 `private static func detail(from:)`，
            //    复制一份会让两个页面对同一个仓库显示不同的许可证 / 关注者数。
            detail: RepositoryDetailMapper.detail(from: detailDTO),
            // 排序与百分比换算**都在领域层做**：`/languages` 是个 JSON 对象，
            // `Dictionary` 的迭代顺序不确定（§9.11）—— 就地换算会让同一份响应两次解析
            // 得到两根顺序不同的占比条。
            languages: LanguageComposition.shares(from: languageBytes),
            release: releaseDTO.map(Self.release(from:)),
            contributors: ContributorRoster(
                contributors: contributorsPage.items.map {
                    Contributor(login: $0.login, avatarURL: $0.avatarURL.flatMap(URL.init(string:)))
                },
                // ⚠️ 这个布尔值是"总数是精确值还是下界"的唯一来源，不能丢。
                hasMore: contributorsPage.hasMore
            )
        )
    }

    // MARK: - 内部

    private static func release(from dto: RepoReleaseDTO) -> LatestRelease {
        LatestRelease(
            tagName: dto.tagName,
            name: dto.name,
            notes: dto.body,
            publishedAt: dto.publishedAt,
            assetCount: dto.assetCount
        )
    }
}
