import Foundation

/// 一次 GraphQL 查询里 `viewer` 下的三个字段（TECH_SPEC §9.14、决策 #74 / #76）。
///
/// ## ⚠️ 三个字段**同属一次往返**，是刻意的
///
/// PRD §4.17 的头部要「仓库 / Star」两个数，而热力图要一整年的日历 ——
/// 三者都挂在 `viewer` 这个**单对象**下，放进同一次查询**点数仍然是 1**
/// （§13.2 纪律 2 的反面：连接挂在同一层**互不相乘**，"加字段不扣点、加嵌套才扣点"）。
/// 于是省下的不是"一点点"，而是一次完整往返。
///
/// ## ⚠️ 两个计数连接都必须 `first: 1`
///
/// 我们用 `totalCount`，而**潜在请求数按 `first` 算**（§13.2）——
/// 写成 `first: 100` 会让这一点数变成 100 点，而且**不会报错**。
/// 只要 `totalCount` 的话，`first: 1` 与 `first: 100` 给出的数**完全一样**。
///
/// ## ⚠️ `weeks` / `contributionDays` 是**数组**，本类型里看不到 `first:`
///
/// 见 `ContributionCalendarDTO` 的类型说明 —— 数组字段不接受 `first:` 参数，
/// 而且**不贡献请求数**。
public struct ViewerActivityDTO: Sendable, Equatable, Decodable {

    public let contributionsCollection: ContributionsCollectionDTO

    /// `viewer.starredRepositories(first: 1) { totalCount }` —— 头部「Star」那个数。
    public let starredRepositories: TotalCountDTO

    /// `viewer.repositories(first: 1, affiliations: […]) { totalCount }` —— 头部「仓库」那个数。
    ///
    /// ⚠️ `affiliations` 必须**显式**写成
    /// `[OWNER, COLLABORATOR, ORGANIZATION_MEMBER]`（决策 #76）：
    /// 它的默认值是**只算自己拥有的**（`[OWNER]`），而仓库列表用的是
    /// `affiliation=owner,collaborator,organization_member`（决策 #35）
    /// ⇒ 不写就会看到"我的页说 42 个、仓库列表里 60 个"——
    /// 两个数**各自都是真的**，摆在一起才成了假话。
    public let repositories: TotalCountDTO

    public init(
        contributionsCollection: ContributionsCollectionDTO,
        starredRepositories: TotalCountDTO,
        repositories: TotalCountDTO
    ) {
        self.contributionsCollection = contributionsCollection
        self.starredRepositories = starredRepositories
        self.repositories = repositories
    }

    /// `contributionsCollection` 这一层在 schema 里是**非空对象**，所以它只包着一个日历字段。
    public struct ContributionsCollectionDTO: Sendable, Equatable, Decodable {

        public let contributionCalendar: ContributionCalendarDTO

        public init(contributionCalendar: ContributionCalendarDTO) {
            self.contributionCalendar = contributionCalendar
        }
    }
}

/// `… { totalCount }` 这个形状 —— 两个计数连接共用它（形状逐字相同，`first` 不同）。
///
/// ⚠️ 它**放在本文件而不是单独一个文件**：它只服务上面的类型，
/// 而单独成文件会让"这个包一共有几个 GraphQL 小 DTO"变得不容易一眼看完。
public struct TotalCountDTO: Sendable, Equatable, Decodable {

    public let totalCount: Int

    public init(totalCount: Int) {
        self.totalCount = totalCount
    }
}
