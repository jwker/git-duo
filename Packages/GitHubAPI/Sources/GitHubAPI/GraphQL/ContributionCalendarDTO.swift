import Foundation

/// 贡献热力图的日历 —— `GitHub GraphQL` 的 `viewer.contributionsCollection.contributionCalendar`
/// （TECH_SPEC §9.14、§4.6.5、决策 #74）。
///
/// ## ⚠️ 本类型为什么在切片 9.1 就存在（数据层是 9.2）
///
/// 与切片 8 的 `FileWriteResultDTO` 同一处置：领域层的**映射规则**要拿它当输入，
/// 而映射规则必须进单测（App target 没有测试 target）⇒ DTO 随领域层一起立，
/// 端点（真正发 GraphQL 查询的那一层）落在 9.2。
///
/// ## ⚠️⚠️ `weeks` 与 `contributionDays` **都是数组，不是连接**
///
/// 官方 schema 原文（`docs.github.com/public/fpt/schema.docs.graphql`）：
///
/// ```graphql
/// type ContributionCalendar {
///   totalContributions: Int!
///   weeks: [ContributionCalendarWeek!]!
/// }
/// type ContributionCalendarWeek {
///   contributionDays: [ContributionCalendarDay!]!
///   firstDay: Date!
/// }
/// ```
///
/// `[X!]!` 是**数组**、`XConnection!` 才是**连接** —— 数组字段**不接受 `first:` 参数**，
/// 写了会被服务端直接拒。`TECH_SPEC §13.2` 原写 `weeks(first:53)` 就是这个错，
/// 2026-10-09 已修正（决策 #74①）。判据：**写查询前先看它是 `[X!]!` 还是 `XConnection!`**。
///
/// 附带的好消息：数组**不贡献 GraphQL 请求数** ⇒ 热力图这一路一个点都不花，
/// 那 1 点的来源是同一次查询里的两个计数连接（决策 #76）。
public struct ContributionCalendarDTO: Sendable, Equatable, Decodable {

    /// 一年内的贡献总数。**它才是屏幕上 `{N} 次贡献` 的那个数** ——
    /// 不要拿格子里的 `contributionCount` 自己加：那样得到的数会随"取回了多少格"而变，
    /// 而这两者本该是同一件事（服务端已经算好了）。
    public let totalContributions: Int

    /// 各周，**顺序即列顺序**（日历是周日开头的一列）。
    public let weeks: [ContributionCalendarWeekDTO]

    public init(totalContributions: Int, weeks: [ContributionCalendarWeekDTO]) {
        self.totalContributions = totalContributions
        self.weeks = weeks
    }
}

/// 日历的一周。
///
/// ⚠️ **头尾两周可能不足 7 天**：GitHub 的日历周是**周日对齐**的，而一年这个窗口
/// 不会正好从周日开始 / 到周六结束 ⇒ 第一周与最后一周的 `contributionDays`
/// 可能只有几天。**不能按"每周 7 格"去铺网格**，否则整张图会错位
/// （见 `ContributionGridMapper` 的口径）。
public struct ContributionCalendarWeekDTO: Sendable, Equatable, Decodable {

    public let contributionDays: [ContributionCalendarDayDTO]

    /// 这一周最早的那一格（`Date` 标量，形如 `2026-01-04`）。
    ///
    /// 取它是为了在映射时**找一个"满 7 天"的周当基准**：那种周的第一格必然是周日。
    /// 有了这个基准，"某一天在第几行"就可以用**相对差**算出来，不必猜
    /// `weekday` 用的是什么编号约定（见 `ContributionDayDTO.weekday`）。
    public let firstDay: String

    public init(contributionDays: [ContributionCalendarDayDTO], firstDay: String) {
        self.contributionDays = contributionDays
        self.firstDay = firstDay
    }
}

/// 日历的一格（一天）。
public struct ContributionCalendarDayDTO: Sendable, Equatable, Decodable {

    /// 那一天（`Date` 标量）。**原样保留字符串**，不转 `Date`。
    ///
    /// ⚠️ 这个值**不带时区**（`Date` 标量序列化成 `yyyy-MM-dd`）。把它转成 `Date`
    /// 就必须**替服务端选一个时区**，而选错会让某些时区下整体偏移一天 ——
    /// 那正是热力图最难自查的一类错（图看着很正常，只是每一天都错位）。
    /// 界面当前不需要"某一天是哪天"，所以没必要承担这个风险。
    public let date: String

    /// 这一天有多少次贡献。
    public let contributionCount: Int

    /// 服务端算好的**档位**（`NONE` / `FIRST_QUARTILE` / `SECOND_QUARTILE` /
    /// `THIRD_QUARTILE` / `FOURTH_QUARTILE`，正好 5 档）。
    ///
    /// ⚠️ **照抄这个，不要自己按 `contributionCount` 划档**（决策 #74②）：
    /// 官方 schema 对它的注释是 *"Indication of contributions, relative to other days"*
    /// —— 它是**相对这位用户自己这一年的分布**算出来的四分位，
    /// 同一个 `contributionCount` 在两个人身上可以是不同档，我们复现不出来。
    ///
    /// 声明成 `String` 而不是 Swift 枚举（同 `IssueDTO.state` 的判据）：
    /// 这是个仍在演进的取值集合，枚举化之后 GitHub 哪天多一档，
    /// 表现就是**整张卡片解码失败**。认不出的取值由映射层兜底（见 `ContributionLevel`）。
    public let contributionLevel: String

    /// 这一天是一周里的第几天。
    ///
    /// 官方注释：*"A number representing which day of the week this square represents,
    /// e.g., 1 is Monday."* ⇒ **1 是周一**（也就是 0 = 周日）。
    ///
    /// ⚠️ 但本包**不依赖这个约定**：布局只用到"某一天相对某个满 7 天的周的第一格差几格"，
    /// 那是**相对量**，换一套编号约定照样成立（见 `ContributionGridMapper`）。
    /// 记这一句是为了让下一个人不必再对着文档猜一遍。
    public let weekday: Int

    public init(date: String, contributionCount: Int, contributionLevel: String, weekday: Int) {
        self.date = date
        self.contributionCount = contributionCount
        self.contributionLevel = contributionLevel
        self.weekday = weekday
    }
}
