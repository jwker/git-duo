import Foundation

/// 仓库详情头部 —— `GET /repos/{owner}/{repo}`（TECH_SPEC §9.11、§4.6.2、§6.2）。
///
/// ## 它服务的是「他人仓库只读页」，而不是仓库列表
///
/// 与 `RepositoryDTO` 有 `fullName` / `description` / `starCount` / `forkCount` / `permissions`
/// 五个重叠字段，但**有意不合并**：两者服务不同端点、字段集不同，
/// 合并会让列表端点被迫解一堆只有详情页才用的字段（`topics` / `license` / `default_branch`…），
/// 而"某天列表页因为列表根本不需要的字段解不出而整页失败"这种事很难排查。
///
/// ## ⚠️ 三个字段陷阱（都在下面各自的属性上写清楚了）
///
/// 1. **Watch 计数必须读 `subscribers_count`**，不是 `watchers_count`。
/// 2. `open_issues_count` **把 PR 也算作 Issue** —— 所以本类型**根本不解它**。
/// 3. `topics` 缺失与空数组**等价**（视图侧按 `?? []` 处理，不该因此报错）。
public struct RepositoryDetailDTO: Sendable, Equatable, Decodable {

    /// `owner/name`。GitHub 保证它有且只有一个 `/`。
    public let fullName: String

    /// 仓库简介。**可以是 `null`**。
    public let description: String?

    /// 话题标签（PRD §4.13 头部的蓝色小标签）。
    ///
    /// **可以是 `nil`**：它是**可选字段**，在旧媒体类型下会被整段省略。
    /// 这里的 `nil` 与空数组**语义相同**（都是"没有标签"），
    /// 所以视图按 `?? []` 处理；声明成必需的 `[String]` 会让"省略"变成整页报错。
    public let topics: [String]?

    /// 许可证。**可以是 `null`**（未指定许可证的仓库很常见）。
    public let license: License?

    /// 默认分支名 —— 分支解析规则的输入（§9.4.1：进仓库先解析默认分支 / 记忆分支）。
    ///
    /// **必需**：它是"打开仓库文件"这条链的起点，缺了就只能猜一个 `main`，
    /// 而猜错的表现是"文件树空白"（看起来像仓库是空的）。
    public let defaultBranch: String

    public let starCount: Int

    public let forkCount: Int

    /// **Watch 计数 —— 注意来源字段。**
    ///
    /// ⚠️ GitHub 的仓库对象里有两个名字极像的字段，含义完全不同：
    /// - `subscribers_count` —— **真正的关注者数**（点了 Watch 的人），就是 PRD 里 `Watch · {n}`
    ///   要显示的那个。
    /// - `watchers_count` —— **`stargazers_count` 的历史别名**，与 Star 数**恒相等**。
    ///
    /// 读错的那一个不会报错，只会让 `Watch · 2,341` 与旁边的 `Star · 2,341` 显示成同一个数
    /// —— 一个"看着很合理"的错值。所以这里显式写明来源。
    public let watcherCount: Int

    /// 最近推送时间（PRD §4.13 头部 `{更新时间} 更新`）。
    ///
    /// **可以是 `null`**：从未推送过任何提交的仓库就是这样。
    public let pushedAt: Date?

    /// 当前令牌对该仓库的权限全集（**可写性判定的唯一来源**，§9.11、§8.1）。
    ///
    /// ⚠️ 它与 `subscribers_count` 不一样：`permissions` **只在已认证请求里返回**，
    /// 且 GitHub 明确规定它代表"**当前令牌**对该仓库的权限"。
    /// 缺失必须解释成**不可写**（`RepositoryMapper` 映射成 `.none`）——
    /// 缺权限时默认可写，会让用户点进编辑器、改完文件、提交时才吃 403。
    public let permissions: RepositoryPermissionsDTO?

    /// owner 摘要 —— 目前只消费头像地址（走查第 72 条：详情头部换 owner 头像）。
    ///
    /// **必需**（非可选）：`GET /repos/{o}/{r}` 的仓库对象恒带 `owner`；
    /// 缺了就是响应形状变了，"整页报错"比"悄悄退化"诚实（同 `starCount` 的口径）。
    public let owner: RepositoryOwnerDTO

    /// REST 的 `license` 对象（`{ key, name, spdx_id, url }`）。
    ///
    /// 两个字段都要：列表里显示的是 **SPDX 短名**（`MIT` / `Apache-2.0`，与原型一致），
    /// 而 `spdx_id` 在"有 LICENSE 文件但不是标准许可证"时会是字符串 `NOASSERTION`
    /// —— 那一刻只有 `name` 是可读的，所以要能退到它。
    public struct License: Sendable, Equatable, Decodable {
        public let name: String?
        public let spdxID: String?

        public init(name: String? = nil, spdxID: String? = nil) {
            self.name = name
            self.spdxID = spdxID
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case spdxID = "spdx_id"
        }
    }

    public init(
        fullName: String,
        description: String? = nil,
        topics: [String]? = nil,
        license: License? = nil,
        defaultBranch: String,
        starCount: Int,
        forkCount: Int,
        watcherCount: Int,
        pushedAt: Date? = nil,
        permissions: RepositoryPermissionsDTO? = nil,
        owner: RepositoryOwnerDTO = RepositoryOwnerDTO()
    ) {
        self.fullName = fullName
        self.description = description
        self.topics = topics
        self.license = license
        self.defaultBranch = defaultBranch
        self.starCount = starCount
        self.forkCount = forkCount
        self.watcherCount = watcherCount
        self.pushedAt = pushedAt
        self.permissions = permissions
        self.owner = owner
    }

    private enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case description
        case topics
        case license
        case defaultBranch = "default_branch"
        case starCount = "stargazers_count"
        case forkCount = "forks_count"
        // ⚠️ 不是 `watchers_count`（那个等于 stargazers_count）
        case watcherCount = "subscribers_count"
        case pushedAt = "pushed_at"
        case permissions
        case owner
    }

    // ⚠️ `open_issues_count` **有意不解码**：它把 PR 也算作 Issue（官方文档明确），
    //    而 PRD §4.14 的说明行是「开放 {N} 个」Issue。直接拿它显示会与下方列表的条数对不上，
    //    而"数字对不上"会被读成"这个 App 数不准"。探索 Issues 列表的 N 用**已加载条目数**
    //    （2026-10-06 用户拍板）—— 零额外请求，且与屏幕上的列表逐条对得上。
    //    将来「我的仓库」四分区若要显示精确的 open issue 计数，请另走 Search
    //    （`repo:x/y type:issue state:open`），那时再决定要不要花那一格搜索配额。
}
