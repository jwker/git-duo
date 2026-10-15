import Foundation

/// 仓库摘要 —— **别处看到一个仓库**时的只读快照（决策 #43、PRD §3.6 / §4.1 / §4.12）。
///
/// ## 它为什么不是 `Repository`
///
/// `Repository` 带 `permissions`（可写性判定的唯一来源）。但生产 `RepoSummary` 的**三个数据源
/// 里有两个给不出权限**：
///
/// | 数据源 | `permissions` |
/// |---|---|
/// | 置顶（GraphQL `viewer.pinnedItems`） | ⚠️ 没有 `permissions` 对象，但有等价的 `viewerPermission` ⇒ 见 `canWrite` |
/// | 探索榜（REST `GET /search/repositories`） | ❌ 搜索响应不返回 |
/// | 仓库列表（REST `GET /user/repos`） | ✅（那条路径直接用 `Repository`，不走本类型） |
///
/// 若复用 `Repository` 并填 `Permissions.none`，就造出了一个 `canWrite == false` 的领域对象
/// —— 而它对应的**可能正是用户自己的仓库**（置顶里放自己的仓库是常态，公开仓库也人人搜得到）。
/// 那一刻"不可写"就是个错值，且长得和正常值一模一样。
///
/// ## 为什么 `forkCount` / `isPrivate` / `canWrite` 是可选的
///
/// 因为**表达的是"这个数据源给不给"，不是"可能是未知值"**：
/// `GET /search/repositories` 的返回里没有 Fork 数与私有性，而置顶有。卡片据此决定
/// 那一格渲不渲染（`nil` ⇒ 不渲染）。把它们做成非可空，就只能给搜索路径填一个假值
/// —— 而 `Fork · 0` 与"搜索接口不告诉我们"是两件完全不同的事。
///
/// ⚠️ `canWrite` 是 2026-10-06 补的（决策 #43 补充条）：**首页置顶卡与最近访问行
/// 必须在进入详情页之前就定下是"自己的仓库"还是"他人仓库"**（铁律 #7），
/// 而原型的置顶演示数据里就**混着一个他人仓库**。`nil` 仍然不是 `false` —— 它是"不知道"，
/// 不能当"不可写"用（要用请走 `canOpenWritableDetail`，那里把保守默认写在一处）。
///
/// ⚠️ **有意不含 `createdAt` / `pushedAt`**：那两样是**榜单指标**的原料（`🆕 08-05 创建` /
/// `⚡ 30 分钟前推送`，见 `TrendingMetric`），不是"仓库摘要"的组成部分 ——
/// 首页置顶卡片压根不用它们。指标随榜单一起由探索页自己的行模型承载。
public struct RepoSummary: Sendable, Hashable, Identifiable {

    /// `owner/name`。GitHub 保证它恰好含一个 `/`。
    public let fullName: String

    /// 仓库简介。**可以是 `nil`**（未填简介的仓库很常见）。
    public let description: String?

    /// 主语言。**可以是 `nil`**（空仓库、或只有配置文件）。
    public let language: String?

    public let starCount: Int

    /// Fork 数。`nil` = **该数据源不提供**（搜索响应）。
    public let forkCount: Int?

    /// 是否私有。`nil` = **该数据源不提供**（搜索响应）；
    /// 最近访问这类纯本地记录也走 `nil`（本机只存全名与时间，见 `RecentVisit`）。
    public let isPrivate: Bool?

    /// 当前登录用户对该仓库是否有写权限。`nil` = **该数据源不提供**（搜索响应）。
    ///
    /// 判定见 `RepoSummaryMapper`（GraphQL `viewerPermission` ⇒ `ADMIN`/`MAINTAIN`/`WRITE`）。
    /// ⚠️ **不要直接读它来做路由分流** —— 那样每个调用点都要自己决定"`nil` 算哪一边"，
    /// 而两处必然会有一处选了另一侧。用 `canOpenWritableDetail`。
    public let canWrite: Bool?

    /// owner 的头像地址。**可以是 `nil`** —— 取不到时界面回退首字母兜底圆（走查第 72 条）。
    ///
    /// 来源随数据源：置顶卡（GraphQL `owner.avatarUrl`）恒有值；
    /// 探索榜（REST 搜索响应 `owner.avatar_url`）也恒有值 ——
    /// `nil` 只出现在"响应形状变了 / 测试夹具没带"的场合，兜底表现统一是首字母圆块。
    /// ⚠️ 别当长期资产：EMU 账号的地址约 20 分钟失效（`RepositoryOwnerDTO` 的说明）。
    public let ownerAvatarURL: URL?

    public init(
        fullName: String,
        description: String? = nil,
        language: String? = nil,
        starCount: Int,
        forkCount: Int? = nil,
        isPrivate: Bool? = nil,
        canWrite: Bool? = nil,
        ownerAvatarURL: URL? = nil
    ) {
        self.fullName = fullName
        self.description = description
        self.language = language
        self.starCount = starCount
        self.forkCount = forkCount
        self.isPrivate = isPrivate
        self.canWrite = canWrite
        self.ownerAvatarURL = ownerAvatarURL
    }

    /// `Identifiable` 的 id 用全名：列表去重、`ForEach` 稳定性都依赖它
    /// （与 `Repository.id` 同一口径）。
    public var id: String { fullName }

    /// **路由分流**用的判定：`true` ⇒ 进「自己的仓库详情」，`false` ⇒ 进「他人只读页」。
    ///
    /// ⚠️ `nil`（数据源没给）按**不可写**处理 —— 这是**保守**的那一侧，与
    /// `Permissions.canWrite` 的取向一致：判错的代价是"自己的仓库看到只读页"，
    /// 而反过来（把他人的仓库判成可写）会给他长出编辑入口、改完文件才吃 403。
    /// 把默认值收在这里，是为了让"保守在哪一侧"只有一处答案。
    public var canOpenWritableDetail: Bool { canWrite == true }
}

extension RepoSummary {

    /// 拆出来的 owner 与仓库名 —— 卡片要把 owner 弱化显示（原型 `.pin-card .pn` 的 `.owner`）。
    ///
    /// **走 `RepositoryMapper.splitFullName` 那一个实现**（`try?` 吞掉错误即可）：
    /// 各写一遍 `count == 2` 的判断，迟早有一处写成 `>= 2` 而放行 `a/b/c`。
    ///
    /// 这里**不抛错** —— `RepoSummary` 的入口（Mapper）已经校验过一次，
    /// 而 `owner` / `name` 是视图直接读的属性、没有 `throws` 的位置可用。
    /// 形状不符时**不猜**：整串都当 `name`、`owner` 为空 ——
    /// 那会让卡片显示成"没有 owner 的仓库名"，肉眼即可发现，
    /// 而不是被悄悄拼接成别的东西（猜一个 owner 会让路由指向不存在的仓库）。
    public var owner: String {
        (try? RepositoryMapper.splitFullName(fullName))?.owner ?? ""
    }

    public var name: String {
        (try? RepositoryMapper.splitFullName(fullName))?.name ?? fullName
    }
}
