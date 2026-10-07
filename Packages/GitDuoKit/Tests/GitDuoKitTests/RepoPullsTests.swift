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

        init(pages: [Page<PullRequestDTO>]) { self.pages = pages }

        func pullRequests(owner: String, repo: String, cursor: URL?) async throws -> Page<PullRequestDTO> {
            cursors.append(cursor)
            return pages.count > 1 ? pages.removeFirst() : (pages.first ?? Page(items: [], nextCursor: nil))
        }
    }

    private func dto(
        _ number: Int,
        title: String = "标题",
        state: String = "open",
        mergedAt: Date? = nil,
        head: String = "feature/x",
        base baseRef: String = "main"
    ) -> PullRequestDTO {
        PullRequestDTO(
            number: number,
            title: title,
            state: state,
            mergedAt: mergedAt,
            head: .init(ref: head),
            base: .init(ref: baseRef)
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

        let page = try await LoadRepoPulls(source: source).load(fullName: "a/b")

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

        let page = try await LoadRepoPulls(source: source).load(fullName: "a/b")

        #expect(page.items.map(\.number) == [1, 2])
        #expect(!page.items.contains { $0.state == .closed },
                "被关闭未合并的 PR 只说明没人合，不是本列表要展示的贡献")
    }

    @Test("⚠️ 过滤**不能**顺手把已合并的一起滤掉（`state=open` 就会犯这个错）")
    func mergedSurvivesTheFilter() async throws {
        let source = ScriptedPullsSource(pages: [
            Page(items: [dto(1, state: "closed", mergedAt: base)], nextCursor: nil)
        ])

        let page = try await LoadRepoPulls(source: source).load(fullName: "a/b")

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

        let page = try await LoadRepoPulls(source: source).load(fullName: "a/b")

        #expect(page.items.isEmpty)
        #expect(page.nextCursor == next, "丢掉游标会让用户以为这个仓库一个 PR 都没有")
        #expect(page.hasMore)
    }

    @Test("续页把上一页的游标真的传下去了")
    func continuationPassesCursorThrough() async throws {
        let next = URL(string: "https://api.github.com/repos/a/b/pulls?page=2")!
        let source = ScriptedPullsSource(pages: [Page(items: [dto(1)], nextCursor: next)])
        let loader = LoadRepoPulls(source: source)

        _ = try await loader.load(fullName: "a/b")
        _ = try await loader.load(fullName: "a/b", cursor: next)

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
            _ = try await LoadRepoPulls(source: source).load(fullName: fullName)
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
}
