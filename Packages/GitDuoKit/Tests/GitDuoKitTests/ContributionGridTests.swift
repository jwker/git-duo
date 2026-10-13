import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 热力图的**深浅档**（TECH_SPEC §9.14、决策 #74②）。
///
/// ## 这一套守的是什么
///
/// 官方 schema 对 `contributionLevel` 的注释是 *"… **relative to other days**"* ——
/// 它是**相对这位用户自己这一年的分布**算出来的四分位。我们复现不出那个分布，
/// 自己按 `contributionCount` 划档只能得到一张**形状不对**的图
/// （而形状不对的热力图看起来也挺正常，只是"这一年好像挺闲"）。
@Suite("热力图 · 档位翻译（照抄服务端，不自己划）")
struct ContributionLevelTests {

    @Test("五个合法取值各翻各的（`NONE` + 四个四分位）")
    func translatesEveryLegalValue() {
        let cases: [(String, ContributionLevel)] = [
            ("NONE", .none),
            ("FIRST_QUARTILE", .firstQuartile),
            ("SECOND_QUARTILE", .secondQuartile),
            ("THIRD_QUARTILE", .thirdQuartile),
            ("FOURTH_QUARTILE", .fourthQuartile),
        ]

        for (raw, expected) in cases {
            #expect(
                ContributionLevel.translate(rawValue: raw, contributionCount: 7) == expected,
                "每一个合法取值都应翻译成对应的档"
            )
        }
    }

    @Test("⚠️ 同一个 `contributionCount` 可以是两档 —— 档位由服务端给，不是由次数算")
    func sameCountCanBeTwoDifferentLevels() {
        // 这一天贡献了 1 次：在一年只有 20 次的人那里是最高档，在天天 50 次的人那里是最低档。
        // 如果哪天有人"顺手"把 translate 改成按 count 划档，这两条会当场变成同一个值。
        #expect(
            ContributionLevel.translate(rawValue: "FOURTH_QUARTILE", contributionCount: 1)
                == .fourthQuartile
        )
        #expect(ContributionLevel.translate(rawValue: "NONE", contributionCount: 1) == .none)
    }

    @Test("⚠️ 认不出的取值按「**有没有贡献**」兜底，而不是一律当成无贡献")
    func unknownValueFallsBackByContribution() {
        // GitHub 哪天多一档 ⇒ 一律当 `.none` 会让那些**确实有贡献**的日子变成空白，
        // 于是"这张图少了东西"看不出是数据问题还是本来就这样。选另一侧：
        #expect(
            ContributionLevel.translate(rawValue: "FIFTH_QUARTILE", contributionCount: 3)
                == .firstQuartile
        )
        #expect(
            ContributionLevel.translate(rawValue: "FIFTH_QUARTILE", contributionCount: 0)
                == .none
        )
        // 空串（服务端给了一个空值）走同一条兜底。
        #expect(ContributionLevel.translate(rawValue: "", contributionCount: 1) == .firstQuartile)
    }

    @Test("`scale` 是从浅到深的 0…4，且 `scaleCount` 与取值个数**一致**")
    func scaleIsOrderedAndComplete() {
        // 设计层的色板按同一个顺序取色。两处各写一套"哪个 case 是第几档"
        // 必然有一天分叉（表现为"最深的那档画成了浅色"）。
        #expect(ContributionLevel.allCases.map(\.scale) == [0, 1, 2, 3, 4])
        #expect(ContributionLevel.scaleCount == ContributionLevel.allCases.count)
    }

    @Test("`rawValue` 就是服务端那串字面量（大小写不能变）")
    func rawValuesMatchTheServer() {
        #expect(ContributionLevel.none.rawValue == "NONE")
        #expect(ContributionLevel.fourthQuartile.rawValue == "FOURTH_QUARTILE")
    }
}

/// 网格的铺法（TECH_SPEC §9.14、决策 #74③）。
///
/// ## 坐标：**列 = 周、行 = 一周里的第几天**
///
/// `columns[c][r]`；`nil` = 补位（那格里没有日子）。这一套守的是三类
/// **看起来完全正常**的错：整张图上下错一位（按 `weekday` 直接编号去铺）、
/// 右边缘多一条空白列（铺满整列时多出来一个尾列）、第一列前面该空几格空错了。
@Suite("热力图 · 网格铺法（7 行 × N 列）")
struct ContributionGridLayoutTests {

    private func day(_ index: Int, level: ContributionLevel = .none) -> ContributionDay {
        ContributionDay(date: "d\(index)", count: 0, level: level)
    }

    @Test("一格日子都没有 ⇒ 零列（**不是**一张全空位的图）")
    func emptyDaysYieldNoColumns() {
        let columns = ContributionGrid.layout(days: [], firstRow: 3)

        #expect(columns.isEmpty)
    }

    @Test("恰好 7 天、从首行起 ⇒ **一列**，且末尾那个空列会被去掉")
    func exactlyOneWeekYieldsOneColumn() {
        let columns = ContributionGrid.layout(days: (0..<7).map { day($0) }, firstRow: 0)

        #expect(columns.count == 1)
        #expect(columns[0].count == 7)
        #expect(columns[0].compactMap { $0 }.map(\.date) == (0..<7).map { "d\($0)" })
    }

    @Test("恰好 14 天 ⇒ 两列（去掉尾列这件事不能把**有内容**的那列也去掉）")
    func exactlyTwoWeeksYieldTwoColumns() {
        let columns = ContributionGrid.layout(days: (0..<14).map { day($0) }, firstRow: 0)

        #expect(columns.count == 2)
        #expect(columns[1].compactMap { $0 }.map(\.date) == (7..<14).map { "d\($0)" })
    }

    @Test("8 天 ⇒ 两列：第二列只有第 0 行有日子，其余是补位")
    func eightDaysSpillIntoASecondColumn() {
        let columns = ContributionGrid.layout(days: (0..<8).map { day($0) }, firstRow: 0)

        #expect(columns.count == 2)
        #expect(columns[1][0]?.date == "d7")
        #expect(columns[1].dropFirst().allSatisfy { $0 == nil })
    }

    @Test("⚠️ 第一天不在首行 ⇒ 第一列**前面**空出恰好那么多格（这就是「补位」的全部意义）")
    func leadingSlotsArePadded() {
        let columns = ContributionGrid.layout(days: (0..<4).map { day($0) }, firstRow: 3)

        #expect(columns.count == 1)
        #expect(columns[0][0] == nil)
        #expect(columns[0][1] == nil)
        #expect(columns[0][2] == nil)
        #expect(columns[0][3]?.date == "d0")
        #expect(columns[0][6]?.date == "d3")
    }

    @Test("`firstRow` 越界被夹进 0…6（不崩、也不写出一个越界的下标）")
    func firstRowIsClamped() {
        let negative = ContributionGrid.layout(days: (0..<2).map { day($0) }, firstRow: -5)
        #expect(negative[0][0]?.date == "d0")

        let overflow = ContributionGrid.layout(days: (0..<2).map { day($0) }, firstRow: 99)
        // 夹到最后一格：第一天落在第 6 行，第二天只能换列（而不是越界写崩）。
        #expect(overflow[0][6]?.date == "d0")
        #expect(overflow[1][0]?.date == "d1")
    }

    @Test("每一列恒有 7 个格子（少一格会让整张图**从那一列起**整体错位）")
    func everyColumnHasSevenSlots() {
        let columns = ContributionGrid.layout(days: (0..<100).map { day($0) }, firstRow: 5)

        #expect(columns.allSatisfy { $0.count == 7 })
    }

    @Test("`levelMatrix` 是给设计层的纯整数矩阵：补位是 `nil`、档位是 0…4")
    func levelMatrixMirrorsTheColumns() {
        let days = [
            day(0, level: .none),
            day(1, level: .fourthQuartile),
            day(2, level: .firstQuartile),
        ]
        let grid = ContributionGrid(
            columns: ContributionGrid.layout(days: days, firstRow: 6),
            totalContributions: 0,
            days: days
        )

        // 第一列：前 6 格补位、最后一格是 `none`(0)；第二列前两格是 4 与 1。
        #expect(grid.levelMatrix[0] == [nil, nil, nil, nil, nil, nil, 0])
        #expect(grid.levelMatrix[1] == [4, 1, nil, nil, nil, nil, nil])
    }

    @Test("`columnCount` / `dayCount` / `isEmpty` 三个派生值口径一致")
    func derivedCountsAgree() {
        let days = (0..<10).map { day($0) }
        let grid = ContributionGrid(
            columns: ContributionGrid.layout(days: days, firstRow: 2),
            totalContributions: 123,
            days: days
        )

        // (2 + 10) / 7 = 1.71… ⇒ 2 列。
        #expect(grid.columnCount == 2)
        #expect(grid.dayCount == 10)
        #expect(!grid.isEmpty)
        #expect(grid.columns.flatMap { $0 }.compactMap { $0 }.count == 10)
    }

    @Test("⚠️ `isEmpty` 说的是「一格日子都没有」，**不是**「零贡献」")
    func isEmptyIsNotZeroContribution() {
        // 零贡献的一年有 365 个格子，只是都最浅 —— PRD §4.17 明写这种情形照常画图、不给空态。
        let days = (0..<365).map { day($0, level: .none) }
        let grid = ContributionGrid(
            columns: ContributionGrid.layout(days: days, firstRow: 4),
            totalContributions: 0,
            days: days
        )

        #expect(grid.totalContributions == 0)
        #expect(!grid.isEmpty)
        #expect(grid.dayCount == 365)
    }
}

/// 从 DTO 铺成网格（`ProfileMapper`，TECH_SPEC §6.1 / §9.14）。
@Suite("热力图 · DTO → 网格（`ProfileMapper`）")
struct ContributionGridMapperTests {

    /// 造一份"像真实那样"的日历：窗口从一周的中间开始（第一周是尾巴），之后全是整周。
    ///
    /// - Parameters:
    ///   - firstRow: 第一天在一周里的第几格（`0` = 周起点）。
    ///   - totalDays: 一共多少天（真实是 365 或 366）。
    ///   - total: `totalContributions`（**刻意让它与格子求和不同**，见下）。
    ///   - weekdayOffset: 全体 `weekday` 的偏移 —— 用来模拟"另一套编号约定"。
    private func calendar(
        firstRow: Int,
        totalDays: Int,
        total: Int = 0,
        weekdayOffset: Int = 0
    ) -> ViewerActivityDTO {
        let days = (0..<totalDays).map { index in
            ContributionCalendarDayDTO(
                date: String(format: "2026-%04d", index),
                contributionCount: index % 4,
                contributionLevel: index % 4 == 0 ? "NONE" : "SECOND_QUARTILE",
                weekday: (firstRow + index) % 7 + weekdayOffset
            )
        }

        var weeks: [ContributionCalendarWeekDTO] = []
        var cursor = 0
        var weekLength = 7 - firstRow
        while cursor < days.count {
            let slice = Array(days[cursor..<min(cursor + weekLength, days.count)])
            weeks.append(
                ContributionCalendarWeekDTO(
                    contributionDays: slice,
                    firstDay: slice.first?.date ?? ""
                )
            )
            cursor += weekLength
            weekLength = 7
        }

        return ViewerActivityDTO(
            contributionsCollection: .init(
                contributionCalendar: .init(totalContributions: total, weeks: weeks)
            ),
            starredRepositories: TotalCountDTO(totalCount: 0),
            repositories: TotalCountDTO(totalCount: 0)
        )
    }

    /// 本套件造的日历日期都在 `2026-` 里 ⇒ 固定取 2026 这一档
    /// （对这些数据**逐字无操作** —— 裁剪只认年份前缀，见 `ContributionYear.datePrefix`）。
    ///
    /// ⚠️ 名字不能就叫 `grid`：好几条用例是 `let grid = …`，而 Swift 会把同一声明里的
    /// 那个名字解析成**正在声明的局部变量**，于是 `let grid = grid(dto)` 编译不过。
    private func makeGrid(_ dto: ViewerActivityDTO) -> ContributionGrid {
        ProfileMapper().grid(dto, year: ContributionYear(year: 2026))
    }

    @Test("⚠️ 一整年 = **53 列 × 7 行**，前面空 4 格、后面空 2 格（坐标就是这个）")
    func fullYearIsFiftyThreeColumns() {
        let dto = calendar(firstRow: 4, totalDays: 365)
        let grid = makeGrid(dto)

        #expect(grid.columnCount == 53)
        #expect(grid.columns.allSatisfy { $0.count == 7 })
        #expect(grid.columns.flatMap { $0 }.compactMap { $0 }.count == 365)

        // 前 4 格补位（窗口不是从周起点开始的），末尾 2 格补位（最后一周不满）。
        #expect(grid.columns[0].prefix(4).allSatisfy { $0 == nil })
        #expect(grid.columns[0][4]?.date == "2026-0000")
        #expect(grid.columns[52].suffix(2).allSatisfy { $0 == nil })
    }

    @Test("⚠️ `weekday` 换一套编号约定（全体 +1）⇒ 铺出来的网格**一模一样**")
    func layoutIsInvariantToWeekdayConvention() {
        // 官方注释只举例"1 is Monday"，没写死区间是 0…6 还是 1…7。
        // 布局算的是**相对差**，所以换一套约定必须得到同一张图 ——
        // 这条断言就是"我们没有偷偷依赖某个约定"的证据。
        let first = makeGrid(calendar(firstRow: 4, totalDays: 365))
        let shifted = makeGrid(calendar(firstRow: 4, totalDays: 365, weekdayOffset: 1))
        let shiftedMore = makeGrid(
            calendar(firstRow: 4, totalDays: 365, weekdayOffset: 100)
        )

        #expect(first == shifted)
        #expect(first == shiftedMore)
    }

    @Test("⚠️ 总数用**服务端给的那个**，不是把格子加起来")
    func totalComesFromTheServer() {
        // 这里刻意给一个与格子求和毫无关系的数。自己求和的话，
        // 显示出来的数会随"这次取回了多少格"而变 —— 而这两者本该是同一件事。
        let dto = calendar(firstRow: 4, totalDays: 365, total: 9_999)
        let grid = makeGrid(dto)

        #expect(grid.totalContributions == 9_999)
        #expect(grid.dayCount == 365)
    }

    @Test("`date` 原样保留服务端那串 `yyyy-MM-dd`（不转 `Date`，也就不必替它选时区）")
    func dateIsKeptVerbatim() {
        let dto = calendar(firstRow: 0, totalDays: 7)
        let grid = makeGrid(dto)

        #expect(grid.days.map(\.date) == ["2026-0000", "2026-0001", "2026-0002", "2026-0003",
                                          "2026-0004", "2026-0005", "2026-0006"])
    }

    @Test("认不出的档位在整条链路上兜底（DTO 是 `String`，认不出不能整张卡片解码失败）")
    func unknownLevelSurvivesTheWholeChain() {
        let day = ContributionCalendarDayDTO(
            date: "2026-01-01",
            contributionCount: 2,
            contributionLevel: "FIFTH_QUARTILE",
            weekday: 0
        )
        let dto = ViewerActivityDTO(
            contributionsCollection: .init(
                contributionCalendar: .init(
                    totalContributions: 2,
                    weeks: [ContributionCalendarWeekDTO(contributionDays: [day], firstDay: day.date)]
                )
            ),
            starredRepositories: TotalCountDTO(totalCount: 0),
            repositories: TotalCountDTO(totalCount: 0)
        )

        let grid = makeGrid(dto)

        #expect(grid.days.count == 1)
        #expect(grid.days[0].level == .firstQuartile)
    }

    @Test("`weeks` 是空的 ⇒ 一张空的网格，不崩（新账号 / 服务端给了个空日历）")
    func emptyCalendarYieldsEmptyGrid() {
        let dto = ViewerActivityDTO(
            contributionsCollection: .init(
                contributionCalendar: .init(totalContributions: 0, weeks: [])
            ),
            starredRepositories: TotalCountDTO(totalCount: 0),
            repositories: TotalCountDTO(totalCount: 0)
        )

        let grid = makeGrid(dto)

        #expect(grid.isEmpty)
        #expect(grid.columnCount == 0)
        #expect(grid.totalContributions == 0)
    }

    @Test("没有「满 7 天」的周可当基准 ⇒ `firstRow` 回落 0（该分支真实数据到不了，但不靠它保证不崩）")
    func missingFullWeekFallsBackToZero() {
        let day = ContributionCalendarDayDTO(
            date: "2026-01-01",
            contributionCount: 1,
            contributionLevel: "NONE",
            weekday: 3
        )
        let week = ContributionCalendarWeekDTO(contributionDays: [day], firstDay: day.date)

        #expect(ProfileMapper.firstRow(in: [week], firstDay: day) == 0)
        #expect(ProfileMapper.firstRow(in: [], firstDay: day) == 0)
        #expect(ProfileMapper.firstRow(in: [week], firstDay: nil) == 0)
    }

    @Test("⚠️ 基准周的第一个日子就是周起点 —— `firstRow` 是**相对差**")
    func firstRowUsesTheGapToTheFullWeek() {
        // 一个满 7 天的周：它的第一个日子必然是周起点（`weekday` = 6）。
        let full = (0..<7).map { index in
            ContributionCalendarDayDTO(
                date: "full-\(index)", contributionCount: 0,
                contributionLevel: "NONE", weekday: 6 + index
            )
        }
        let firstDay = ContributionCalendarDayDTO(
            date: "partial-0", contributionCount: 0,
            contributionLevel: "NONE", weekday: 2
        )
        let weeks = [
            ContributionCalendarWeekDTO(contributionDays: [firstDay], firstDay: firstDay.date),
            ContributionCalendarWeekDTO(contributionDays: full, firstDay: full[0].date),
        ]

        // 2 − 6 = −4 ⇒ ((−4) mod 7 + 7) mod 7 = 3。
        #expect(ProfileMapper.firstRow(in: weeks, firstDay: firstDay) == 3)
    }
}

// MARK: - 年份与窗口（2026-10-09 加，用户走查第 2 条）

/// 热力图的**年份选项与窗口**（`ContributionYearBoard`、偏差第 44 条）。
///
/// ## 这一套守的是什么
///
/// 两处"看起来完全正常"的错：
///
/// 1. **窗口多算或少算一段** —— 当前年若取到 12/31，窗口就**声称**覆盖了还没发生的日子
///    （返回值照样是 0，所以看不出）；若上一年的窗口漏掉 12 月 31 日那几个小时，
///    那一天最深的那格会凭空消失；
/// 2. **跨度超过一年** —— 官方对 `contributionsCollection(from:to:)` 的硬约束。
///    超了不是 HTTP 4xx，而是 **200 + `errors`**（归到 `.graphQLErrors`），
///    排查时很容易误以为是"热力图数据坏了"。
///
/// ⚠️ `now` 与 `calendar` 都钉死（文件头那两个字面量的说明）：日期算术挂真时间
/// 必然在元旦/跨年那一刻偶发变红。
@Suite("热力图 · 年份选项与窗口（`ContributionYearBoard`）")
struct ContributionYearTests {

    private var board: ContributionYearBoard {
        ContributionYearBoard(now: { frozenNow }, calendar: frozenCalendar)
    }

    @Test("可切换的年份：**当前年 + 前 2 年**，当前年在第一位（用户 2026-10-09 拍板）")
    func yearsStartFromTheCurrentOne() {
        #expect(board.years.map(\.year) == [2026, 2025, 2024])
        #expect(ContributionYearBoard.selectableCount == 3)
        // 当前年不是"某一年"，而是"我现在这一年"—— 摆在第一项才能让"看回默认那一年"
        // 永远只有一次点击（`ContributionYearBoard.years` 的说明）。
        #expect(board.current == board.years[0])
    }

    @Test("每个选项自己带着屏幕上那几个字，文案**取自 `ProfileCopy`**")
    func labelsComeFromCopy() {
        // `label` 只做转发（两处各拼一遍，早晚出现"菜单写 2026 年、a11y 念 26 年"）。
        #expect(board.years.map(\.label) == ["2026 年", "2025 年", "2024 年"])
        // `id` 就是年份本身 —— `Menu` 的勾选与 `ForEach` 的去重都靠它。
        #expect(ContributionYear(year: 2026).id == 2026)
    }

    @Test("⚠️ 窗口是**自然年**：往年 1/1 0 点 → 12/31 23:59:59（不再是「过去一年」）")
    func pastYearsAreWholeYears() {
        let interval = board.interval(of: ContributionYear(year: 2025))

        #expect(
            interval.start
                == frozenCalendar.date(from: DateComponents(year: 2025, month: 1, day: 1))
        )
        // ⚠️ 终点是 23:59:59 而不是 1/1 00:00（那会把 12 月 31 日整天漏掉）。
        #expect(
            interval.end == frozenCalendar.date(
                from: DateComponents(year: 2025, month: 12, day: 31, hour: 23, minute: 59, second: 59)
            )
        )
    }

    @Test("⚠️ 当前年**截至今天**，不是到 12/31")
    func currentYearStopsAtNow() {
        // 给年末会让窗口**声称**覆盖那些还没发生的日子。那些天的贡献数照样是 0，
        // 所以这个错在屏幕上**看不出来** —— 但窗口是我们对外声称的区间，
        // 而卡片右上还写着"2026 年"（这一条与 `ProfileCopy.yearLabel` 是一对）。
        let interval = board.interval(of: ContributionYear(year: 2026))

        #expect(
            interval.start
                == frozenCalendar.date(from: DateComponents(year: 2026, month: 1, day: 1))
        )
        #expect(interval.end == frozenNow)
    }

    @Test("⚠️ 跨度**不超过一年**：官方上限（而「一年」**不是 365 天**）")
    func windowsNeverExceedOneYear() {
        // 超了的表现是 **HTTP 200 + `errors`**（⇒ `.graphQLErrors`），很容易被误读成
        // "热力图数据坏了"。自然年天然满足 —— 这条断言挡的是"以后有人把窗口改成
        // 过去 13 个月"那类改动（改一处、单测就红）。
        //
        // ⚠️⚠️ **"一年"不是 365 天**：2024 是闰年，它整年的窗口（1/1 0 点 → 12/31 23:59:59）
        //    是 **366 天减 1 秒**。按"≤ 31,536,000 秒"去判会把一个**合法**窗口判成越界
        //    —— 这条口径必须写下来：哪天有人把它实现成秒数比较，表现会是
        //    **"2024 那一年的热力图永远切不过去"**，而错误只会说"贡献数据取不到"。
        //    官方那条上限是**日历**意义的（`to` 省略时默认 = `from` 加一年，
        //    见 `ContributionYear` 抬头的引用），所以断言也照日历写。
        for option in board.years {
            let interval = board.interval(of: option)
            let bound = frozenCalendar.date(byAdding: .year, value: 1, to: interval.start)!
            #expect(interval.end <= bound, "\(option.year) 年的窗口超过了一年")
        }
    }

    @Test("⚠️ 时钟被调到过去：窗口退化成**零长度**，而不是一个负长度区间")
    func futureYearUnderAPastClockIsEmptyNotNegative() {
        // 负长度区间会让服务端**直接拒**。这一支真实数据到不了（谁的时钟会跳到 2020），
        // 但它是一行 `max(start,…)` 的成本，而错误表现是"整个热力图卡片变成失败态"。
        let past = ContributionYearBoard(
            now: { frozenCalendar.date(from: DateComponents(year: 2020, month: 5, day: 1))! },
            calendar: frozenCalendar
        )

        let interval = past.interval(of: ContributionYear(year: 2026))

        #expect(interval.duration == 0)
        // "看这一年的第一天"是那种情形下唯一说得通的答案。
        #expect(
            interval.start
                == frozenCalendar.date(from: DateComponents(year: 2026, month: 1, day: 1))
        )
    }
}

/// x 轴月份表头**挂在哪一列**（`ContributionGrid.monthLabels`、偏差第 44 条）。
///
/// ## 这一套守的是什么
///
/// 月份表头是**原型里根本没有**的东西（原型只有一排格子），所以它没有可照抄的正本，
/// 只能由规则定：**每个月挂在它第一次出现的那一列**。
///
/// 两处"看不出来"的错：
///
/// 1. **月份与列错位** —— 表头整体偏一格、或某几个月逐月漂移一点点
///    （真实数据的表头是 12 个独立标签，偏一格在屏幕上像"整个日历不对齐"，
///    但格子本身是对的，所以很难判断是哪一边错了）；
/// 2. **认不出的日期编出一个月** —— `date` 是服务端给的字符串，畸形串必须只让
///    **那一列不挂标签**，而不是让整排表头消失。
@Suite("热力图 · 月份表头挂哪一列（`ContributionGrid.monthLabels`）")
struct ContributionMonthLabelTests {

    /// 一天一列 —— 于是"哪一列该挂标签"完全由 `dates` 的顺序决定，断言读起来就是它本身。
    private func grid(_ dates: [String]) -> ContributionGrid {
        let columns: [[ContributionDay?]] = dates.map { date in
            var column = Array(repeating: Optional<ContributionDay>.none, count: ContributionGrid.rowCount)
            column[0] = ContributionDay(date: date, count: 0, level: .none)
            return column
        }
        return ContributionGrid(
            columns: columns,
            totalContributions: 0,
            days: dates.map { ContributionDay(date: $0, count: 0, level: .none) }
        )
    }

    @Test("每个月挂在**它第一次出现的那一列**（同月后续的列不重复挂）")
    func eachMonthHangsOnItsFirstColumn() {
        let grid = grid(["2026-01-31", "2026-02-01", "2026-02-08", "2026-03-01"])

        #expect(
            grid.monthLabels == [
                MonthLabel(column: 0, month: 1),
                MonthLabel(column: 1, month: 2),
                MonthLabel(column: 3, month: 3),
            ]
        )
    }

    @Test("⚠️ 认不出的日期**只是那一列不挂标签**，不会编出一个月来")
    func malformedDatesAreSkipped() {
        // `date` 一路是服务端那串 `yyyy-MM-dd`（`ContributionDay` 的抬头讲了为什么不转
        // `Date`）⇒ "取不出月份"是一个真实分支。
        let grid = grid(["2026-00-01", "2026-13-01", "not-a-date", "2026-04-05"])

        // 前三列各自跳过，且**不影响**"上一个月出现过"这个状态 ⇒ 4 月那一列照常挂。
        #expect(grid.monthLabels == [MonthLabel(column: 3, month: 4)])
    }

    @Test("某列没有日子（补位 / 空串）⇒ 它不挂标签，也不打断后面")
    func emptyColumnsCarryNoLabel() {
        let grid = grid(["2026-01-01", "", "2026-01-20"])

        // 中间那列取不出月份 ⇒ 跳过；末列仍是 1 月、且 1 月已经挂过 ⇒ 不重复。
        #expect(grid.monthLabels == [MonthLabel(column: 0, month: 1)])
    }

    @Test("⚠️ 像真的一年（365 天、窗口从周中开始）⇒ 恰好 **12 个**标签，1 月在最左那一列")
    func aRealYearProducesTwelveLabels() {
        // 2026 不是闰年。日子按"平年各月天数"铺，列数按 `layout` 的规则算（首行偏移 4）。
        let monthLengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        var days: [ContributionDay] = []
        for (index, length) in monthLengths.enumerated() {
            for day in 1...length {
                days.append(
                    ContributionDay(
                        date: String(format: "2026-%02d-%02d", index + 1, day),
                        count: 0,
                        level: .none
                    )
                )
            }
        }
        let grid = ContributionGrid(
            columns: ContributionGrid.layout(days: days, firstRow: 4),
            totalContributions: 0,
            days: days
        )

        #expect(grid.columnCount == 53, "4 格偏移 + 365 天 ⇒ 53 列")
        #expect(grid.monthLabels.map(\.month) == Array(1...12))
        // 窗口从 1/1 开始 ⇒ 1 月必然落在第 0 列（这条同时钉住"表头与网格共用同一个坐标系"）。
        #expect(grid.monthLabels.first == MonthLabel(column: 0, month: 1))
        // 2 月 1 日 = 首行偏移 4 + 1 月的 31 天 = 第 35 格 ⇒ 第 5 列、第 0 行。
        #expect(grid.monthLabels[1] == MonthLabel(column: 5, month: 2))

        // 列号严格递增（相等或倒退会让两个标签叠在一起，而格子照常画）。
        #expect(
            zip(grid.monthLabels, grid.monthLabels.dropFirst()).allSatisfy { $0.column < $1.column }
        )
        // ⚠️ `monthLabels` 抬头里那条"不处理重叠"的**前提**：一个月最少 4 列
        //    （28 天 = 4 整周），而 `{n}月` 约 22pt、4 列约 50pt ⇒ 真实数据撞不上。
        //    这条断言把那个前提写下来：哪天窗口不再是自然年，这里会先红。
        #expect(
            zip(grid.monthLabels, grid.monthLabels.dropFirst()).allSatisfy { $1.column - $0.column >= 4 }
        )
    }
}

/// 跨年裁剪 —— 服务端按周返回，而窗口起点是按本机日历算的 1/1 零点
/// （用户走查**第 60 条**、`ContributionYear.datePrefix`）。
///
/// ## 这一套守的是什么
///
/// 用户报回「**12月和1月的坐标值贴在一起**」。机制是：首列里混进一个上一年的 12 月日子
/// ⇒ `monthLabels` 在首列挂「12月」、在第 1 列挂「1月」，而两列只差 **13.5pt**
/// （`ContributionHeatmap` 的 `step = 11 + 2.5`）而「12月」约 **23pt** ⇒ **两个字叠上**。
///
/// ⚠️ 那个混进来的日子**不是服务端塞的**（它不补周：*range comes back exactly as
/// requested, without padding to whole weeks*），而是**我们窗口起点要来的**：
/// 起点按本机日历取 1/1 零点、再按 GMT 写出去，对东八区来说正是 `2025-12-31T16:00:00Z`。
///
/// ⇒ 两条断言：**那一天被裁掉**（表头只剩 1 月），且**同年的日子一格都没挪位**。
/// 后者才是"裁剪"与"整张图错位"的分界 —— 错位的热力图看起来一样正常，
/// 只是每一天都不在它该在的位置（最难自查的一类错）。
@Suite("热力图 · 跨年裁剪（走查第 60 条）")
struct ContributionYearTrimTests {

    /// 走查第 60 条那个真实形状：**首列混进上一年的 12 月**。
    ///
    /// 造 2025-12-31（周三）→ 2026-01-24：首周是"尾巴"（只有 12/31 + 1/1 + 1/2 + 1/3 四天
    /// —— 服务端不给窗口外的日子），之后三个整周（至少一个满 7 天的周给 `firstRow` 当基准）。
    ///
    /// `weekday` 取 `0` = 周日，基准是 2025-12-28（周日）⇒ 12/31 = 3、1/1 = 4。
    private func calendarCrossingNewYear(total: Int = 999) -> ViewerActivityDTO {
        var dates = ["2025-12-31", "2026-01-01", "2026-01-02", "2026-01-03"]
        var weekdays = [3, 4, 5, 6]
        for index in 0..<21 {
            dates.append(String(format: "2026-01-%02d", 4 + index))
            weekdays.append(index % 7)
        }

        var weeks: [ContributionCalendarWeekDTO] = []
        var cursor = 0
        var length = 4                      // 首周只有 4 天
        while cursor < dates.count {
            let end = min(cursor + length, dates.count)
            let slice = (cursor..<end).map { index in
                ContributionCalendarDayDTO(
                    date: dates[index],
                    contributionCount: 1,
                    contributionLevel: "FIRST_QUARTILE",
                    weekday: weekdays[index]
                )
            }
            weeks.append(
                ContributionCalendarWeekDTO(contributionDays: slice, firstDay: slice[0].date)
            )
            cursor = end
            length = 7
        }

        return ViewerActivityDTO(
            contributionsCollection: .init(
                contributionCalendar: .init(totalContributions: total, weeks: weeks)
            ),
            starredRepositories: TotalCountDTO(totalCount: 0),
            repositories: TotalCountDTO(totalCount: 0)
        )
    }

    @Test("⚠️ 首列混进上一年 12 月 ⇒ **裁掉**：表头不再多出一个「12月」")
    func daysOutsideTheYearAreTrimmed() {
        let grid = ProfileMapper().grid(
            calendarCrossingNewYear(),
            year: ContributionYear(year: 2026)
        )

        #expect(grid.days.count == 24, "25 天里裁掉 12/31 那一天")
        #expect(grid.days.first?.date == "2026-01-01")
        #expect(grid.days.allSatisfy { $0.date.hasPrefix("2026-") })

        // 用户看到的那一幕的反面：只剩 1 月、且落在第 0 列
        //（裁之前是「12月」在第 0 列、「1月」在第 1 列，两个标签叠在一起）。
        #expect(grid.monthLabels == [MonthLabel(column: 0, month: 1)])
    }

    @Test("⚠️ 裁剪**只把上一年那几格挖空**，同年的日子一格都没挪位")
    func trimmingOnlyBlanksTheForeignCells() {
        let grid = ProfileMapper().grid(
            calendarCrossingNewYear(),
            year: ContributionYear(year: 2026)
        )

        // 12/31 本来占第 0 列第 3 行；裁掉之后那一格是补位，而 1/1 仍在**它真实该在的
        // 第 0 列第 4 行** —— `firstRow` 是拿裁剪后的第一天重算的（3 → 4）。
        // 漏掉这一步的表现就是整张图上下错位一格。
        #expect(grid.columns[0][3] == nil, "上一年那一格被挖空")
        #expect(grid.columns[0][4]?.date == "2026-01-01")
        #expect(grid.columns[0][5]?.date == "2026-01-02")
        #expect(grid.columns[0][6]?.date == "2026-01-03")

        // 下一列照常从周日起（1/4 是周日）—— 列与列的对齐没有被裁剪打乱。
        #expect(grid.columns[1][0]?.date == "2026-01-04")
        #expect(grid.columns[1][6]?.date == "2026-01-10")
    }

    @Test("⚠️ **同年内**的日子一天都不裁（裁了会让最后一列凭空短一截）")
    func sameYearDaysAreNeverTrimmed() {
        let grid = ProfileMapper().grid(
            calendarCrossingNewYear(),
            year: ContributionYear(year: 2026)
        )

        // 裁剪只认年份前缀 ⇒ 它治的是"跨年"，不是"窗口"。1/24 之后那几天属于 2026，
        // 照旧画出来（真实数据里它们是"今天之后"的空日子，服务端按周返回会带上）。
        #expect(grid.days.last?.date == "2026-01-24")
        #expect(!grid.isEmpty)
    }

    @Test("⚠️ 整份数据都不属于这一年 ⇒ 一张**空网格**（不崩、也不把别年的日子画进来）")
    func fullyTrimmedYieldsEmptyGrid() {
        let grid = ProfileMapper().grid(
            calendarCrossingNewYear(),
            year: ContributionYear(year: 2024)
        )

        #expect(grid.isEmpty)
        #expect(grid.columnCount == 0)
        // ⚠️ 总数照抄服务端的（既有口径：它不是把格子加起来的）⇒ 这一档下会出现
        //    "空格子 + 非零总数"。它只在服务端整份数据都跨年时才到得了，
        //    而这比"把别的年份的日子画进这一年"要好（走查第 60 条已登记）。
        #expect(grid.totalContributions == 999)
    }

    @Test("⚠️ 前缀是**零填充**的四位年 —— 与服务端 `yyyy-MM-dd` 逐字对得上")
    func datePrefixIsZeroPadded() {
        #expect(ContributionYear(year: 2026).datePrefix == "2026-")
        // 不零填充的话这里会是 `"999-"`，于是那一年的图**整张是空的**，
        // 而症状看起来像"数据没取到"、不像"前缀写错了"。
        #expect(ContributionYear(year: 999).datePrefix == "0999-")
    }
}
