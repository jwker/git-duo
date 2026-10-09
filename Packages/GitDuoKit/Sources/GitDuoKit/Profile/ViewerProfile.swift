import Foundation
import GitDuoCore

/// 「我的」页个人资料头部（PRD §4.17 第 2 条、TECH_SPEC §9.14）。
///
/// ## ⚠️ `name` / `bio` 是 Optional，而且 `nil` **不是**空串
///
/// PRD §4.17 逐字：「昵称与简介取不到时**整行不渲染** —— 不留空行、也不显示占位
/// （"没有"与"空字符串"不是一回事）」。
///
/// 这一条在类型上就成立：`String?` 让视图**不得不**先解包才能画那一行，
/// 而如果这里是 `String`（缺失时填 `""`），视图照着画只会得到一个空行 ——
/// 屏幕上看起来像"排版坏了"，而真相是"这个人没填昵称"。
/// （同 `SearchUserDTO` 那条「**绝不把缺席填成 0**」的纪律。）
///
/// ## 有意**不装头像地址**
///
/// 与 `AuthorDTO` 同一条判据：界面上的头像一律由 `UserAvatar` 从 `login` **现算**
/// （首字母 + 由登录名派生的兜底色）。原型 `12-me.js` 画的也正是
/// `<div class="big-avatar" style="…">J</div>` 这样一个首字母块，不是网络图片。
/// 装一个没有消费端的字段，等于多一处会因为服务端形状变化而炸的地方。
public struct ViewerProfile: Sendable, Hashable {

    /// 登录名。**它同时是头像的种子**。
    public let login: String

    /// 昵称。`nil` ⇒ 那一行不渲染。
    public let name: String?

    /// 简介。`nil` ⇒ 那一行不渲染。
    public let bio: String?

    public init(login: String, name: String? = nil, bio: String? = nil) {
        self.login = login
        self.name = name
        self.bio = bio
    }
}

/// 头部三个统计项分别是哪个（PRD §4.17 第 2 条、决策 #76）。
///
/// ⚠️ 显示名**逐字取自原型** `12-me.js`：`仓库` / `Star` / `Follower`
/// —— 注意第三个是英文单数的 `Follower`（不是 `关注者`，也不是 `Followers`），
/// 与仓库卡片上那个 `Star` 同一风格。别顺手"修正"它。
public enum ProfileStatKind: String, Sendable, Hashable, CaseIterable, Identifiable {

    case repositories
    case stars
    case followers

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .repositories: "仓库"
        case .stars: "Star"
        case .followers: "Follower"
        }
    }
}

/// 一个统计项（标题 + 数字）。
public struct ProfileStatItem: Sendable, Hashable, Identifiable {

    public let kind: ProfileStatKind
    public let value: Int

    public var id: String { kind.rawValue }

    public var title: String { kind.title }

    /// 屏幕上那个数字 —— **千分位、不缩写**。
    ///
    /// ⚠️ 与仓库卡片上的 `2.3k` **有意不同**：卡片窄、要省宽度；
    /// 头部这三个数是用户要**读准**的（同 `StarCopy.buttonTitle` 的口径，
    /// 2026-10-06 已拍板，TECH_SPEC §9.11）。
    /// 原型那三个演示值（`42` / `318` / `126`）都不到四位，看不出这个差别。
    public var valueText: String { GroupedNumber.string(from: value) }

    public init(kind: ProfileStatKind, value: Int) {
        self.kind = kind
        // 计数不该为负：真出现时显示 `-1` 比显示 `0` 更让人困惑（同 `GroupedNumber` 的口径）。
        self.value = max(0, value)
    }
}

/// 头部三个统计项（决策 #76）。
///
/// ## 三个数各从哪来（**两条不同的取数路径**）
///
/// | 项 | 来源 |
/// |---|---|
/// | 仓库 | GraphQL `viewer.repositories(first:1, affiliations:[OWNER, COLLABORATOR, ORGANIZATION_MEMBER]) { totalCount }` |
/// | Star | GraphQL `viewer.starredRepositories(first:1) { totalCount }` |
/// | Follower | `GET /user` 的 `followers` |
///
/// 前两个与热力图**共用一次 GraphQL 往返**（加两个 `first:1` 的计数连接，
/// **点数仍是 1** —— §13.2 的"加字段不扣点、加嵌套才扣点"）；
/// 第三个跟着 `GET /user` 走。
///
/// ## ⚠️⚠️ 三个都是 Optional，而这不是"防御性编码"
///
/// 每一个 `nil` 都对应一个**真实可达**的路径：
///
/// | 情形 | 结果 |
/// |---|---|
/// | 两路都成 | 三项齐全 |
/// | `GET /user` 失败（断网 / 那一发 5xx） | 剩「仓库」「Star」两项 |
/// | GraphQL 那一路失败 | 剩「Follower」一项 |
/// | 两路都失败 | **一项都没有** ⇒ 整行统计不画 |
///
/// 第三种情形值得多说一句：**GraphQL 的错误可以是"部分成功"** ——
/// 官方语义是 HTTP 200 + body 里 `errors` 有值，而 `data` 里**没出错的那几个字段照常返回**
/// （`TECH_SPEC §4.3` 第 2 条点名过这条）。所以"热力图那一格没拿到、但两个计数拿到了"
/// 不是假想，它就是决策 #76 末句说的「失败要隔离」要处理的形状。
///
/// 于是这里的 Optional **不是在防"服务端不返回 followers"**
/// （官方 OpenAPI 里 `private-user` 与 `public-user` 两个形状都把它列为必需，
/// 2026-10-09 核实过），而是在**忠实表达"这一项这次有没有拿到"**。
///
/// ## ⚠️ 拿不到的项**整项不画**，不填 `0`、也不画占位符
///
/// `0` 是"就是零"，`nil` 是"不知道"，两者在界面上必须不同
/// （同 `SearchUserDTO` 那条「绝不把缺席填成 0」的纪律）。
/// 而 PRD 没有给"未知"的样式 ⇒ 沿同一条先例「拿不到就整段不渲染」，
/// **不新造一个 PRD 没有的占位符**（那是"替用户拍板"）。
public struct ProfileStats: Sendable, Hashable {

    /// 仓库数（GraphQL，口径 = 决策 #35 的 `affiliation`，必须与仓库列表同数）。
    public let repositories: Int?

    /// Star 数（GraphQL）。
    ///
    /// ⚠️ 不承诺精确：`StarredRepositoryConnection.isOverLimit` 的官方注释写着
    /// *"this is true for users that have many stars"* ⇒ **Star 特别多的人这个数可能被截断**
    /// （决策 #76 已如实登记）。
    public let stars: Int?

    /// 关注者数（`GET /user`）。
    public let followers: Int?

    public init(repositories: Int? = nil, stars: Int? = nil, followers: Int? = nil) {
        self.repositories = repositories.map { max(0, $0) }
        self.stars = stars.map { max(0, $0) }
        self.followers = followers.map { max(0, $0) }
    }

    /// 该画哪几项 —— **顺序固定为 仓库 / Star / Follower**，缺的那项直接跳过。
    ///
    /// 顺序写死在这里（而不是让视图按 `ProfileStatKind.allCases` 遍历再查表），
    /// 是因为"哪几项有值"与"按什么顺序画"必须同时决定 —— 分两处做，
    /// 就会出现"少了一项但间距还是按三项均分"这种只差一点点、又说不清哪里怪的样子。
    public var items: [ProfileStatItem] {
        var items: [ProfileStatItem] = []
        if let repositories {
            items.append(ProfileStatItem(kind: .repositories, value: repositories))
        }
        if let stars {
            items.append(ProfileStatItem(kind: .stars, value: stars))
        }
        if let followers {
            items.append(ProfileStatItem(kind: .followers, value: followers))
        }
        return items
    }

    /// 一项都没有 ⇒ 整行统计不画（而不是画一行空的东西）。
    public var isEmpty: Bool { items.isEmpty }

    public static let empty = ProfileStats()
}
