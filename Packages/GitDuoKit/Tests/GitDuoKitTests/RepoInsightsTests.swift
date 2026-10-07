import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 他人仓库详情的四路数据与卡片文案（PRD §4.13、TECH_SPEC §9.11、决策 #40/#42）。
///
/// ## 这组断言守的是三类"数据拿到了、但内容有缺口"的情形
///
/// | 缺口 | 表现 | 陷阱 |
/// |---|---|---|
/// | 语言为空（空仓库 / 只有配置文件） | 空数组 | 画一根**全灰的条**会被读成"100% 是某种语言" |
/// | 没有 Release | `release == nil` | 它不是错误（端点把 404 翻译成 `nil`），不许让整页失败 |
/// | 贡献者为空 / 匿名 | 空名单、`login == nil` | 画一排 `?` 头像像"还在加载"；`login` 声明成非空会让整块消失 |
///
/// 还有一条**下界**：`GET /contributors` 不返回总数，一页取回 100 条，
/// **有下一页时只能说"100 位以上"** —— 说成一个确数就是编。
@Suite("他人仓库详情 · 四路数据 / 贡献者计数 / 空态")
struct RepoInsightsTests {

    private let base = Date(timeIntervalSince1970: 1_786_000_000)

    // MARK: - 数据源替身

    private actor ScriptedInsightsSource: RepoInsightsDataSource {

        private let detail: RepositoryDetailDTO
        private let languageBytes: LanguageBytes
        private let release: RepoReleaseDTO?
        private let contributorsPage: Page<RepoContributorDTO>

        private(set) var callCount = 0

        init(
            detail: RepositoryDetailDTO,
            languages: LanguageBytes = [:],
            release: RepoReleaseDTO? = nil,
            contributors: Page<RepoContributorDTO> = Page(items: [], nextCursor: nil)
        ) {
            self.detail = detail
            self.languageBytes = languages
            self.release = release
            self.contributorsPage = contributors
        }

        func repository(owner: String, repo: String) async throws -> RepositoryDetailDTO {
            callCount += 1
            return detail
        }

        func languages(owner: String, repo: String) async throws -> LanguageBytes { languageBytes }

        func latestRelease(owner: String, repo: String) async throws -> RepoReleaseDTO? { release }

        func contributors(owner: String, repo: String) async throws -> Page<RepoContributorDTO> {
            contributorsPage
        }
    }

    private func detailDTO(
        _ fullName: String = "kuda/ui-craft",
        topics: [String]? = nil,
        license: RepositoryDetailDTO.License? = nil,
        stars: Int = 100,
        forks: Int = 5,
        watchers: Int = 12,
        pushedAt: Date? = nil
    ) -> RepositoryDetailDTO {
        RepositoryDetailDTO(
            fullName: fullName,
            description: "一个示例仓库",
            topics: topics,
            license: license,
            defaultBranch: "main",
            starCount: stars,
            forkCount: forks,
            watcherCount: watchers,
            pushedAt: pushedAt
        )
    }

    // MARK: - 四路组装

    @Test("四路数据组装成 `RepoInsights`：语言已在领域层算成占比段")
    func assemblesAllFourRoutes() async throws {
        let source = ScriptedInsightsSource(
            detail: detailDTO(license: .init(name: "MIT License", spdxID: "MIT")),
            languages: ["Swift": 720, "Shell": 180, "Ruby": 100],
            release: RepoReleaseDTO(tagName: "v2.1.0", name: "2.1.0", body: "修了几个 bug",
                                    publishedAt: base.addingTimeInterval(-3_600)),
            contributors: Page(
                items: [RepoContributorDTO(login: "a"), RepoContributorDTO(login: "b")],
                nextCursor: nil
            )
        )

        let insights = try await LoadRepoInsights(source: source).load(fullName: "kuda/ui-craft", now: base)

        #expect(insights.detail.fullName == "kuda/ui-craft")
        #expect(insights.detail.licenseLabel == "MIT")
        #expect(insights.release?.tagName == "v2.1.0")
        #expect(insights.contributors.loadedCount == 2)

        // 语言：字节已换算成百分比，**各段之和恰为 100**（决策 #42 的最大余数法）。
        #expect(insights.languages.map(\.label) == ["Swift", "Shell", "其他"])
        #expect(insights.languages.map(\.percent) == [72, 18, 10])
        #expect(insights.languages.map(\.percent).reduce(0, +) == 100)
    }

    @Test("⚠️ 语言为空 ⇒ **空数组**（视图据此渲染空态，而不是一根全灰的条）")
    func emptyLanguagesStayEmpty() async throws {
        let source = ScriptedInsightsSource(detail: detailDTO(), languages: [:])

        let insights = try await LoadRepoInsights(source: source).load(fullName: "a/b", now: base)

        #expect(insights.languages.isEmpty, "一根全灰的条会被读成「100% 是某种语言」")
    }

    @Test("零字节的语言不参与分段（它只会在图例里多出一行 `Foo 0%`）")
    func zeroByteLanguagesAreDropped() async throws {
        let source = ScriptedInsightsSource(
            detail: detailDTO(),
            languages: ["Swift": 100, "Empty": 0]
        )

        let insights = try await LoadRepoInsights(source: source).load(fullName: "a/b", now: base)

        #expect(insights.languages.map(\.label) == ["Swift"])
    }

    @Test("⚠️ 没有 Release ⇒ `nil`，**不是错误**（端点已把 404 翻译成 nil）")
    func missingReleaseIsNotAFailure() async throws {
        let source = ScriptedInsightsSource(detail: detailDTO(), release: nil)

        let insights = try await LoadRepoInsights(source: source).load(fullName: "a/b", now: base)

        #expect(insights.release == nil)
    }

    @Test(
        "`fullName` 不是 `owner/name` 形状 ⇒ 抛错",
        arguments: ["noSlash", "a/b/c", "/name", "owner/", ""]
    )
    func malformedFullNameThrows(_ fullName: String) async throws {
        let source = ScriptedInsightsSource(detail: detailDTO())
        var threw = false
        do {
            _ = try await LoadRepoInsights(source: source).load(fullName: fullName, now: base)
        } catch let error as RepositoryMappingError {
            #expect(error == .malformedFullName(fullName))
            threw = true
        }
        #expect(threw, "`\(fullName)` 应当被拒绝")
        #expect(await source.callCount == 0, "形状就不对，一个请求都不该发")
    }

    // MARK: - 贡献者计数（下界而不是确数）

    @Test("没有下一页 ⇒ 条目数就是**精确总数**")
    func exactCountWhenNoMorePages() {
        let roster = ContributorRoster(contributors: Array(repeating: Contributor(login: "x"), count: 23))

        #expect(roster.exactCount == 23)
        #expect(roster.sectionTitle == "贡献者 · 23 位")
        #expect(roster.displayTitle == "贡献者 · 23 位")
    }

    @Test("⚠️ 有下一页 ⇒ 只能说 **`100 位以上`**（一个下界，不是猜测）")
    func lowerBoundWhenMorePages() {
        let roster = ContributorRoster(
            contributors: Array(repeating: Contributor(login: "x"), count: 100),
            hasMore: true
        )

        #expect(roster.exactCount == nil, "还有下一页就没有确数")
        #expect(roster.sectionTitle == "贡献者 · 100 位以上")
    }

    @Test("⚠️ 名单为空 ⇒ 标题退成不带计数的 `贡献者`（`0 位` 与正文那句「暂无贡献者」说的是同一件事）")
    func emptyRosterDropsTheCount() {
        let roster = ContributorRoster()

        #expect(roster.displayTitle == "贡献者")
        #expect(roster.displayTitle == RepoInsightNotice.contributorsSectionTitle)
        #expect(!roster.displayTitle.contains("0"))
    }

    // MARK: - 「以及另外 N 位」

    @Test("⚠️ 全都画出来了 ⇒ **`nil`**（不渲染那一行），而不是拼出 `以及另外 0 位`")
    func remainingLabelIsNilWhenEverythingIsVisible() {
        let roster = ContributorRoster(contributors: Array(repeating: Contributor(login: "x"), count: 5))

        #expect(roster.remainingLabel(visibleLimit: 5) == nil)
        #expect(roster.remainingLabel(visibleLimit: 8) == nil, "画得下的比实际还多，同样不该出这一行")
    }

    @Test("⚠️ 原型那处会算成**负数**（`contrib` 小于 8 时）—— 这里必须是 `nil`")
    func remainingLabelNeverGoesNegative() {
        let roster = ContributorRoster(contributors: [Contributor(login: "a")])

        let label = roster.remainingLabel(visibleLimit: 8)
        #expect(label == nil)
        #expect(label?.contains("-") != true)
        #expect(label?.contains("−") != true)
    }

    @Test("还有更多 ⇒ 说 `以及另外 N 位贡献者`（准确的差值）")
    func remainingLabelCountsTheRest() {
        let roster = ContributorRoster(contributors: Array(repeating: Contributor(login: "x"), count: 23))

        #expect(roster.remainingLabel(visibleLimit: 8) == "以及另外 15 位贡献者")
    }

    @Test("⚠️ 有下一页时那句后缀 **`以上`** —— 差值也只是下界")
    func remainingLabelCarriesTheLowerBound() {
        let roster = ContributorRoster(
            contributors: Array(repeating: Contributor(login: "x"), count: 100),
            hasMore: true
        )

        #expect(roster.remainingLabel(visibleLimit: 8) == "以及另外 92 位以上贡献者")
    }

    @Test("负的可见上限不崩（防御性：调用方传错不该让页面炸掉）")
    func negativeVisibleLimitIsClamped() {
        let roster = ContributorRoster(contributors: Array(repeating: Contributor(login: "x"), count: 3))

        #expect(roster.remainingLabel(visibleLimit: -4) == "以及另外 3 位贡献者")
    }

    // MARK: - 匿名贡献者

    @Test("⚠️ 匿名贡献者（`login` / `avatar_url` 都是 null）**不崩**，且不会让整块消失")
    func anonymousContributorsSurvive() async throws {
        let source = ScriptedInsightsSource(
            detail: detailDTO(),
            contributors: Page(
                items: [
                    RepoContributorDTO(login: nil, avatarURL: nil),
                    RepoContributorDTO(login: "real", avatarURL: "https://example.com/a.png"),
                ],
                nextCursor: nil
            )
        )

        let insights = try await LoadRepoInsights(source: source).load(fullName: "a/b", now: base)

        #expect(insights.contributors.loadedCount == 2)
        #expect(insights.contributors.contributors.first?.login == nil)
        #expect(insights.contributors.contributors.first?.avatarURL == nil)
        #expect(insights.contributors.contributors.last?.avatarURL != nil)
    }

    // MARK: - Latest Release 文案

    @Test("发布时间为空 ⇒ **不渲染时间**（不是拿当前时间顶上，那会显示成「刚刚发布」）")
    func missingPublishDateRendersNothing() {
        #expect(LatestRelease(tagName: "v1.0.0", publishedAt: nil).publishedLabel(now: base) == nil)

        let release = LatestRelease(tagName: "v1.0.0", publishedAt: base.addingTimeInterval(-7_200))
        #expect(release.publishedLabel(now: base) == "2 小时前")
    }

    @Test("资产按钮文案 `资产 (3)` 逐字对齐原型")
    func assetsButtonTitleMatchesPrototype() {
        #expect(LatestRelease(tagName: "v1", assetCount: 3).assetsButtonTitle == "资产 (3)")
        #expect(LatestRelease(tagName: "v1").assetsButtonTitle == "资产 (0)")
        #expect(LatestRelease.sourceCodeButtonTitle == "下载源码")
    }

    @Test("版本说明为空（或只有空白）⇒ **不渲染正文**，而不是渲染一个空盒子")
    func blankNotesDoNotRender() {
        #expect(!LatestRelease(tagName: "v1", notes: nil).hasNotes)
        #expect(!LatestRelease(tagName: "v1", notes: "").hasNotes)
        #expect(!LatestRelease(tagName: "v1", notes: "   \n  ").hasNotes)
        #expect(LatestRelease(tagName: "v1", notes: "修了几个 bug").hasNotes)
    }

    // MARK: - 许可证标签

    @Test("`spdx_id` 可用就用它；`NOASSERTION` 是哨兵值，要退到 `name`")
    func licenseLabelFallsBackAroundTheSentinel() {
        #expect(LicenseLabel.text(spdxID: "MIT", name: "MIT License") == "MIT")
        // ⚠️ 漏掉这一档，界面上会出现 `NOASSERTION 许可证` —— 既不是中文也不是许可证名。
        #expect(LicenseLabel.text(spdxID: "NOASSERTION", name: "MIT License") == "MIT License")
        #expect(LicenseLabel.text(spdxID: "noassertion", name: "MIT License") == "MIT License")
        #expect(LicenseLabel.text(spdxID: nil, name: "Apache License 2.0") == "Apache License 2.0")
        #expect(LicenseLabel.text(spdxID: "  ", name: nil) == LicenseLabel.unspecified)
        #expect(LicenseLabel.text(spdxID: nil, name: nil) == "未指定")
        #expect(LicenseLabel.unspecified == "未指定")
    }

    // MARK: - 头部文案

    @Test("头部那行：`{更新时间} 更新 · {许可证} 许可证`（逐字对齐原型）")
    func heroMetaLabelMatchesPrototype() {
        let detail = RepositoryDetail(
            fullName: "kuda/ui-craft",
            defaultBranch: "main",
            starCount: 1,
            forkCount: 2,
            watcherCount: 3,
            pushedAt: base.addingTimeInterval(-86_400)
        )

        #expect(detail.metaLabel(now: base) == "昨天 更新 · 未指定 许可证")
        #expect(detail.updatedLabel(now: base) == "昨天")
    }

    @Test("从未推送过 ⇒ 显示 `未知`（原型兜底对象写的就是它）")
    func neverPushedShowsUnknown() {
        let detail = RepositoryDetail(
            fullName: "a/b", defaultBranch: "main",
            starCount: 0, forkCount: 0, watcherCount: 0, pushedAt: nil
        )

        #expect(detail.updatedLabel(now: base) == RepositoryDetail.unknownUpdateLabel)
        #expect(detail.updatedLabel(now: base) == "未知")
        #expect(detail.metaLabel(now: base) == "未知 更新 · 未指定 许可证")
    }

    @Test("`owner` / `name` 走那**一个**拆分实现")
    func ownerAndNameComeFromTheSingleSplit() {
        let detail = RepositoryDetail(
            fullName: "rust-lang/rust", defaultBranch: "master",
            starCount: 0, forkCount: 0, watcherCount: 0
        )

        #expect(detail.owner == "rust-lang")
        #expect(detail.name == "rust")
        #expect(detail.id == "rust-lang/rust")
    }

    // MARK: - 三个空态文案（PRD §7，2026-10-06 定）

    @Test("三处「数据拿到了但是空的」文案（PRD §7）")
    func emptyStateCopyIsPinned() {
        #expect(RepoInsightNotice.noLanguages == "暂无语言数据")
        #expect(RepoInsightNotice.noRelease == "还没有发布过版本")
        #expect(RepoInsightNotice.noContributors == "暂无贡献者")
        #expect(RepoInsightNotice.contributorsSectionTitle == "贡献者")
    }

    @Test("三处文案各不相同 —— 串用会让用户以为点错了页面")
    func emptyStateCopyIsDistinct() {
        let all = [RepoInsightNotice.noLanguages, RepoInsightNotice.noRelease, RepoInsightNotice.noContributors]
        #expect(Set(all).count == 3)
    }
}
