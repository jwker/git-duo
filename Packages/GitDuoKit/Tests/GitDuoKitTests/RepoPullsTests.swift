import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 探索 PR 列表：三种状态的判定 · **滤掉已关闭未合并** · 卡片文案（PRD §4.15、决策 #39）。
///
/// ## 这组断言守的是一条**很容易漏一半**的规则
///
/// GitHub **没有**独立的 `merged` 状态：`state` 只有 `open` / `closed`，
/// 而"合并了"与"关掉了但没合"在它上面长得一模一样。区分只能靠 `merged_at`
/// （见 `PullRequestDTO.isMerged`）。各调用点自己写一遍那个布尔表达式的下场是
/// **总有一处漏掉 `merged_at` 那一半** —— 于是所有被关闭的 PR 都显示成"已合并"，
/// 而这看起来完全正常。
///
/// 第二件事是**过滤**（2026-10-07 明确）：本列表只列开放与已合并，
/// 而 `state=all` 会把三种都取回来。滤错了的表现不是报错，是"列表里多了一类东西"。
@Suite("探索 PR 列表 · 状态判定 / 过滤 / 文案")
struct RepoPullsTests {

    private let base = Date(timeIntervalSince1970: 1_786_000_000)

    // MARK: - 数据源替身

    private actor ScriptedPullsSource: RepoPullsDataSource {

        private var pages: [Page<PullRequestDTO>]
        private(set) var cursors: [URL?] = []
        /// 实际发出去的 `state` —— 四个调用方的意图各不相同，传错档会静默给错一批。
        private(set) var states: [String] = []

        init(pages: [Page<PullRequestDTO>]) { self.pages = pages }

        func pullRequests(
            owner: String,
            repo: String,
            state: String,
            cursor: URL?
        ) async throws -> Page<PullRequestDTO> {
            states.append(state)
            cursors.append(cursor)
            let next = pages.count > 1 ? pages.removeFirst() : (pages.first ?? Page(items: [], nextCursor: nil))

            // ⚠️ 替身**按 `state` 筛一遍**，模仿服务端 —— 否则"三档各自要哪一批"这件事
            //    在测试里根本不存在：喂进去 3 条，三档都会拿回同样的 3 条，
            //    而真实调用里"要错一批"是这个功能唯一会错的地方（见 `stateIsForwardedVerbatim`）。
            let filtered = next.items.filter { dto in
                switch state {
                case "open": dto.state == "open"
                case "closed": dto.state == "closed"
                default: true          // `all` = 不筛（服务端语义）
                }
            }
            return Page(items: filtered, nextCursor: next.nextCursor, headers: next.headers)
        }
    }

    private func dto(
        _ number: Int,
        title: String = "标题",
        state: String = "open",
        mergedAt: Date? = nil,
        head: String = "feature/x",
        base baseRef: String = "main",
        author: String? = nil,
        updatedAt: Date? = nil
    ) -> PullRequestDTO {
        PullRequestDTO(
            number: number,
            title: title,
            state: state,
            mergedAt: mergedAt,
            head: .init(ref: head),
            base: .init(ref: baseRef),
            user: author.map(AuthorDTO.init(login:)),
            updatedAt: updatedAt
        )
    }

    // MARK: - 状态判定（`merged` 是算出来的）

    @Test("⚠️ 状态判定：**`closed` + 有 `merged_at` 才算已合并** —— 判错了会把「关掉了没合」显示成「已合并」")
    func mergedIsDerivedFromMergedAtNotFromClosedAlone() async throws {
        let source = ScriptedPullsSource(pages: [
            Page(items: [
                dto(1, state: "open"),
                dto(2, state: "closed", mergedAt: base),      // 已合并
                dto(3, state: "closed", mergedAt: nil),       // 关闭但没合 ⇒ 被滤
            ], nextCursor: nil)
        ])

        let page = try await LoadRepoPulls(source: source).load(fullName: "a/b", state: .all)

        // 2 号留下 ⇒ `state == "closed"` 加上 `merged_at` 确实判成了 `.merged`；
        // 3 号走的是**另一个分支**（`.closed` 后被滤），两条路径必须分开 ——
        // 若判定漏掉 `merged_at` 那一半，3 号会以 `.merged` 的身份混进列表。
        #expect(page.items.map(\.state) == [.open, .merged])
        #expect(page.items.map(\.number) == [1, 2])
    }

    @Test("⚠️ **已关闭但未合并的被滤掉** —— 只列开放与已合并（PRD §4.15，2026-10-07 明确）")
    func closedUnmergedIsFilteredOut() async throws {
        let source = ScriptedPullsSource(pages: [
            Page(items: [
                dto(1, state: "open"),
                dto(2, state: "closed", mergedAt: base),
                dto(3, state: "closed", mergedAt: nil),
                dto(4, state: "closed", mergedAt: nil),
            ], nextCursor: nil)
        ])

        let page = try await LoadRepoPulls(source: source).load(fullName: "a/b", state: .all)

        #expect(page.items.map(\.number) == [1, 2])
        #expect(!page.items.contains { $0.state == .closed },
                "被关闭未合并的 PR 只说明没人合，不是本列表要展示的贡献")
    }

    @Test("⚠️ 过滤**不能**顺手把已合并的一起滤掉（`state=open` 就会犯这个错）")
    func mergedSurvivesTheFilter() async throws {
        let source = ScriptedPullsSource(pages: [
            Page(items: [dto(1, state: "closed", mergedAt: base)], nextCursor: nil)
        ])

        let page = try await LoadRepoPulls(source: source).load(fullName: "a/b", state: .all)

        #expect(page.items.count == 1)
        #expect(page.items.first?.state == .merged)
    }

    @Test("⚠️ 滤空了一页**不等于到底** —— `hasMore` 必须原样带走")
    func filteringDoesNotSwallowTheCursor() async throws {
        let next = URL(string: "https://api.github.com/repos/a/b/pulls?page=2")!
        let source = ScriptedPullsSource(pages: [
            // 这一页全是"关闭未合并"，滤完一条不剩 —— 但后面还有页。
            Page(items: [dto(1, state: "closed"), dto(2, state: "closed")], nextCursor: next)
        ])

        let page = try await LoadRepoPulls(source: source).load(fullName: "a/b", state: .all)

        #expect(page.items.isEmpty)
        #expect(page.nextCursor == next, "丢掉游标会让用户以为这个仓库一个 PR 都没有")
        #expect(page.hasMore)
    }

    @Test("续页把上一页的游标真的传下去了")
    func continuationPassesCursorThrough() async throws {
        let next = URL(string: "https://api.github.com/repos/a/b/pulls?page=2")!
        let source = ScriptedPullsSource(pages: [Page(items: [dto(1)], nextCursor: next)])
        let loader = LoadRepoPulls(source: source)

        _ = try await loader.load(fullName: "a/b", state: .all)
        _ = try await loader.load(fullName: "a/b", state: .all, cursor: next)

        #expect(await source.cursors == [nil, next])
    }

    @Test(
        "`fullName` 不是 `owner/name` 形状 ⇒ 抛错",
        arguments: ["noSlash", "a/b/c", "/name", "owner/", ""]
    )
    func malformedFullNameThrows(_ fullName: String) async throws {
        let source = ScriptedPullsSource(pages: [])
        var threw = false
        do {
            _ = try await LoadRepoPulls(source: source).load(fullName: fullName, state: .all)
        } catch let error as RepositoryMappingError {
            #expect(error == .malformedFullName(fullName))
            threw = true
        }
        #expect(threw, "`\(fullName)` 应当被拒绝")
    }

    // MARK: - 卡片副标题

    @Test("副标题逐字对齐原型：`#57 · feature/repo-hub → main`（**不含作者**，PRD §4.15）")
    func metaLabelMatchesPrototype() {
        let row = PullRow(number: 57, title: "标题", state: .open,
                          headRef: "feature/repo-hub", baseRef: "main")

        #expect(row.metaLabel == "#57 · feature/repo-hub → main")
    }

    @Test("⚠️ 分支名只取 `ref`（不带 fork 的 owner）—— `main → main` 不代表自己合并自己")
    func branchNamesAreBareRefs() {
        let row = PullRow(number: 1, title: "t", state: .open, headRef: "main", baseRef: "main")

        #expect(row.metaLabel == "#1 · main → main")
    }

    @Test("三档状态的读屏词（图标不该是状态的唯一载体）")
    func stateLabelsAreReadable() {
        #expect(PullRequestState.open.label == "开放")
        #expect(PullRequestState.merged.label == "已合并")
        #expect(PullRequestState.closed.label == "已关闭")
    }

    @Test("⚠️ 胶囊上的状态词是**英文**（原型 `pillOf` 逐字），且不带前置字形")
    func pillTitlesMatchPrototype() {
        #expect(PullRequestState.open.pillTitle == "Open")
        #expect(PullRequestState.merged.pillTitle == "Merged")
        #expect(PullRequestState.closed.pillTitle == "Closed")

        // 原型那串里还有一个 `●` / `⇿` 前缀 —— 有意不带（它已由胶囊的三处配色表达，
        // 混进文案会让读屏念出一个多余符号）。这条断言就是那个决定的守卫。
        for state in [PullRequestState.open, .merged, .closed] {
            #expect(!state.pillTitle.contains("●"))
            #expect(!state.pillTitle.contains("⇿"))
        }
    }

    @Test("`id` 用 PR 编号 —— 它同时是跳详情页的键")
    func idIsTheNumber() {
        #expect(PullRow(number: 57, title: "t", state: .open,
                        headRef: "a", baseRef: "b").id == 57)
    }

    // MARK: - 说明行与空态

    @Test("⚠️ 说明行**只有仓库全名**，刻意不含任何计数（PRD §4.15）")
    func summaryLineHasNoCount() {
        let line = PullListIndicator.summaryLine(fullName: "kuda/ui-craft")

        #expect(line == "kuda/ui-craft")
        // 说"共 N 个 PR"会把用户看不到的（已关闭未合并的）也算进去。
        #expect(!line.contains("个"))
        #expect(!line.contains("演示"))
    }

    @Test("页脚与空态文案（PRD §4.15 / §7，2026-10-07 定）")
    func copyIsPinned() {
        #expect(PullListIndicator.footer == "他人仓库：可评论 Review，合并 / 关闭需维护者权限")
        #expect(PullListIndicator.emptyTitle == "暂无 Pull Request")
        #expect(PullListIndicator.emptyHint == "这个仓库还没有任何 Pull Request")
    }

    @Test("⚠️ 空态两行不分家，也不能与 Issues 那页串用")
    func emptyCopyIsDistinctFromIssues() {
        #expect(PullListIndicator.emptyTitle != PullListIndicator.emptyHint)
        #expect(PullListIndicator.emptyTitle != OpenIssueIndicator.emptyTitle)
        #expect(PullListIndicator.footer != OpenIssueIndicator.footer)
    }

    // MARK: - 切片 7：三档都用同一个用例（决策 #61）

    @Test("⚠️ 三个调用方各自的 `state` 逐档传下去（`.all` / `.open` / `.closed` 意图不同）")
    func stateIsForwardedVerbatim() async throws {
        let source = ScriptedPullsSource(pages: [Page(items: [], nextCursor: nil)])
        let loader = LoadRepoPulls(source: source)

        _ = try await loader.load(fullName: "a/b", state: .all)
        _ = try await loader.load(fullName: "a/b", state: .open)
        _ = try await loader.load(fullName: "a/b", state: .closed)

        #expect(await source.states == ["all", "open", "closed"])
    }

    @Test(
        """
        ⚠️ **「关闭但未合并」在三档里都不显示** —— 过滤条件与 `state` 无关，
        写成一条不变量，而不是按档分支（按档写要维护三处，漏一处屏幕上完全看不出来）
        """
    )
    func closedButNotMergedIsHiddenInEveryState() async throws {
        // 同一批数据喂三次：开放 / 已合并 / 关闭未合并 各一条。
        let makeSource = {
            ScriptedPullsSource(pages: [
                Page(
                    items: [
                        self.dto(1, title: "还开着", state: "open"),
                        self.dto(2, title: "合了", state: "closed", mergedAt: self.base),
                        self.dto(3, title: "关掉了没合", state: "closed", mergedAt: nil),
                    ],
                    nextCursor: nil
                )
            ])
        }

        for state in [RepoListState.all, .open, .closed] {
            let page = try await LoadRepoPulls(source: makeSource()).load(fullName: "a/b", state: state)
            #expect(
                page.items.contains { $0.number == 3 } == false,
                "\(state.rawValue)：关闭但未合并的 3 号不该出现"
            )
        }
    }

    @Test("各档实际留下谁：`.all` 开放 + 已合并 · `.open` 只剩开放 · `.closed` 只剩已合并")
    func eachStateKeepsTheRightRows() async throws {
        let makeSource = {
            ScriptedPullsSource(pages: [
                Page(
                    items: [
                        self.dto(1, state: "open"),
                        self.dto(2, state: "closed", mergedAt: self.base),
                        self.dto(3, state: "closed", mergedAt: nil),
                    ],
                    nextCursor: nil
                )
            ])
        }

        let all = try await LoadRepoPulls(source: makeSource()).load(fullName: "a/b", state: .all)
        #expect(all.items.map(\.number) == [1, 2])

        let open = try await LoadRepoPulls(source: makeSource()).load(fullName: "a/b", state: .open)
        #expect(open.items.map(\.number) == [1])

        let closed = try await LoadRepoPulls(source: makeSource()).load(fullName: "a/b", state: .closed)
        #expect(closed.items.map(\.number) == [2])
    }

    // MARK: - 切片 7：§4.4 分区三（仓库详情 PR 段，决策 #61）

    /// 造一行"两段都有"的 PR，省掉每个断言里重复五个参数。
    private func row(
        authorLogin: String? = "reviewer-a",
        updatedAt: Date? = nil
    ) -> PullRow {
        PullRow(
            number: 57,
            title: "标题",
            state: .open,
            headRef: "feature/repo-hub",
            baseRef: "main",
            authorLogin: authorLogin,
            updatedAt: updatedAt ?? base
        )
    }

    @Test("⚠️ 卡片第三行：`{作者} 更新于 {时间}`（原型 `05-repo.js:140` 逐字）")
    func updateLineMatchesPrototype() {
        #expect(row().updateLine(now: base.addingTimeInterval(7_200)) == "reviewer-a 更新于 2 小时前")
    }

    @Test("⚠️ 拿不到作者 ⇒ **只去掉名字那一截**（时间是真的，整句不说更亏）")
    func updateLineWithoutAuthorKeepsTheTime() {
        #expect(row(authorLogin: nil).updateLine(now: base.addingTimeInterval(7_200))
                == "更新于 2 小时前")
        // 空串与 `nil` 同一种处置 —— 不然会拼出 ` 更新于 …`（前面多一个空格）。
        #expect(row(authorLogin: "").updateLine(now: base.addingTimeInterval(7_200))
                == "更新于 2 小时前")
    }

    @Test("⚠️ 拿不到更新时间 ⇒ **整行返回 `nil`**（不画那一行，而不是画一行空的）")
    func updateLineIsNilWithoutUpdatedAt() {
        let noTime = PullRow(
            number: 57, title: "标题", state: .open,
            headRef: "feature/repo-hub", baseRef: "main",
            authorLogin: "reviewer-a", updatedAt: nil
        )

        // 空串会被渲染成**一行空白**（高度还在）—— "没有这一行"与"有一行空的"在屏幕上不同。
        #expect(noTime.updateLine(now: base) == nil)
    }

    @Test("⚠️ 探索页那行 `metaLabel` **一点都不受影响** —— 仍然不含作者、不含时间（PRD §4.15）")
    func metaLabelStaysForTheExplorePage() {
        let line = row().metaLabel

        #expect(line == "#57 · feature/repo-hub → main")
        #expect(!line.contains("reviewer-a"))
        #expect(!line.contains("更新于"))
    }

    @Test("两个字段真的从 DTO 带过来了（列表端点**返回** `updated_at` —— 与增删统计不同）")
    func authorAndUpdatedAtAreMapped() async throws {
        let source = ScriptedPullsSource(pages: [
            Page(items: [dto(1, author: "reviewer-a", updatedAt: base)], nextCursor: nil)
        ])

        let page = try await LoadRepoPulls(source: source).load(fullName: "a/b", state: .open)

        #expect(page.items.first?.authorLogin == "reviewer-a")
        #expect(page.items.first?.updatedAt == base)
    }

    @Test("两个字段都可空 ⇒ 服务端不给时行照样建得出来")
    func optionalFieldsSurviveMissingValues() async throws {
        let source = ScriptedPullsSource(pages: [Page(items: [dto(1)], nextCursor: nil)])

        let page = try await LoadRepoPulls(source: source).load(fullName: "a/b", state: .open)

        #expect(page.items.first?.authorLogin == nil)
        #expect(page.items.first?.updatedAt == nil)
    }

    @Test("§4.4 分区三分段条：`开放 (N)` / `已合并`（原型 `05-repo.js:132-133` 逐字）")
    func sectionSegmentsMatchPrototype() {
        #expect(RepoPullsSectionCopy.openSegment(loadedCount: 5, hasMore: false) == "开放 (5)")
        #expect(RepoPullsSectionCopy.openSegment(loadedCount: 30, hasMore: true) == "开放 (30+)")
        #expect(RepoPullsSectionCopy.mergedSegment == "已合并")
        #expect(!RepoPullsSectionCopy.mergedSegment.contains("("))
    }

    @Test("⚠️ PR 段的计数与 Issues 那两页**是同一条规则**（`N` 不重复实现一遍）")
    func sectionCountSharesTheSameRule() {
        for (loaded, more) in [(0, false), (5, false), (30, true), (-3, false)] {
            #expect(
                RepoPullsSectionCopy.openSegment(loadedCount: loaded, hasMore: more)
                    == "开放 (\(OpenIssueIndicator.countLabel(loadedCount: loaded, hasMore: more)))"
            )
        }
    }

    @Test("⚠️ 这一档**还没加载过**时只写 `开放`，不写 `开放 (0)`（加载中 ≠ 没有数据）")
    func openSegmentOmitsCountWhenNotLoadedYet() {
        #expect(RepoPullsSectionCopy.openSegment(loadedCount: nil, hasMore: false) == "开放")
        #expect(RepoPullsSectionCopy.openSegmentTitle == "开放")
        #expect(RepoPullsSectionCopy.openSegment(loadedCount: 0, hasMore: false) == "开放 (0)")
    }

    @Test("⚠️ 两档空态**各说各的**，也不与探索页那一句串用（§4.4 分区三 vs §4.15）")
    func sectionEmptyCopyIsPerSegment() {
        #expect(RepoPullsSectionCopy.emptyOpenTitle == "暂无开放的 Pull Request")
        #expect(RepoPullsSectionCopy.emptyOpenHint == "这个仓库当前没有开放中的 Pull Request")
        #expect(RepoPullsSectionCopy.emptyMergedTitle == "暂无已合并的 Pull Request")
        #expect(RepoPullsSectionCopy.emptyMergedHint == "这个仓库还没有已合并的 Pull Request")

        // 探索页说的是"一个 PR 都没有"（那一页开放 + 已合并混排）；这一页的档位是分开的，
        // 说"没有 PR"会把"已合并的有一堆"也一起否掉。
        #expect(RepoPullsSectionCopy.emptyOpenTitle != PullListIndicator.emptyTitle)
        #expect(RepoPullsSectionCopy.emptyMergedTitle != PullListIndicator.emptyTitle)
        #expect(RepoPullsSectionCopy.emptyOpenTitle != RepoPullsSectionCopy.emptyMergedTitle)

        // 两档的引导行都不是标题的复述。
        #expect(!RepoPullsSectionCopy.emptyOpenHint.contains(RepoPullsSectionCopy.emptyOpenTitle))
        #expect(!RepoPullsSectionCopy.emptyMergedHint.contains(RepoPullsSectionCopy.emptyMergedTitle))
    }

    @Test("⚠️ 「已合并」档的引导行说「还没有」而不是「当前没有」（只增不减的集合）")
    func mergedEmptyHintDoesNotImplyItChanges() {
        #expect(!RepoPullsSectionCopy.emptyMergedHint.contains("当前"))
        #expect(RepoPullsSectionCopy.emptyMergedHint.contains("还没有"))
    }
}
