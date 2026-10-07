import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 探索 Issues 列表：**滤掉混进来的 PR** · 卡片文案 · 说明行计数（PRD §4.14、决策 #38）。
///
/// ## 这组断言守的三件事，出错时都"看起来正常"
///
/// 1. **`GET /issues` 会混入 PR** —— 不过滤的话列表里会夹着 PR 条目，而两类卡片
///    长得几乎一样（标题 + `#N`）。**一页 30 条里可能只有 9 个是 Issue**，
///    这是端点固有行为，不是缺数据。
/// 2. **计数是"已加载的非 PR 条目数"**，不是接口里那个把 PR 也算进去的
///    `open_issues_count` —— 用后者会让标题的数字与屏幕上的条数对不上，
///    而"数字对不上"会被读成"这个 App 数不准"。
/// 3. **原型没覆盖的情形不许编**：0 条评论不写那一段（原型数据里 0 评论也只写时间）、
///    作者为 `nil` 不拼出 `由 undefined 创建`。
@Suite("探索 Issues 列表 · 过滤 / 文案 / 计数")
struct RepoIssuesTests {

    private let base = Date(timeIntervalSince1970: 1_786_000_000)

    // MARK: - 数据源替身

    /// 脚本化的 Issues 端点：**原样返回**（含混进来的 PR）。
    ///
    /// 过滤是本包（领域层）的活，数据层故意不滤 —— 喂进去的必须带 PR，
    /// 否则这组测试只是在断言"没写过滤也不会坏"。
    private actor ScriptedIssuesSource: RepoIssuesDataSource {

        private var pages: [Page<IssueDTO>]
        private(set) var cursors: [URL?] = []
        private(set) var owners: [String] = []

        init(pages: [Page<IssueDTO>]) { self.pages = pages }

        func openIssues(owner: String, repo: String, cursor: URL?) async throws -> Page<IssueDTO> {
            owners.append("\(owner)/\(repo)")
            cursors.append(cursor)
            return pages.count > 1 ? pages.removeFirst() : (pages.first ?? Page(items: [], nextCursor: nil))
        }
    }

    private func dto(
        _ number: Int,
        title: String = "标题",
        state: String = "open",
        comments: Int = 0,
        author: String? = nil,
        isPullRequest: Bool = false
    ) -> IssueDTO {
        IssueDTO(
            number: number,
            title: title,
            state: state,
            comments: comments,
            createdAt: base,
            user: author.map(IssueDTO.Author.init(login:)),
            pullRequest: isPullRequest ? IssueDTO.PullRequestMarker() : nil
        )
    }

    // MARK: - 过滤

    @Test("⚠️ 混进来的 PR 被滤掉 —— 一页 3 条里 2 条是 PR，只剩 1 条 Issue")
    func pullRequestsAreFilteredOut() async throws {
        let source = ScriptedIssuesSource(pages: [
            Page(items: [
                dto(1, title: "真的是 Issue"),
                dto(2, title: "其实是 PR", isPullRequest: true),
                dto(3, title: "也是 PR", isPullRequest: true),
            ], nextCursor: nil)
        ])

        let page = try await LoadRepoIssues(source: source).load(fullName: "kuda/ui-craft")

        #expect(page.items.map(\.number) == [1])
        #expect(page.items.first?.title == "真的是 Issue")
    }

    @Test("⚠️ 游标与响应头**原样带走** —— 丢掉它等于让「加载更多」永远拿不到下一页")
    func cursorIsPreserved() async throws {
        let next = URL(string: "https://api.github.com/repos/a/b/issues?page=2")!
        let source = ScriptedIssuesSource(pages: [
            Page(items: [dto(1)], nextCursor: next)
        ])

        let page = try await LoadRepoIssues(source: source).load(fullName: "a/b")

        #expect(page.nextCursor == next)
        #expect(page.hasMore)
    }

    @Test("续页把上一页的游标真的传下去了（否则会永远翻回第 1 页）")
    func continuationPassesCursorThrough() async throws {
        let next = URL(string: "https://api.github.com/repos/a/b/issues?page=2")!
        let source = ScriptedIssuesSource(pages: [Page(items: [dto(1)], nextCursor: next)])
        let loader = LoadRepoIssues(source: source)

        _ = try await loader.load(fullName: "a/b")
        _ = try await loader.load(fullName: "a/b", cursor: next)

        #expect(await source.cursors == [nil, next])
    }

    @Test("仓库全名被拆成 owner / name 传到端点（拆错会请求到别人的仓库）")
    func fullNameIsSplit() async throws {
        let source = ScriptedIssuesSource(pages: [Page(items: [], nextCursor: nil)])

        _ = try await LoadRepoIssues(source: source).load(fullName: "rust-lang/rust")

        #expect(await source.owners == ["rust-lang/rust"])
    }

    @Test(
        "`fullName` 不是 `owner/name` 形状 ⇒ 抛错（与其余入口同一条契约）",
        arguments: ["noSlash", "a/b/c", "/name", "owner/", ""]
    )
    func malformedFullNameThrows(_ fullName: String) async throws {
        let source = ScriptedIssuesSource(pages: [])
        var threw = false
        do {
            _ = try await LoadRepoIssues(source: source).load(fullName: fullName)
        } catch let error as RepositoryMappingError {
            #expect(error == .malformedFullName(fullName))
            threw = true
        }
        #expect(threw, "`\(fullName)` 应当被拒绝")
    }

    // MARK: - 卡片副标题

    @Test("副标题逐字对齐原型：`#42 · 2 小时前 · 3 条评论 · 由 reviewer-a 创建`")
    func metaLabelMatchesPrototype() {
        let row = IssueRow(
            number: 42,
            title: "标题",
            isOpen: true,
            comments: 3,
            createdAt: base,
            authorLogin: "reviewer-a"
        )

        #expect(row.metaLabel(now: base.addingTimeInterval(7_200)) == "#42 · 2 小时前 · 3 条评论 · 由 reviewer-a 创建")
    }

    @Test("⚠️ 0 条评论 ⇒ **不写那一段**（原型的数据里 0 评论也只写时间）")
    func zeroCommentsOmitsTheSegment() {
        let row = IssueRow(number: 42, title: "标题", isOpen: true, comments: 0,
                           createdAt: base, authorLogin: "a")

        let label = row.metaLabel(now: base.addingTimeInterval(7_200))

        #expect(!label.contains("条评论"), "`0 条评论` 是噪声：没有评论与不知道有没有评论看起来一样")
        #expect(label == "#42 · 2 小时前 · 由 a 创建")
    }

    @Test("⚠️ 作者为 nil ⇒ **整段去掉**（原型那处会拼出 `由 undefined 创建`）")
    func nilAuthorDropsTheSegment() {
        let row = IssueRow(number: 42, title: "标题", isOpen: true, comments: 2,
                           createdAt: base, authorLogin: nil)

        let label = row.metaLabel(now: base.addingTimeInterval(7_200))

        #expect(label == "#42 · 2 小时前 · 2 条评论")
        #expect(!label.contains("undefined"))
        #expect(!label.contains("由 "))
    }

    @Test("作者是空串（不是 nil）也去掉那一段 —— 空串会拼出 `由  创建`")
    func emptyAuthorDropsTheSegment() {
        let row = IssueRow(number: 42, title: "标题", isOpen: true, comments: 0,
                           createdAt: base, authorLogin: "")

        // `now == createdAt` ⇒ 相对时间是「刚刚」（新建的 Issue 恰好是这个样子）。
        #expect(row.metaLabel(now: base) == "#42 · 刚刚")
    }

    @Test("状态词是给读屏用的 —— 图标本身不该是状态的唯一载体")
    func stateLabelIsReadable() {
        #expect(IssueRow(number: 1, title: "t", isOpen: true, comments: 0,
                         createdAt: base).stateLabel == "开放")
        #expect(IssueRow(number: 1, title: "t", isOpen: false, comments: 0,
                         createdAt: base).stateLabel == "已关闭")
    }

    @Test("`id` 用仓库内编号 —— 它同时是跳详情页的键")
    func idIsTheNumber() {
        #expect(IssueRow(number: 42, title: "t", isOpen: true, comments: 0,
                         createdAt: base).id == 42)
    }

    // MARK: - 说明行与计数

    @Test("说明行：`{仓库} · 开放 {N} 个`（PRD §4.14 结构一行）")
    func summaryLineMatchesPrototype() {
        #expect(OpenIssueIndicator.summaryLine(fullName: "kuda/ui-craft", loadedCount: 9, hasMore: false)
                == "kuda/ui-craft · 开放 9 个")
    }

    @Test("⚠️ 还有下一页 ⇒ 计数是 **`30+`**（下界，不是确数）")
    func countBecomesLowerBoundWhenMorePages() {
        #expect(OpenIssueIndicator.countLabel(loadedCount: 30, hasMore: true) == "30+")
        #expect(OpenIssueIndicator.summaryLine(fullName: "a/b", loadedCount: 30, hasMore: true)
                == "a/b · 开放 30+ 个")
    }

    @Test("⚠️ 计数**只数已加载的非 PR 条目**，且从不为负")
    func countIsNeverNegative() {
        #expect(OpenIssueIndicator.countLabel(loadedCount: 0, hasMore: false) == "0")
        #expect(OpenIssueIndicator.countLabel(loadedCount: 0, hasMore: true) == "0+")
        // 传负数只可能来自调用方的 bug；写成 `-3` 会直接印在屏幕上。
        #expect(OpenIssueIndicator.countLabel(loadedCount: -3, hasMore: false) == "0")
    }

    @Test("⚠️ 说明行**不含**原型那句 `· 只读演示数据`（那是演示标记，不是产品文案）")
    func summaryLineHasNoDemoMarker() {
        let line = OpenIssueIndicator.summaryLine(fullName: "a/b", loadedCount: 1, hasMore: false)
        #expect(!line.contains("演示"))
    }

    @Test("页脚与空态文案（PRD §4.14 / §7，2026-10-07 定）")
    func copyIsPinned() {
        #expect(OpenIssueIndicator.footer == "他人仓库：可评论参与讨论，关闭 Issue 需维护者权限")
        #expect(OpenIssueIndicator.emptyTitle == "暂无开放的 Issue")
        #expect(OpenIssueIndicator.emptyHint == "这个仓库当前没有开放中的 Issue")
    }

    @Test("⚠️ 空态的两行说的**不是同一件事**：标题是状态、引导行才是结论 —— 不许合并成一句")
    func emptyCopyIsNotOneSentence() {
        #expect(OpenIssueIndicator.emptyTitle != OpenIssueIndicator.emptyHint)
        #expect(!OpenIssueIndicator.emptyHint.contains(OpenIssueIndicator.emptyTitle))
    }
}
