import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 头部三个统计项（PRD §4.17、决策 #76）。
///
/// ## 三个都是 Optional，而这不是"防御性编码"
///
/// 每一个 `nil` 都对应一条真实可达的路径：`GET /user` 失败 ⇒ 只剩仓库与 Star；
/// GraphQL 那一路失败 ⇒ 只剩 Follower；两路都失败 ⇒ 一项都没有（整行不画）。
/// GraphQL 还允许"部分成功"（`data` + `errors` 并存），
/// 所以 `ProfileStats` 三个字段**全可选** —— 把前两个做成非可选就表达不了
/// "日历那一格没拿到、两个计数拿到了"这个形状。
@Suite("我的页 · 三个统计项（失败要能隔离）")
struct ProfileStatsTests {

    @Test("三项齐全：顺序固定为 仓库 / Star / Follower")
    func allThreeInFixedOrder() {
        let stats = ProfileStats(repositories: 42, stars: 318, followers: 126)

        #expect(stats.items.map(\.kind) == [.repositories, .stars, .followers])
        #expect(stats.items.map(\.title) == ["仓库", "Star", "Follower"])
        #expect(stats.items.map(\.value) == [42, 318, 126])
        #expect(!stats.isEmpty)
    }

    @Test("⚠️ 显示名**逐字**取自原型：第三个是单数的 `Follower`（不是 `关注者`、也不是 `Followers`）")
    func titlesAreVerbatim() {
        // 顺手"修正"成复数会让它与原型对不上，而屏幕上看起来毫无异常。
        #expect(ProfileStatKind.repositories.title == "仓库")
        #expect(ProfileStatKind.stars.title == "Star")
        #expect(ProfileStatKind.followers.title == "Follower")
        #expect(ProfileStatKind.allCases == [.repositories, .stars, .followers])
    }

    @Test("只有 Follower（GraphQL 那一路失败）⇒ 只画一项")
    func onlyFollowersSurvives() {
        let stats = ProfileStats(followers: 126)

        #expect(stats.items.map(\.kind) == [.followers])
        #expect(stats.repositories == nil)
        #expect(stats.stars == nil)
    }

    @Test("只有仓库与 Star（`GET /user` 失败）⇒ Follower 那一项**整项不画**")
    func missingFollowersIsSkippedNotZeroed() {
        // `0` 是"就是零"，`nil` 是"不知道" —— 填 0 会让用户以为自己一个关注者都没有。
        let stats = ProfileStats(repositories: 42, stars: 318)

        #expect(stats.items.map(\.kind) == [.repositories, .stars])
        #expect(!stats.items.contains { $0.kind == .followers })
    }

    @Test("三项都没有 ⇒ `isEmpty`（整行不画，而不是画一行空的东西）")
    func emptyStatsReportEmpty() {
        let stats = ProfileStats()

        #expect(stats.isEmpty)
        #expect(stats.items.isEmpty)
        #expect(ProfileStats.empty == stats)
    }

    @Test("计数为负时夹到 0（`-1` 比 `0` 更让人困惑）")
    func negativesAreClampedToZero() {
        let stats = ProfileStats(repositories: -5, stars: -1, followers: -100)

        #expect(stats.items.map(\.value) == [0, 0, 0])
        #expect(ProfileStatItem(kind: .stars, value: -3).value == 0)
    }

    @Test("数字**千分位、不缩写**（与仓库卡片上的 `2.3k` 有意不同）")
    func valuesAreGroupedNotCompacted() {
        // 头部这三个数是用户要**读准**的；卡片窄、要省宽度才缩写。
        #expect(ProfileStatItem(kind: .stars, value: 42).valueText == "42")
        #expect(ProfileStatItem(kind: .stars, value: 1_234).valueText == "1,234")
        #expect(ProfileStatItem(kind: .stars, value: 1_024_000).valueText == "1,024,000")
    }
}

// MARK: - 钉住的"现在"

/// 固定的日历与时点 —— **2026-06-15 12:00 GMT**。
///
/// ⚠️ 窗口（`ContributionYearBoard`）是本片唯一的日期算法，而它的取值直接依赖
/// "现在"与日历。挂真时间断言会在**元旦与跨年那一刻偶发变红** ——
/// 那是最难查的一类红（一年只有一天跑得到，而且看起来像"图少了一块"）。
/// 所以两个入参都钉死，并从这里往后排（`ContributionGridTests.swift` 的年份那套也用它们）。
///
/// ⚠️ 日历显式设成 **GMT**，与 `ContributionYearBoard` 里"`calendar` 必须带时区"那条
/// 是同一件事：`Calendar(identifier:)` 裸建会让 1/1 落到 GMT，
/// 于是断言会**随跑测试那台机器的时区而变**（东八区看到的 1/1 不是同一个瞬间）。
let frozenCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

/// 见 `frozenCalendar`。
let frozenNow = frozenCalendar.date(
    from: DateComponents(year: 2026, month: 6, day: 15, hour: 12)
)!

/// 「我的」页的两路取数（TECH_SPEC §9.14）。
///
/// ## 这一套守的是"失败要隔离"
///
/// 合成一个"整页成功 / 失败"的开关，表现就是**一张热力图取不到、
/// 整个「我的」页变成一片失败态** —— 而大头像与 `@登录名` 是本机从登录名画出来的，
/// 它们根本不会失败（决策 #76 末句点名要避免的正是这件事）。
///
/// ## ⚠️ 2026-10-09 起还多守两件事：**窗口**与**年份**
///
/// 热力图要能切年份（用户走查第 2 条）⇒ `load()` 变成 `load(year:)`，
/// 而"这一份结果是哪一年换来的"跟着进了 `ProfileOverview`。于是这里加两条断言：
///
/// 1. **窗口真的传到了数据源**（自然年；当前年截至今天）——
///    证据取自替身**收到**的那两个瞬间，而不是我们"以为"传下去的东西；
/// 2. **`year` 跟着数据走** —— 失败时也在，且不许出现"写着 2025、画着 2026"。
///
/// 年份选项本身与窗口算术在 `ContributionYearTests`（`ContributionGridTests.swift`）。
@Suite("我的页 · 两路取数与降级（`LoadProfileOverview`）")
struct LoadProfileOverviewTests {

    /// 钉死的年份板（`now` = 2026-06-15 12:00 GMT）。
    ///
    /// ⚠️ 做成计算属性而不是全局常量：`ContributionYearBoard` 是一个值，
    /// 每个用例各拿一份，避免"某个用例改了它"这种事有发生的余地。
    private var board: ContributionYearBoard {
        ContributionYearBoard(now: { frozenNow }, calendar: frozenCalendar)
    }

    /// 取**某一年**的两路数据；不指定就取当前年（= 2026）。
    ///
    /// ⚠️ 包这一层只是因为 `board` 必须注进去（不注就会按**跑测试那一刻**算窗口，
    /// 而下面那些"哪一路失败时哪几块降级"的断言其实不关心窗口）。
    /// 它**不**隐藏 `LoadProfileOverview` —— 窗口那两条仍然把构造写全。
    private func load(_ source: ScriptedProfileSource, year: Int? = nil) async -> ProfileOverview {
        let board = self.board
        return await LoadProfileOverview(source: source, board: board)
            .load(year: year.map { ContributionYear(year: $0) } ?? board.current)
    }

    private func activity(
        repositories: Int = 42,
        stars: Int = 318,
        calendarDays: Int = 7,
        total: Int? = nil
    ) -> ViewerActivityDTO {
        let days = (0..<calendarDays).map { index in
            ContributionCalendarDayDTO(
                date: String(format: "2026-%04d", index),
                contributionCount: 1,
                contributionLevel: "FIRST_QUARTILE",
                weekday: 0
            )
        }
        return ViewerActivityDTO(
            contributionsCollection: .init(
                contributionCalendar: .init(
                    // 格子数与总数**分开传**：两者本该一致，但代码里它们来自两个字段，
                    // 测试要能单独拨动其中一个（见"零贡献"那条）。
                    totalContributions: total ?? calendarDays,
                    weeks: [ContributionCalendarWeekDTO(
                        contributionDays: days,
                        firstDay: "2026-0000"
                    )]
                )
            ),
            starredRepositories: TotalCountDTO(totalCount: stars),
            repositories: TotalCountDTO(totalCount: repositories)
        )
    }

    private func profile(
        login: String = "octocat",
        name: String? = "小明",
        followers: Int = 126,
        avatar: String? = nil
    ) -> ViewerProfileDTO {
        ViewerProfileDTO(
            login: login,
            name: name,
            bio: nil,
            followers: followers,
            avatarURL: avatar
        )
    }

    @Test("两路都成 ⇒ 三块都有值，三个数各取各的来源")
    func bothSucceed() async {
        let source = ScriptedProfileSource(
            profile: .success(profile()),
            activity: .success(activity())
        )

        let overview = await load(source)

        #expect(overview.profile == ViewerProfile(login: "octocat", name: "小明", bio: nil))
        #expect(overview.gridValue?.dayCount == 7)
        #expect(overview.stats.items.map(\.value) == [42, 318, 126])
        // 两路**并发**：各问一次，不多不少（串行会让这一页白等一次往返）。
        #expect(await source.profileCalls == 1)
        #expect(await source.activityCalls == 1)
    }

    @Test("头像地址：原样翻译成 `URL`；**空串与缺席都落到 `nil`**（偏差第 43 条）")
    func avatarURLTranslation() async {
        // ⚠️ 空串这一档**不是假想**：`GET /user` 的同一份响应里 `gravatar_id` 就是 `""`
        // （`ViewerProfileDTO` 的说明里以它为由把字段收成 `String?`）⇒
        // "服务端给了个空串"必须被当成"没有头像"，而不是让 `URL` 解码抛错、整条 `/user` 失败。
        let cases: [(String?, URL?)] = [
            ("https://avatars.githubusercontent.com/u/1?v=4",
             URL(string: "https://avatars.githubusercontent.com/u/1?v=4")),
            ("", nil),
            ("   ", nil),
            (nil, nil),
        ]

        for (raw, expected) in cases {
            let source = ScriptedProfileSource(
                profile: .success(profile(avatar: raw)),
                activity: .success(activity())
            )

            let overview = await load(source)

            #expect(overview.profile?.avatarURL == expected, "输入 `\(raw ?? "nil")`")
            // 头像这一项**无论如何都不影响**其余字段（昵称与关注者数照常在）。
            #expect(overview.profile?.name == "小明")
            #expect(overview.stats.followers == 126)
        }
    }

    @Test("`GET /user` 失败 ⇒ 资料头部降级，**热力图与两个计数照常在**")
    func profileFailureIsIsolated() async {
        let source = ScriptedProfileSource(
            profile: .failure(.unauthorized),
            activity: .success(activity())
        )

        let overview = await load(source)

        #expect(overview.identity == .failure(.unauthorized))
        #expect(overview.profile == nil)
        #expect(overview.gridValue != nil, "热力图来自 GraphQL，与 REST 那一发无关")
        // Follower 跟着 `GET /user` 一起没了，但仓库与 Star 是 GraphQL 给的。
        #expect(overview.stats.items.map(\.kind) == [.repositories, .stars])
        #expect(overview.stats.followers == nil)
    }

    @Test("GraphQL 那一路失败 ⇒ 热力图降级，**Follower 照常在**")
    func activityFailureIsIsolated() async {
        let resetAt = Date(timeIntervalSince1970: 1_700_000_000)
        let source = ScriptedProfileSource(
            profile: .success(profile()),
            activity: .failure(.rateLimited(resetAt: resetAt, isSecondary: false))
        )

        let overview = await load(source)

        #expect(overview.grid == .failure(.rateLimited(resetAt: resetAt, isSecondary: false)))
        #expect(overview.gridValue == nil)
        #expect(overview.profile != nil)
        #expect(overview.stats.items.map(\.kind) == [.followers])
    }

    @Test("两路都失败 ⇒ 一块都没有，但**不抛错**（返回的是一份「什么都没拿到」的结果）")
    func bothFailuresStillReturnAResult() async {
        let source = ScriptedProfileSource(
            profile: .failure(.transport(URLError(.notConnectedToInternet))),
            activity: .failure(.serverError(status: 503))
        )

        let overview = await load(source)

        #expect(overview.identity.isFailure)
        #expect(overview.grid.isFailure)
        #expect(overview.stats.isEmpty, "一项都没有 ⇒ 整行统计不画")
    }

    @Test("⚠️ 错误**原样**带过去，不被折叠成一句「加载失败」")
    func errorsAreCarriedVerbatim() async {
        // 归一化只有一处（数据层的令牌出口，决策 #33）；领域层再包一层的话，
        // "断网"会被说成"检查网络"，而 404 与无权限本来就被 GitHub 混同（§14）。
        let source = ScriptedProfileSource(
            profile: .failure(.notFound),
            activity: .success(activity())
        )

        let overview = await load(source)

        #expect(overview.identity.error == .notFound)
    }

    @Test("零贡献**不是**失败：拿到的是一张全最浅的图 + `0 次贡献`，不是降级态")
    func zeroContributionIsAValueNotAFailure() async {
        let source = ScriptedProfileSource(
            profile: .success(profile()),
            activity: .success(
                activity(repositories: 0, stars: 0, calendarDays: 365, total: 0)
            )
        )

        let overview = await load(source)

        #expect(overview.gridValue?.totalContributions == 0)
        #expect(overview.gridValue?.dayCount == 365, "图照常画满一年（PRD §4.17 不给空态）")
        #expect(overview.stats.repositories == 0, "0 与「不知道」不同 —— 这里是真的 0")
        #expect(overview.stats.followers == 126)
    }

    // MARK: - 年份与窗口（2026-10-09 加，用户走查第 2 条）

    @Test("可切换的年份：**当前年 + 前 2 年**、当前年在第一位（用户 2026-10-09 拍板）")
    func selectableYearsComeFromTheBoard() async {
        let source = ScriptedProfileSource(
            profile: .success(profile()),
            activity: .success(activity())
        )
        let loader = LoadProfileOverview(source: source, board: board)

        #expect(loader.years.map(\.year) == [2026, 2025, 2024])
        #expect(loader.years.count == ContributionYearBoard.selectableCount)
        // ⚠️ 当前年**永远是第一位**：它不是"某一年"，而是"我现在这一年"，
        //    摆在第一项才能让"想看回默认那一年"永远只有一次点击。
        #expect(loader.currentYear == loader.years[0])

        // 选项与默认值必须是**同一个口径**：分两处算，早晚出现"菜单写着 2025、取的是 2024"。
        let first = await load(source)
        #expect(first.year == loader.currentYear)
    }

    @Test("⚠️ 窗口真的传到了数据源：**自然年**，当前年**截至今天**（偏差第 44 条）")
    func windowReachesTheSource() async {
        // 这一条是"切换年份真的换了窗口"的**唯一**证据：`lastInterval` 记的是替身
        // **收到**的那两个瞬间，而不是我们"以为"传下去的东西。
        let source = ScriptedProfileSource(
            profile: .success(profile()),
            activity: .success(activity())
        )

        _ = await load(source, year: 2025)
        let past = await source.lastInterval
        #expect(
            past == DateInterval(
                start: frozenCalendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!,
                end: frozenCalendar.date(
                    from: DateComponents(year: 2025, month: 12, day: 31, hour: 23, minute: 59, second: 59)
                )!
            ),
            "往年是**整年**：1/1 0 点 → 12/31 23:59:59"
        )

        _ = await load(source, year: 2026)
        let current = await source.lastInterval
        #expect(
            current == DateInterval(
                start: frozenCalendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!,
                end: frozenNow
            ),
            "当前年**截至今天** —— 给年末会让窗口声称覆盖还没发生的日子"
        )
    }

    @Test("⚠️ `year` 跟着数据走（切换那一瞬间不许出现「写着 2025、画着 2026」）")
    func yearTravelsWithTheData() async {
        // 两个数各自都是真的、摆在一起才成了假话 —— 同 `ViewerActivityDTO` 那条
        // `affiliations` 的教训。所以 `year` 不是视图的 `@State`，它在这一份结果里。
        let source = ScriptedProfileSource(
            profile: .success(profile()),
            activity: .success(activity())
        )

        // ⚠️ 先把 `await` 取出来再断言（`#expect` 是 autoclosure，`await` 写进去是坑，
        //    见 `DETAILS.md §12`）。
        let defaultYear = await load(source)
        #expect(defaultYear.year == ContributionYear(year: 2026))

        let pastYear = await load(source, year: 2024)
        #expect(pastYear.year == ContributionYear(year: 2024))
    }

    @Test("⚠️ 热力图那一路失败时 `year` **照常有** —— 失败态也要画得出年份切换器")
    func yearSurvivesFailure() async {
        // 失败的是"这一年的数"，不是"我们在问哪一年"。缺了 `year`，
        // 失败态那个切换器就只能写死一个年份（或干脆没有），而那正是
        // "离线时用户最需要切回能看的那一年"这个出口消失的成因。
        let source = ScriptedProfileSource(
            profile: .success(profile()),
            activity: .failure(.serverError(status: 503))
        )

        let overview = await load(source, year: 2025)

        #expect(overview.grid.isFailure)
        #expect(overview.year == ContributionYear(year: 2025))
        #expect(overview.stats.followers == 126, "另一路不受牵连")
    }
}

// MARK: - 替身

/// 「我的」页两路取数的脚本化替身 —— 领域层测试用它，**不碰 HTTP**。
///
/// 理由同 `ScriptedRepositorySource` / `ScriptedSearchSource`：这一层要断言的是
/// "哪一路失败时哪几块降级"，而不是"GraphQL 查询文本里 `first:` 写了几"。
private actor ScriptedProfileSource: ProfileDataSource {

    private let profileResult: Result<ViewerProfileDTO, GitHubError>
    private let activityResult: Result<ViewerActivityDTO, GitHubError>

    private(set) var profileCalls = 0
    private(set) var activityCalls = 0

    /// 最近一次收到的窗口（`nil` = 还没被问过）—— 2026-10-09 加。
    ///
    /// ⚠️ 它记的是替身**收到**的那两个瞬间，而不是测试"以为"传下去的东西：
    /// "切换年份真的换了窗口"这件事只有从这里才验证得到（`windowReachesTheSource`）。
    /// 记在 `try` **之前** —— 失败的那一次请求同样是"发起了、带了哪个窗口"的证据。
    private(set) var lastInterval: DateInterval?

    init(
        profile: Result<ViewerProfileDTO, GitHubError>,
        activity: Result<ViewerActivityDTO, GitHubError>
    ) {
        self.profileResult = profile
        self.activityResult = activity
    }

    func loadProfile() async throws -> ViewerProfileDTO {
        profileCalls += 1
        return try profileResult.get()
    }

    func loadActivity(from: Date, to: Date) async throws -> ViewerActivityDTO {
        activityCalls += 1
        lastInterval = DateInterval(start: from, end: to)
        return try activityResult.get()
    }
}
