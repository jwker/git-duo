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
    /// - Parameters:
    ///   - from: 窗口起点（含）。领域层按**本机日历**算出来（`ContributionYear.interval`）。
    ///   - to: 窗口终点（含）。
    /// - Throws: `GitHubError.graphQLErrors(messages:partialData:)`（**HTTP 200 也可能是失败**）、
    ///   `GitHubError.decoding`（形状完全不符），以及 transport 归一化出的网络 / 状态码错误。
    ///
    /// ## ⚠️ 2026-10-09：`from` / `to` 从"省略"变成"必填"
    ///
    /// 省略时官方默认给的是"**一年前 → 现在**"（那条口径写在 `ContributionGrid` 与
    /// `TECH_SPEC §9.14` 里，是决策 #74 的依据）。加年份切换之后窗口必须**显式给**
    /// —— 否则"切到 2025 年"就没有任何参数能表达。
    ///
    /// ⚠️ 官方对这个窗口有一条硬约束：**跨度不超过一年**（自然年天然满足，当前年更短）。
    /// 超了服务端会报 `errors`（HTTP 200 + body 里报错 ⇒ 归到 `.graphQLErrors`）。
    /// ⚠️ 而**"一年"是日历意义的**（`to` 省略时官方默认 = `from` 加一年）——
    /// **闰年整年是 366 天减 1 秒**，按"≤ 365 天"去判会误杀 2024 那一年。
    /// 这条口径的完整来龙去脉记在 `ContributionYear` 的抬头。
    ///
    /// ⚠️ **加变量不增加点数**：这一次的请求数仍是 2（两个 `first: 1` 的计数连接），
    /// 按"最小 1 点"计 ⇒ 切换一次年份 = **1 点**（切换成本与进页同价）。
    ///
    /// ## ⚠️ 部分成功时**整块抛错**，不打捞那份 `partialData`
    ///
    /// `GitHubGraphQLClient` 刻意把"`data` + `errors` 并存"抛成一个带 `partialData` 的错误，
    /// 好让调用方自己决定。这里的选择是**不打捞**（`LoadProfileOverview` 的说明写着理由）：
    /// 这一页没有任何位置能说明"两个计数准、日历缺了几天"，而重试一次只要 **1 点**。
    /// 代价如实记在这里：**部分成功时那两个计数也一起不显示**。
    public func loadActivity(from: Date, to: Date) async throws -> ViewerActivityDTO {
        let response = try await client.query(
            Self.query,
            variables: Variables(
                from: Self.dateTime(from),
                to: Self.dateTime(to)
            ),
            as: Response.self
        )
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
    ///
    /// ⚠️ **`$from` / `$to` 只出现在 `contributionsCollection` 一处**：两个计数的
    /// `first:` **仍然写死在文本里**（第 1 条），别把"加变量"理解成"以后什么都能进变量"。
    static let query = """
    query ViewerActivity($from: DateTime!, $to: DateTime!) {
      viewer {
        contributionsCollection(from: $from, to: $to) {
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

    /// 变量形状 —— **带类型的结构体**而不是 `[String: Any]`：
    /// 变量名写错会在**编译期**报出来，而不是运行时被服务端拒
    /// （`GitHubGraphQLClient.query` 的说明点名了这条）。
    struct Variables: Encodable, Sendable {
        let from: String
        let to: String
    }

    /// `Date` → GraphQL `DateTime!` 的线上形状：ISO-8601、**带时区**（`2026-01-01T00:00:00Z`）。
    ///
    /// ⚠️ 固定按 **GMT** 序列化。领域层是按**本机日历**算出的那两个瞬间
    /// （"当地 1 月 1 日 0 点"），把它序列化成 UTC 只是换个写法、不改变时刻；
    /// 反而是"按本机时区写带偏移量的字符串"会让同一个瞬间有 24 种写法，
    /// 排查时对着两行日志要自己换算（官方 `DateTime` 两种都收）。
    ///
    /// ## ⚠️ 顺带一条外部证据：**时区不会让日子错位**（2026-10-09 查得）
    ///
    /// 第三方项目的实测记录（`octomation/maintainer` issue #457）称：把**同一个窗口**
    /// 按 `Z` / `+03:00` / `-07:00` 三种写法发出去，返回的 `date` **完全一样**
    /// ⇒ "按 GMT 写"**不会**让某些天的贡献整体偏一天（那本来是这里最该担心的事）。
    ///
    /// ⚠️ 但它是**别人报的实测、不是官方承诺** ⇒ 上面那个理由（同一个瞬间只有一种写法）
    /// 仍然是这个决定的正式依据，别把这条升级成"官方保证了时区无关"。
    static func dateTime(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .gmt))
    }

    // MARK: - 私有形状

    /// `viewer` 下选的字段与 `ViewerActivityDTO` **逐字相同**（三个字段、同名同层）
    /// ⇒ 直接把它当信封里的载荷解，不再造一个只为了多一层大括号的中间类型。
    struct Response: Decodable, Sendable {
        let viewer: ViewerActivityDTO
    }
}
