import Foundation
import GitDuoCore

/// 会话（Issue / PR）的两类 —— PRD §4.2 的「Issue · PR」范围、§4.15。
///
/// `rawValue` 用于**结果行的 `id` 前缀**（见 `SearchRow.id`），不用于界面文案。
public enum ConversationKind: String, Sendable, Hashable, CaseIterable, Identifiable {

    case issue
    case pullRequest = "pr"

    public var id: String { rawValue }

    /// 读屏标签，也是"点开去哪一页"的口径名（PRD §4.2 的结果行去向表）。
    public var title: String {
        switch self {
        case .issue: "Issue"
        case .pullRequest: "Pull Request"
        }
    }
}

/// 搜索结果的一行（PRD §4.2）。
///
/// ## 为什么是 enum 而不是"一个宽结构体 + 一堆可空字段"
///
/// 后者会让「仓库结果行上带一个 `followers`」「代码结果行上带一个 `state`」
/// 这类根本不存在的组合在**类型上合法**，于是视图里会多出一片"这个字段这会儿有没有值"
/// 的判断，而那些分支永远没人走到、也永远没人删。
/// 四个范围各一种行，就写成四种行。
public enum SearchRow: Sendable, Hashable, Identifiable {

    case repository(RepositoryHit)
    case user(UserHit)
    case code(CodeHit)
    case conversation(ConversationHit)

    /// `ForEach` 的键。
    ///
    /// ⚠️ **每种前缀都不同**：切片 5 的缓存按「范围 · 关键词」存，
    /// 切回上一个范围时整份列表会被换掉，而 `ForEach` 认的就是 `id`。
    /// 若两种行可能算出同一个 `id`（比如仓库行的 `owner/name` 与代码行里某个路径），
    /// 切范围的那一刻 `ForEach` 会认错行（渲染告警 + 视觉上是重复/错位）。
    ///
    /// 代码行的键**必须含仓库全名**：只按 `path` 去重的话，
    /// 两个不同仓库里的同名文件（`README.md`、`Package.swift`）会被当成同一行。
    public var id: String {
        switch self {
        case let .repository(hit): "repo:\(hit.fullName)"
        case let .user(hit): "user:\(hit.login)"
        case let .code(hit): "code:\(hit.repoFullName)/\(hit.path)"
        case let .conversation(hit): "\(hit.kind.rawValue):\(hit.repoFullName)#\(hit.number)"
        }
    }
}

// MARK: - 四种行

/// 仓库结果行（原型 `repoResultRow`）。
///
/// ## 为什么不复用 `RepoSummary`
///
/// 这四行只来自 `GET /search/repositories`，而搜索响应**不返回** Fork 数 / 私有性 / 权限
/// ⇒ 复用就要给那三个字段填 `nil`，卡片上于是多出三处"要不要渲染"的判断，
/// 而搜索页一处都用不上。判据仍是决策 #43（参数用领域模型 ⇒ 卡片留 Feature），
/// 这里只是把"领域模型"取窄一点。
///
/// ⚠️ 因此它也**没有** `createdAt` / `pushedAt` —— 那是榜单指标的原料（见 `RepoSummary` 的说明），
/// 搜索页不显示"创建于"。
public struct RepositoryHit: Sendable, Hashable, Identifiable {

    /// `owner/name`。GitHub 保证它恰好含一个 `/`。
    public let fullName: String

    /// 仓库简介。**可以是 `nil`**（未填简介的仓库很常见）。
    public let description: String?

    /// 主语言。**可以是 `nil`**（空仓库、或只有配置文件）。
    public let language: String?

    public let starCount: Int

    public var id: String { fullName }

    public init(fullName: String, description: String? = nil, language: String? = nil, starCount: Int) {
        self.fullName = fullName
        self.description = description
        self.language = language
        self.starCount = starCount
    }

    /// 卡片把 owner 弱化显示（原型 `.t1` 里 `<span style="color:var(--text3)">${owner}/</span>`）。
    ///
    /// 走 `RepositoryMapper.splitFullName` 那**一个**实现（`try?` 吞掉错误即可）：
    /// 各写一遍 `count == 2` 的判断，迟早有一处写成 `>= 2` 而放行 `a/b/c`。
    /// 形状不符时**不猜** —— 整串都当 `name`、`owner` 为空，卡片上肉眼即可发现
    /// （猜一个 owner 会让路由指向不存在的仓库）。
    public var owner: String { (try? RepositoryMapper.splitFullName(fullName))?.owner ?? "" }
    public var name: String { (try? RepositoryMapper.splitFullName(fullName))?.name ?? fullName }

    /// `2,341` —— 与仓库头部统计同一套**千分位**（`GroupedNumber`），不是 `124k` 那种缩写：
    /// 搜索结果是用户要读准的地方。
    public var starLabel: String { GroupedNumber.string(from: starCount) }
}

/// 用户结果行（原型 `userResultRow`）。
///
/// ⚠️ 与仓库行**有意不同**：这里的人数用 **k/m 缩写**（原型数据里是 `'210k'`、`'98k'`），
/// 与仓库 Star 的千分位不是一套 —— 两张卡在原型里就是这么分的，别顺手统一。
public struct UserHit: Sendable, Hashable, Identifiable {

    public let login: String

    /// 昵称。**可以是 `nil`**（很多人不填）。结果行上不显示它，资料弹层里显示。
    public let name: String?

    /// 简介。**可以是 `nil`**。
    public let bio: String?

    public let publicRepoCount: Int
    public let followerCount: Int

    public var id: String { login }

    public init(
        login: String,
        name: String? = nil,
        bio: String? = nil,
        publicRepoCount: Int,
        followerCount: Int
    ) {
        self.login = login
        self.name = name
        self.bio = bio
        self.publicRepoCount = publicRepoCount
        self.followerCount = followerCount
    }

    /// `@登录名`（原型结果行与弹层都这么写）。
    public var handle: String { "@\(login)" }

    /// 结果行副标题：`5 个公开仓库 · 210k 关注者`（原型 `userResultRow` 逐字）。
    public var metaLabel: String {
        "\(publicRepoCount) 个公开仓库 · \(CompactNumber.string(from: followerCount)) 关注者"
    }

    /// 资料弹层副标题：`@dev-j · 5 个仓库 · 210k 关注者`（原型 `openUserSheet` 逐字）。
    ///
    /// ⚠️ 比结果行少了「公开」二字，且多了 `@登录名` —— **两处原型就是这么写的**，不是笔误。
    public var profileMetaLabel: String {
        "\(handle) · \(publicRepoCount) 个仓库 · \(CompactNumber.string(from: followerCount)) 关注者"
    }
}

/// 代码结果行（原型 `codeResultRow`）。
public struct CodeHit: Sendable, Hashable, Identifiable {

    /// 文件在仓库里的路径（原型 `c.p`）。
    public let path: String

    /// 所属仓库全名（原型 `c.r`）。
    public let repoFullName: String

    /// 语言。**可以是 `nil`**（GitHub 认不出的文件类型）。
    public let language: String?

    /// 命中的那行代码（原型 `.sr-code` 里的 `c.l`）。
    ///
    /// **可以是 `nil`**：它来自 `text_matches`，而服务端只在请求带
    /// `Accept: application/vnd.github.text-match+json` 时才返回（§9.2）。
    /// `nil` ⇒ 卡片**不渲染**那一行，而不是显示一个空框。
    public let snippet: String?

    public var id: String { "\(repoFullName)/\(path)" }

    public init(path: String, repoFullName: String, language: String? = nil, snippet: String? = nil) {
        self.path = path
        self.repoFullName = repoFullName
        self.language = language
        self.snippet = snippet
    }

    /// 卡片副标题：`{仓库} · {语言}`（原型 `codeResultRow`）。
    ///
    /// ⚠️ 语言为 `nil` 时**整段去掉**（只留仓库）—— 原型那处会拼出
    /// `my-git/gitduo · undefined`。原型的演示数据里语言永远有值，所以它没覆盖这个情形；
    /// 遇到没覆盖的情形就不要编。
    public var metaLabel: String {
        guard let language, !language.isEmpty else { return repoFullName }
        return "\(repoFullName) · \(language)"
    }
}

/// Issue / PR 结果行（原型 `convResultRow`）。
public struct ConversationHit: Sendable, Hashable, Identifiable {

    public let kind: ConversationKind

    /// 仓库内编号 —— 卡片上的 `#42`，也是跳详情页的键。
    public let number: Int

    public let title: String

    /// 所属仓库全名。
    ///
    /// ⚠️ 原型那行是**写死的** `"my-git/gitduo"`（演示数据只有这一个仓库）；
    /// 真实搜索跨仓库，所以它是每个结果自己的值。
    public let repoFullName: String

    /// 展示状态。
    ///
    /// ⚠️ **复用 `PullRequestState`**（切片 4 的 PR 列表那个枚举），不新造一个：
    /// 状态胶囊与状态图标在探索页的 PR 列表与搜索页里必须是**同一套**，
    /// 各写一份必然分叉（"合并"的图标在一处带箭头、另一处不带）。
    /// Issue 只会取到 `.open` / `.closed` —— Issue 没有「已合并」。
    public let state: PullRequestState

    /// 最近更新时刻（卡片上的 `· 2 小时前`）。
    public let updatedAt: Date

    public var id: String { "\(kind.rawValue):\(repoFullName)#\(number)" }

    public init(
        kind: ConversationKind,
        number: Int,
        title: String,
        repoFullName: String,
        state: PullRequestState,
        updatedAt: Date
    ) {
        self.kind = kind
        self.number = number
        self.title = title
        self.repoFullName = repoFullName
        self.state = state
        self.updatedAt = updatedAt
    }

    /// 读屏用的状态词（图标不能只靠形状传达状态）。
    public var stateLabel: String { state.label }

    /// 卡片副标题：`my-git/gitduo #42 · 2 小时前`（原型 `convResultRow` 逐字）。
    ///
    /// ⚠️ **时间那一段恒在**：原型的演示数据里 `d` 可能为空（于是整段省掉），
    /// 而真实响应的 `updated_at` 是**必需字段**，永远有值。
    /// 若照着原型写一个可选分支，就会有一条永远走不到的代码，而后人不敢删。
    public func metaLabel(now: Date) -> String {
        "\(repoFullName) #\(number) · \(RelativeTime.string(from: updatedAt, now: now))"
    }
}
