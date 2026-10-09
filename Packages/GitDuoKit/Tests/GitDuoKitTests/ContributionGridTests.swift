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

    @Test("⚠️ 一整年 = **53 列 × 7 行**，前面空 4 格、后面空 2 格（坐标就是这个）")
    func fullYearIsFiftyThreeColumns() {
        let dto = calendar(firstRow: 4, totalDays: 365)
        let grid = ProfileMapper().grid(dto)

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
        let first = ProfileMapper().grid(calendar(firstRow: 4, totalDays: 365))
        let shifted = ProfileMapper().grid(calendar(firstRow: 4, totalDays: 365, weekdayOffset: 1))
        let shiftedMore = ProfileMapper().grid(
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
        let grid = ProfileMapper().grid(dto)

        #expect(grid.totalContributions == 9_999)
        #expect(grid.dayCount == 365)
    }

    @Test("`date` 原样保留服务端那串 `yyyy-MM-dd`（不转 `Date`，也就不必替它选时区）")
    func dateIsKeptVerbatim() {
        let dto = calendar(firstRow: 0, totalDays: 7)
        let grid = ProfileMapper().grid(dto)

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

        let grid = ProfileMapper().grid(dto)

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

        let grid = ProfileMapper().grid(dto)

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
