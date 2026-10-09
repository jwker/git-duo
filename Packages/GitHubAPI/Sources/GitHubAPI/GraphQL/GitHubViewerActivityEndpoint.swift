import Foundation

/// 「我的」页的热力图 + 两个计数 —— 一次 GraphQL 查询（TECH_SPEC §9.14、决策 #74 / #76）。
///
/// ## ⚠️ 三个字段**同属一次往返**，这是本类型的全部意义
///
/// 热力图要一整年的日历，头部要「仓库」「Star」两个数。三者都挂在 `viewer` 这个
/// **单对象**下 ⇒ 放进同一次查询**点数仍然是 1**（§13.2 纪律 2 的反面：
/// 连接挂在同一层**互不相乘**，"加字段不扣点、加嵌套才扣点"）。
/// 省下的不是"一点点"，而是一次完整往返。
///
/// ## ⚠️ 两个计数连接都写死 `first: 1`，**不进变量**
///
/// 我们要的只是 `totalCount`，而**潜在请求数按 `first` 算**（§13.2）——
/// 写成 `first: 100` 会让这一点数变成 100 点，而且**不会报错**：
/// `first: 1` 与 `first: 100` 给出的 `totalCount` **完全一样**。
///
/// 与 `GitHubPinnedItemsEndpoint` 把 `first` 放进变量的做法**有意相反**：
/// 那里 `maximumCount` 是一个会变的业务口径（GitHub 置顶栏的容量），值得留一个名字；
/// 这里的 `1` 是"点数预算的边界"，多一个能改的地方就多一次把 1 打成 100 的机会。
/// 所以它**写在查询文本里**，并由单测断言文本里确实是 `first: 1`。
///
/// ## ⚠️ `affiliations` 必须显式写全（决策 #76）
///
/// 它的**默认值只算自己拥有的**（`[OWNER]`），而仓库列表用的是
/// `affiliation=owner,collaborator,organization_member`（决策 #35）⇒
/// 不写就会看到"「我的」页说 42 个、仓库列表里 60 个"——
/// 两个数**各自都是真的**，摆在一起才成了假话。
///
/// 写成**字面量**（而不是变量）与 `types: [REPOSITORY]` 同理：取值集合由我们的口径固定，
/// 写成变量只会多一个"调用方传错就静默少算"的入口。
///
/// ## 数组不是连接 ⇒ 热力图一条连接都不开
///
/// `contributionCalendar.weeks` 与 `ContributionCalendarWeek.contributionDays`
/// 官方 schema 里是 `[X!]!`（见 `ContributionCalendarDTO` 的说明）：
/// **不接受 `first:`、也不贡献请求数**。所以这一次查询的请求数正好是 **2**（两个计数连接），
/// `round(2 ÷ 100) = 0` ⇒ 按"最小 1 点"计 ⇒ **总共 1 点**。
public struct GitHubViewerActivityEndpoint: Sendable {

    private let client: GitHubGraphQLClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var transport: HTTPTransport { client.transport }

    public init(client: GitHubGraphQLClient) {
        self.client = client
    }

    /// 取回热力图日历与两个计数。
    ///
    /// - Throws: `GitHubError.graphQLErrors(messages:partialData:)`（**HTTP 200 也可能是失败**）、
    ///   `GitHubError.decoding`（形状完全不符），以及 transport 归一化出的网络 / 状态码错误。
    ///
    /// ## ⚠️ 部分成功时**整块抛错**，不打捞那份 `partialData`
    ///
    /// `GitHubGraphQLClient` 刻意把"`data` + `errors` 并存"抛成一个带 `partialData` 的错误，
    /// 好让调用方自己决定。这里的选择是**不打捞**（`LoadProfileOverview` 的说明写着理由）：
    /// 这一页没有任何位置能说明"两个计数准、日历缺了几天"，而重试一次只要 **1 点**。
    /// 代价如实记在这里：**部分成功时那两个计数也一起不显示**。
    public func loadActivity() async throws -> ViewerActivityDTO {
        let response = try await client.query(Self.query, as: Response.self)
        return response.viewer
    }

    // MARK: - 查询文本

    /// ⚠️ 四处细节都不是随手写的：
    ///
    /// 1. **两个 `first: 1` 写死**（理由见类型说明）—— 它们决定这一次花几点；
    /// 2. **`affiliations` 写全三个值**（决策 #76；漏了不会报错，只是数小了一截）；
    /// 3. `contributionCalendar` 下的 `weeks` / `contributionDays` **不带 `first:`**
    ///    —— 它们是数组，写了会被服务端直接拒（§13.2 那处已修的错）；
    /// 4. `date` / `firstDay` 是 `Date` 标量、`weekday` 是 `Int!`：字段名逐个对着
    ///    `ContributionCalendarDTO` 抄，改一处就要同时改那边。
    static let query = """
    query ViewerActivity {
      viewer {
        contributionsCollection {
          contributionCalendar {
            totalContributions
            weeks {
              firstDay
              contributionDays {
                date
                contributionCount
                contributionLevel
                weekday
              }
            }
          }
        }
        starredRepositories(first: 1) {
          totalCount
        }
        repositories(first: 1, affiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER]) {
          totalCount
        }
      }
    }
    """

    // MARK: - 私有形状

    /// `viewer` 下选的字段与 `ViewerActivityDTO` **逐字相同**（三个字段、同名同层）
    /// ⇒ 直接把它当信封里的载荷解，不再造一个只为了多一层大括号的中间类型。
    struct Response: Decodable, Sendable {
        let viewer: ViewerActivityDTO
    }
}
