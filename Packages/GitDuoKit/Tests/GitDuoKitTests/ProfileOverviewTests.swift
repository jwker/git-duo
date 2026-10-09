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

/// 「我的」页的两路取数（TECH_SPEC §9.14）。
///
/// ## 这一套守的是"失败要隔离"
///
/// 合成一个"整页成功 / 失败"的开关，表现就是**一张热力图取不到、
/// 整个「我的」页变成一片失败态** —— 而大头像与 `@登录名` 是本机从登录名画出来的，
/// 它们根本不会失败（决策 #76 末句点名要避免的正是这件事）。
@Suite("我的页 · 两路取数与降级（`LoadProfileOverview`）")
struct LoadProfileOverviewTests {

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

        let overview = await LoadProfileOverview(source: source).load()

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

            let overview = await LoadProfileOverview(source: source).load()

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

        let overview = await LoadProfileOverview(source: source).load()

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

        let overview = await LoadProfileOverview(source: source).load()

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

        let overview = await LoadProfileOverview(source: source).load()

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

        let overview = await LoadProfileOverview(source: source).load()

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

        let overview = await LoadProfileOverview(source: source).load()

        #expect(overview.gridValue?.totalContributions == 0)
        #expect(overview.gridValue?.dayCount == 365, "图照常画满一年（PRD §4.17 不给空态）")
        #expect(overview.stats.repositories == 0, "0 与「不知道」不同 —— 这里是真的 0")
        #expect(overview.stats.followers == 126)
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

    func loadActivity() async throws -> ViewerActivityDTO {
        activityCalls += 1
        return try activityResult.get()
    }
}
