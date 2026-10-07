import Foundation

/// 用户搜索结果 —— `GET /search/users` 的 `items` 元素（TECH_SPEC §4.6.1、§9.2、PRD §4.2）。
///
/// ## ⚠️ 四个字段是可选的，而且可能**根本不出现**
///
/// `name` / `bio` / `public_repos` / `followers` 在官方 OpenAPI 的
/// `user-search-result-item` schema 里是**可选**属性；而官方 REST 文档里
/// `GET /search/users` 的 200 示例**不含它们**（GHEC 与 GHES 两处文档一致，示例就是
/// 一坨 `login` / `id` / `avatar_url` / `type` / `score`）。
///
/// 两处官方材料互相矛盾 ⇒ 按"**拿不准的外部字段一律按可选处理**"办，因为两侧代价极不对称：
/// - **声明成可选**：真返回 ⇒ 卡片照原型显示人数；不返回 ⇒ 那一行不渲染。
/// - **声明成必需**：一旦真不返回 ⇒ **整个「用户」范围整页解不出**（一页空白）。
///
/// ## 因此**绝不把缺席填成 0**
///
/// `nil` 是"不知道"，`0` 是"就是零" —— 两者在界面上必须不同（同 `RepoSummary`
/// 的 `forkCount` / `canWrite` 那条纪律）。`UserHit.metaLabel` 拿不到数就**整段不渲染**，
/// 而不是写出"0 个公开仓库"这句我们并不知道真假的话。
///
/// ⚠️ 若真不返回、而产品仍要那两个数，唯一的路是**为每个结果补一次** `GET /users/{login}`
/// （主桶 5,000/小时，不紧张）。那是一笔新增的取数成本 ⇒ 需要产品拍板，
/// 已登记在 `REVIEW-CHECKLIST §6` 第 10 条的待裁定清单，**不在本切片顺手加**。
public struct SearchUserDTO: Sendable, Equatable, Decodable {

    public let login: String

    /// 昵称。**可以是 `null`**（很多人不填）。列表行不显示它，资料弹层显示。
    public let name: String?

    /// 简介。**可以是 `null`**。
    public let bio: String?

    /// 公开仓库数。**可以是 `null`，也可能整个键都不在**（见类型说明）。
    public let publicRepos: Int?

    /// 关注者数。**可以是 `null`，也可能整个键都不在**（见类型说明）。
    public let followers: Int?

    public init(
        login: String,
        name: String? = nil,
        bio: String? = nil,
        publicRepos: Int? = nil,
        followers: Int? = nil
    ) {
        self.login = login
        self.name = name
        self.bio = bio
        self.publicRepos = publicRepos
        self.followers = followers
    }

    private enum CodingKeys: String, CodingKey {
        case login
        case name
        case bio
        case publicRepos = "public_repos"
        case followers
    }
}
