import Foundation
import GitHubAPI

/// 「我的」页那两路数据的形状翻译（TECH_SPEC §6.1 / §9.14）。
///
/// ## 为什么要有这一层
///
/// 与 `RepositoryMapper` / `RepoSummaryMapper` 同源：DTO 是**服务端的形状**，
/// 领域模型是**产品的语义**。这里集中了三条只有本层才知道的规则：
///
/// 1. **热力图的排布**（哪一天在第几列第几行）—— 见 `grid(_:)`；
/// 2. **档位翻译**（`contributionLevel` 的字符串 → 0…4）—— 见 `ContributionLevel`；
/// 3. **三个统计项各自有没有值** —— 见 `stats(activity:followers:)`。
///
/// 三条都**不是**纯转发，所以都不能就近写在视图里（App target 没有测试 target）。
public struct ProfileMapper: Sendable {

    public init() {}

    // MARK: - 资料头部

    /// ## 头像地址为什么要在这里"翻译"一次
    ///
    /// DTO 收的是**原样字符串**（`ViewerProfileDTO` 的说明讲了为什么 —— 同一份响应里
    /// GitHub 真的会发空串，而空串对 `URL` 解码是会抛错的）。这里把它变成 `URL?`：
    /// `nil`（字段缺席 / 值是 `null`）与空串**都落到同一个 `nil`**，
    /// 视图那边于是只有一条路可走（首字母块）。
    ///
    /// ⚠️ 这一步是**纯函数**（`URL(string:)` 与 `trimming` 都不碰网络），
    /// 所以它必须在领域层、必须可单测 —— 放在 App 层的视图里就再也测不到
    /// （App target 没有测试 target，决策 #34）。
    public func profile(_ dto: ViewerProfileDTO) -> ViewerProfile {
        ViewerProfile(
            login: dto.login,
            name: dto.name,
            bio: dto.bio,
            avatarURL: dto.avatarURL.flatMap(Self.avatarURL(from:))
        )
    }

    /// 头像字符串 → `URL`。空白串当成"没有"。
    ///
    /// `avatars.githubusercontent.com` 的地址不含空格，所以 `trimming` 之后为空
    /// 只可能是"服务端给了个空串"这一种情形（`gravatar_id` 就是这么发的）。
    /// ⚠️ **不补 `?s=<size>`**：§5.3 那条降采样规则三处消费点都还没做，属独立的整理
    /// （`TECH_SPEC §5.3` 已登记为欠账）—— 在这里单方面补上会让同一个头像在
    /// 三处走两种 URL。
    static func avatarURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : URL(string: trimmed)
    }

    // MARK: - 热力图

    /// `contributionCalendar` → 铺好的网格。
    ///
    /// ## ⚠️ 排布只有一处难点：**第一天在第几行**
    ///
    /// 日历的周是**周日对齐**的，而"过去一年"这个窗口不会正好从周日开始
    /// ⇒ 第一列前面要空出几格。空几格 = 第一天的行号，而它只能从服务端给的
    /// `weekday` 算出来。
    ///
    /// ## 为什么要绕一圈用"相对差"，而不是直接信 `weekday` 的编号约定
    ///
    /// 官方对 `weekday` 的注释只举了一个例子（*"e.g., 1 is Monday"*），
    /// 没有明写它的取值区间是 `0...6` 还是 `1...7`。猜错的后果是**整张图上下错一位**
    /// —— 而错位的热力图看起来完全正常，只是每一天都不在它该在的位置（最难自查的一类错）。
    ///
    /// 所以这里**算相对量**：找一个"满 7 天"的周，它的第一天必然是周起点；
    /// 第一天的行号 = `(第一天的 weekday − 那个周起点的 weekday) mod 7`。
    /// 无论服务端用什么编号约定，这个差都成立。
    public func grid(_ dto: ViewerActivityDTO) -> ContributionGrid {
        let calendar = dto.contributionsCollection.contributionCalendar
        let rawDays = calendar.weeks.flatMap(\.contributionDays)

        let days = rawDays.map { day in
            ContributionDay(
                date: day.date,
                count: day.contributionCount,
                // 档位照抄服务端的 `contributionLevel`（**不按次数自己划**，见 `ContributionLevel`）。
                level: ContributionLevel.translate(
                    rawValue: day.contributionLevel,
                    contributionCount: day.contributionCount
                )
            )
        }

        return ContributionGrid(
            columns: ContributionGrid.layout(
                days: days,
                firstRow: Self.firstRow(in: calendar.weeks, firstDay: rawDays.first)
            ),
            totalContributions: calendar.totalContributions,
            days: days
        )
    }

    /// 第一天落在第几行（`0` = 首行）。见 `grid(_:)` 的说明。
    ///
    /// 找不到"满 7 天的周"时回落成 `0`（= 假定第一列从周起点开始）。
    /// 这个分支在真实数据上到不了 —— 一年的窗口有 52 个以上满周；
    /// 留它只是为了不靠"数据一定完整"来保证不崩。
    static func firstRow(
        in weeks: [ContributionCalendarWeekDTO],
        firstDay: ContributionCalendarDayDTO?
    ) -> Int {
        guard let firstDay,
              let fullWeek = weeks.first(where: {
                  $0.contributionDays.count == ContributionGrid.rowCount
              }),
              let weekStart = fullWeek.contributionDays.first
        else { return 0 }

        let offset = firstDay.weekday - weekStart.weekday
        let rows = ContributionGrid.rowCount
        return ((offset % rows) + rows) % rows
    }

    // MARK: - 三个统计项

    /// 三个数各自有没有值。
    ///
    /// - Parameters:
    ///   - activity: GraphQL 那一路；`nil` = 没拿到 ⇒ 仓库与 Star 两个数都没有。
    ///   - followers: `GET /user` 那一路的关注者数；`nil` = 没拿到。
    ///
    /// ## 为什么两个来源要分开传
    ///
    /// 因为它们**真的会各自失败**（REST 与 GraphQL 是两个端点、两个配额桶）。
    /// 合成一个"整页成功 / 失败"的开关，表现就是"热力图取不到 ⇒ 连带 Follower 也不显示"，
    /// 而 Follower 其实就在手里。分开传之后，"哪一项缺席"这件事在类型上写清楚了
    /// （`ProfileStats` 三个 Optional），视图不必猜。
    public func stats(activity: ViewerActivityDTO?, followers: Int?) -> ProfileStats {
        ProfileStats(
            repositories: activity?.repositories.totalCount,
            stars: activity?.starredRepositories.totalCount,
            followers: followers
        )
    }
}
