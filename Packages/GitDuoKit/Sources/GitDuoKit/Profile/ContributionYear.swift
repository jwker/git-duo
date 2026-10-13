import Foundation

/// 热力图上的**一年**（2026-10-09 加，用户走查第 2 条：热力图要能切年份）。
///
/// ## ⚠️ 这里的"一年"是**自然年**，不是"过去一年"
///
/// 决策 #74 落地时窗口取的是官方默认值"**一年前 → 现在**"，卡片右上那句文案
/// （原型逐字）也是「过去一年」。加年份切换之后这个口径必须换掉，理由是**滚动窗口
/// 拿不出年份标签**：一年前 → 现在跨着两个年份，"2025" 与 "2026" 都指不准它。
///
/// 所以本类型的窗口是 **1/1 → 12/31**（当前年**截至今天**）：
///
/// | 选项 | 窗口 |
/// |---|---|
/// | 2026（当前年） | 2026-01-01 → **今天** |
/// | 2025 | 2025-01-01 → 2025-12-31 23:59:59 |
/// | 2024 | 同上 |
///
/// ⚠️ **代价如实登记**：当前年那个数**比旧的「过去一年」少**（少的是去年 10–12 月那一段），
/// 这是"有年份标签"必须付的代价 —— 已写进 `REVIEW-CHECKLIST` 偏差第 44 条与 `PRD §4.17`。
///
/// ## ⚠️⚠️ 「跨度不超过一年」—— 而**"一年"不是 365 天**
///
/// 官方 schema 对这两个参数的原文是：`from` 省略 ⇒ 默认 "**a year ago**"；
/// `to` 省略 ⇒ 默认 "the current time or **one year from the provided `from` argument**"。
/// 它说的是**日历**意义的"一年"（`from` 加一年），不是一个固定的秒数。
///
/// 自然年天然满足，**而闰年是这两个口径唯一分岔的地方**：2024 整年的窗口
/// （1/1 0 点 → 12/31 23:59:59）是 **366 天减 1 秒**。
/// ⇒ 若哪天有人把这条上限实现成"≤ 31,536,000 秒"（365 天），表现会是
/// **"2024 那一年的热力图永远切不过去"**，而错误只会说贡献数据取不到
/// （`ContributionGridTests.windowsNeverExceedOneYear` 按日历断言，就是为了钉住这一点）。
///
/// ⚠️ **残留不确定（如实登记）**：这条上限**在闰年上没在真机验过**，而 2024
/// 正是本期三个选项之一 ⇒ 它是**现在就在走的路径**。若真被服务端拒，
/// 改法是"往年的窗口掐到 365 天"，代价是闰年的 12/31 会缺一天。
/// 走查单 #123 已把这个症状的排查线索写下来（先怀疑这条，别先怀疑数据层）。
public struct ContributionYear: Sendable, Hashable, Identifiable {

    /// 四位年份。**它同时是 `Identifiable` 与菜单的 `tag`**。
    public let year: Int

    public var id: Int { year }

    /// 屏幕上那几个字（`2026 年`）—— 文案归 `ProfileCopy`，这里只做转发，
    /// 免得"菜单标题"与"a11y 标签"两处各拼一遍。
    public var label: String { ProfileCopy.yearLabel(year) }

    /// 该年日子的**字符串前缀**（`"2026-"`）—— 把服务端给的 `yyyy-MM-dd` 裁到这一年
    /// （2026-10-12 加，用户走查**第 60 条**）。
    ///
    /// ## 它治什么
    ///
    /// 服务端**按周**返回 `contributionDays`，而本类型的窗口起点是"1/1 零点"按**本机日历**
    /// 算的、再由数据层按 **GMT** 序列化（`GitHubViewerActivityEndpoint.dateTime`）
    /// ⇒ 对 UTC 东侧来说那串落到**上一年 12/31**（东八区：`2025-12-31T16:00:00Z`）。
    /// 服务端若按它自己的口径切日，首周就会带回一个**不属于这一年**的日子。
    ///
    /// 那个日子会把月份表头带歪：`ContributionGrid.monthLabels` 的规则是"每个月挂在
    /// **它第一次出现的那一列**"，于是第 0 列挂「12月」、第 1 列挂「1月」，而两列只差
    /// **13.5pt**（`ContributionHeatmap` 的 `step = 11 + 2.5`）而「12月」约 **23pt**
    /// ⇒ **两个字叠在一起**（用户就是这么发现的：*12月和1月的坐标值贴在一起*）。
    ///
    /// ## ⚠️ 为什么是"按年份前缀裁"而不是"把窗口起点摆到 UTC 日历"
    ///
    /// 因为**后者要先坐实"服务端到底按哪个时区切日"**，而那件事在本机验不了
    /// （令牌在 Keychain 里、`gh` 未授权，而匿名的 `/users/{u}/contributions` 只认年份粒度、
    /// 会忽略 `from`/`to` 的细粒度 ⇒ 问不出边界落在哪一天）。
    /// 按前缀裁**不依赖那个判断**：无论服务端怎么切，网格里只剩这一年的日子，表头自然是 1…12。
    /// 代价如实登记在走查第 60 条：服务端的 `totalContributions` 仍可能含着那个跨年的日子。
    ///
    /// ## ⚠️ 必须**零填充**（`%04d`）
    ///
    /// 服务端那串是零填充的四位年（`yyyy-MM-dd`），前缀必须逐字对得上 ——
    /// 写成 `"\(year)-"` 的话 999 年那种会得到 `"999-"`、**永远匹配不上**，
    /// 而症状是"某一年的热力图整张是空的"，看起来像数据没取到。
    public var datePrefix: String { String(format: "%04d-", year) }

    public init(year: Int) {
        self.year = year
    }
}

/// 年份选项与窗口计算 —— **全部是纯函数**，`now` 与 `calendar` 都注入。
///
/// ## 为什么 `now` 与 `calendar` 要注入
///
/// 两个理由，都不是洁癖：
/// 1. **可测**：窗口计算是本片唯一的日期算法，"当前年截至今天"这条规则错了的表现是
///    "总数少了一截"，而它**看起来完全正常** —— 必须能拿固定时刻断言（App target
///    没有测试 target，决策 #34）；
/// 2. **可解释**：时区/日历（农历关掉与否、周起始日）由本机决定，注入之后
///    "这一次算的是谁的年"在调用点一眼可见。
///
/// ⚠️ **`calendar` 必须带上时区**（`Calendar.current` 自带）：用 `Calendar(identifier:)`
/// 裸建一个会让 `date(from: DateComponents(year: 2026, month: 1, day: 1))` 落到 GMT，
/// 于是东八区的用户会看到"1 月 1 日那天的贡献跑到 2025 那一列去了"。
public struct ContributionYearBoard: Sendable {

    /// 可切换的年份个数 —— **当前年 + 前 2 年**（2026-10-09 用户拍板：共 3 档）。
    ///
    /// ⚠️ 写成一个常量而不是把三个年份摆在调用点：多一档少一档是**一句话的事**，
    /// 而摆开写会散进视图、`LoadProfileOverview` 与测试三处。
    public static let selectableCount = 3

    private let now: @Sendable () -> Date
    private let calendar: Calendar

    public init(
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.now = now
        self.calendar = calendar
    }

    /// 可选的年份，**从当前年往前排**（菜单顺序 = 数组顺序）。
    ///
    /// 当前年**永远在第一位**：它不是"某一年"，而是"我现在这一年"，
    /// 菜单第一项就是它能让"我想看回默认那一年"永远只有一次点击。
    public var years: [ContributionYear] {
        let current = calendar.component(.year, from: now())
        return (0..<Self.selectableCount).map { ContributionYear(year: current - $0) }
    }

    /// 当前年（`years.first`）—— 进页默认看的那一年。
    public var current: ContributionYear { years[0] }

    /// 某一年的窗口。
    ///
    /// - 起点：该年 1 月 1 日 **0 点**（本机日历）；
    /// - 终点：该年 12 月 31 日 **23:59:59**，但**当前年截至"现在"**。
    ///
    /// ⚠️ 终点用 `min(年末, now)` 而不是直接给年末：给年末会让当前年多算"今天之后
    /// 那一天还没发生的贡献"（实际返回 0，但窗口的含义就不对了 —— 窗口是**我们声称
    /// 覆盖的区间**，而卡片右上写着年份）。
    ///
    /// ⚠️ 兜底：起点算不出来（畸形日历）时退化成"整年 = 现在这一刻"，
    /// 而不是崩掉或返回一个 0 长度的区间 —— 调用方拿到的是一个**一定能用**的窗口。
    ///
    /// ⚠️ **这里只管"请求哪个区间"，管不到"服务端实际回了哪几天"**：上面那条"起点按本机
    /// 日历算"会让东八区请求到的 `from` 落在**上一年 12/31**（`16:00:00Z`），而服务端按周
    /// 返回、不补周 ⇒ 首周就可能带回那个日子。**它由映射层按年份前缀裁掉**
    /// （`ContributionYear.datePrefix`、`ProfileMapper.grid(_:year:)`，走查第 60 条），
    /// 不在这里改 —— 那要先坐实服务端按哪个时区切日，而按前缀裁不依赖那个判断。
    public func interval(of year: ContributionYear) -> DateInterval {
        let instant = now()
        guard let start = calendar.date(from: DateComponents(year: year.year, month: 1, day: 1)),
              let yearEnd = calendar.date(
                  from: DateComponents(year: year.year, month: 12, day: 31, hour: 23, minute: 59, second: 59)
              )
        else { return DateInterval(start: instant, end: instant) }

        // `max(start, …)` 兜住"时钟被调到过去"这种情形：终点不许早于起点（负长度区间
        // 会让服务端直接拒），而那种情形下"看这一年的第一天"是唯一说得通的答案。
        let end = max(start, min(yearEnd, instant))
        return DateInterval(start: start, end: end)
    }
}
