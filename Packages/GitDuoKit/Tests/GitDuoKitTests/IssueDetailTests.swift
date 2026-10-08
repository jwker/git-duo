import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// Issue 详情：**两次请求可分别失败** · 头部文案 · 评论发送（PRD §4.9、TECH_SPEC §9.8、决策 #57）。
///
/// ## 这组断言守的三件事，出错时都"看起来正常"
///
/// 1. **评论拉失败不能让正文也消失** —— 这是决策 #57（两次 REST 而非一次 GraphQL 聚合）
///    的**全部要点**。把两次请求的失败合并成一个，表现是"网络抖一下，整个 Issue 打不开"，
///    而用户本来可以照常读到正文。
/// 2. **"评论重试"只重取评论** —— 重取详情会让整页闪一次骨架屏，
///    而用户点的是评论区的"重试"。
/// 3. **已关闭但拿不到关闭时间时不许编时间** —— 拼出 `已于  关闭`
///    比少说一句话更糟。
@Suite("Issue 详情 · 两次请求 / 头部文案 / 评论发送")
struct IssueDetailTests {

    private let base = Date(timeIntervalSince1970: 1_786_000_000)

    // MARK: - 数据源替身

    /// 脚本化的详情端点。详情与评论**各自独立**地成功或失败 ——
    /// 这是本组测试的核心形状：两边共用一个"失败开关"就测不出"评论失败不拖垮正文"。
    private actor ScriptedDetailSource: IssueDetailDataSource {

        private let detailResult: Result<IssueDetailDTO, any Error>
        private let commentResult: Result<Page<IssueCommentDTO>, any Error>

        private(set) var detailCalls = 0
        private(set) var commentCalls = 0
        private(set) var commentPerPages: [Int] = []
        private(set) var commentCursors: [URL?] = []

        init(
            detail: Result<IssueDetailDTO, any Error>,
            comments: Result<Page<IssueCommentDTO>, any Error> = .success(
                Page(items: [], nextCursor: nil)
            )
        ) {
            self.detailResult = detail
            self.commentResult = comments
        }

        func issue(owner: String, repo: String, number: Int) async throws -> IssueDetailDTO {
            detailCalls += 1
            return try detailResult.get()
        }

        func issueComments(
            owner: String,
            repo: String,
            number: Int,
            perPage: Int,
            cursor: URL?
        ) async throws -> Page<IssueCommentDTO> {
            commentCalls += 1
            commentPerPages.append(perPage)
            commentCursors.append(cursor)
            return try commentResult.get()
        }
    }

    /// 一个**不是** `GitHubError` 的抛出，用来验证兜底那一档。
    private struct Boom: Error {}

    private func detailDTO(
        number: Int = 42,
        title: String = "真机上 session.start() 返回 false 后状态没有回退",
        state: String = "open",
        body: String? = "建议补上返回值检查。",
        author: String? = "reviewer-a",
        closedAt: Date? = nil
    ) -> IssueDetailDTO {
        IssueDetailDTO(
            number: number,
            title: title,
            state: state,
            body: body,
            user: author.map(AuthorDTO.init(login:)),
            createdAt: base,
            closedAt: closedAt
        )
    }

    private func commentDTO(
        id: Int,
        body: String = "已确认，修复在 feature/auth-fix 分支。",
        author: String? = "you",
        createdAt: Date? = nil
    ) -> IssueCommentDTO {
        IssueCommentDTO(
            id: id,
            body: body,
            user: author.map(AuthorDTO.init(login:)),
            createdAt: createdAt ?? base
        )
    }

    // MARK: - 头部文案

    @Test("开放 ⇒ `该 Issue 仍然开放`（原型逐字）")
    func openHeadNote() {
        let detail = IssueDetail(number: 1, title: "t", isOpen: true, createdAt: base)
        #expect(detail.headNote(now: base) == "该 Issue 仍然开放")
    }

    @Test("已关闭 ⇒ `已于 3 天前关闭`（PRD §4.9 的写法）")
    func closedHeadNote() {
        let closedAt = base.addingTimeInterval(-3 * 86_400)
        let detail = IssueDetail(
            number: 1, title: "t", isOpen: false, createdAt: base, closedAt: closedAt
        )
        #expect(detail.headNote(now: base) == "已于 3 天前关闭")
    }

    @Test("⚠️ 已关闭但**没有关闭时间** ⇒ 只说 `已关闭`，不拼出 `已于  关闭`")
    func closedWithoutTimestampDoesNotInventATime() {
        let detail = IssueDetail(number: 1, title: "t", isOpen: false, createdAt: base)
        let note = detail.headNote(now: base)
        #expect(note == "已关闭")
        #expect(!note.contains("已于"))
    }

    @Test("头部元信息逐字：`#42 · my-git/gitduo · 由 reviewer-a 创建于 3 天前`")
    func metaLabelMatchesPrototype() {
        let createdAt = base.addingTimeInterval(-3 * 86_400)
        let detail = IssueDetail(
            number: 42, title: "t", isOpen: true, authorLogin: "reviewer-a", createdAt: createdAt
        )
        #expect(
            detail.metaLabel(fullName: "my-git/gitduo", now: base)
                == "#42 · my-git/gitduo · 由 reviewer-a 创建于 3 天前"
        )
    }

    @Test("⚠️ 作者为 `nil` ⇒ **整段去掉**（不拼出 `由  创建于 …`）")
    func metaLabelDropsMissingAuthor() {
        let detail = IssueDetail(number: 42, title: "t", isOpen: true, createdAt: base)
        let meta = detail.metaLabel(fullName: "a/b", now: base)
        #expect(meta == "#42 · a/b")
        #expect(!meta.contains("创建于"))
    }

    @Test("`hasBody`：`nil` / 空串 / 只有空白 都**不出气泡**，有内容才出")
    func hasBodyTreatsBlankAsEmpty() {
        func make(_ body: String?) -> IssueDetail {
            IssueDetail(number: 1, title: "t", isOpen: true, body: body, createdAt: base)
        }
        #expect(make(nil).hasBody == false)
        #expect(make("").hasBody == false)
        #expect(make("  \n\t ").hasBody == false)
        #expect(make("正文").hasBody == true)
    }

    @Test("读屏状态词与列表同一套词")
    func stateLabel() {
        let open = IssueDetail(number: 1, title: "t", isOpen: true, createdAt: base)
        let closed = IssueDetail(number: 1, title: "t", isOpen: false, createdAt: base)
        #expect(open.stateLabel == "开放")
        #expect(closed.stateLabel == "已关闭")
    }

    // MARK: - 两次请求的失败后果不同（决策 #57 的要点）

    @Test("⚠️ **评论失败 ⇒ 正文照常拿到**，只有评论区是 `.failed`")
    func commentFailureDoesNotKillThePage() async throws {
        let source = ScriptedDetailSource(
            detail: .success(detailDTO()),
            comments: .failure(GitHubError.transport(URLError(.notConnectedToInternet)))
        )

        let snapshot = try await LoadIssueDetail(source: source).load(fullName: "a/b", number: 42)

        #expect(snapshot.detail.number == 42)
        #expect(snapshot.detail.title.contains("session.start()"))
        guard case .failed(let error) = snapshot.comments else {
            Issue.record("评论失败时应当折叠成 .failed，而不是抛错或给空数组 —— 实际：\(snapshot.comments)")
            return
        }
        #expect(error == .transport(URLError(.notConnectedToInternet)))
    }

    @Test("⚠️ **详情失败 ⇒ 抛错，并且一次评论请求都没发**")
    func detailFailureSkipsCommentFetch() async throws {
        let source = ScriptedDetailSource(
            detail: .failure(GitHubError.notFound),
            comments: .success(Page(items: [commentDTO(id: 1)], nextCursor: nil))
        )

        var caught = false
        do {
            _ = try await LoadIssueDetail(source: source).load(fullName: "a/b", number: 42)
        } catch let error as GitHubError {
            #expect(error == .notFound)
            caught = true
        }

        #expect(caught)
        #expect(
            await source.commentCalls == 0,
            "详情没拿到就不该去拉评论 —— 那个 Issue 根本不存在，评论那次请求纯属浪费"
        )
    }

    @Test("两条都成功 ⇒ 评论是 `.loaded`，条数与游标都在")
    func bothSucceed() async throws {
        let next = URL(string: "https://api.github.com/repos/a/b/issues/42/comments?page=2")!
        let source = ScriptedDetailSource(
            detail: .success(detailDTO()),
            comments: .success(Page(items: [commentDTO(id: 1), commentDTO(id: 2)], nextCursor: next))
        )

        let snapshot = try await LoadIssueDetail(source: source).load(fullName: "a/b", number: 42)

        let page = try #require(snapshot.comments.value)
        #expect(page.items.map(\.id) == [1, 2])
        #expect(page.items.count == 2)
        // ⚠️ 一页取 100 条、还有下一页时 `items.count` 只是**下界** —— 游标与标志不能丢。
        #expect(page.hasMore)
        #expect(page.nextCursor == next)
    }

    @Test("评论页大小是 **100**、首页游标是 `nil`（写成 30 会让「点进来只看到一半讨论」）")
    func commentRequestShape() async throws {
        let source = ScriptedDetailSource(detail: .success(detailDTO()))

        _ = try await LoadIssueDetail(source: source).load(fullName: "a/b", number: 42)

        #expect(await source.commentPerPages == [100])
        #expect(await source.commentCursors == [nil])
        #expect(LoadIssueDetail.commentPageSize == 100)
    }

    @Test("⚠️ **评论重试只重取评论** —— 详情只被问过一次")
    func commentsRetryDoesNotRefetchDetail() async throws {
        let source = ScriptedDetailSource(
            detail: .success(detailDTO()),
            comments: .failure(GitHubError.transport(URLError(.timedOut)))
        )
        let loader = LoadIssueDetail(source: source)

        _ = try await loader.load(fullName: "a/b", number: 42)
        _ = await loader.comments(fullName: "a/b", number: 42)

        #expect(await source.detailCalls == 1, "重试评论不该重新拉详情 —— 那会让整页闪一次骨架屏")
        #expect(await source.commentCalls == 2)
    }

    @Test("⚠️ 评论重试**不抛错**：失败折进 `.failed`（它是区域内状态，不是整页开天窗）")
    func commentsRetryFoldsFailure() async throws {
        let source = ScriptedDetailSource(
            detail: .success(detailDTO()),
            comments: .failure(GitHubError.rateLimited(resetAt: base, isSecondary: false))
        )

        let state = await LoadIssueDetail(source: source).comments(fullName: "a/b", number: 42)

        #expect(state.error == .rateLimited(resetAt: base, isSecondary: false))
        #expect(state.value == nil)
    }

    @Test("⚠️ 抛出的**不是** `GitHubError` ⇒ 折进未归类那一档，不谎称网络问题")
    func nonGitHubErrorFoldsToUnclassified() async throws {
        let source = ScriptedDetailSource(detail: .success(detailDTO()), comments: .failure(Boom()))

        let state = await LoadIssueDetail(source: source).comments(fullName: "a/b", number: 42)

        #expect(state.error == .serverError(status: 0), "折成 .transport 会给出「检查网络」的错误引导")
    }

    @Test("`fullName` 形状不对 ⇒ 重试评论折进未归类档（**不是** `notFound`）")
    func malformedFullNameInRetryIsNotReportedAsMissing() async throws {
        let source = ScriptedDetailSource(detail: .success(detailDTO()))

        let state = await LoadIssueDetail(source: source).comments(fullName: "noSlash", number: 42)

        #expect(state.error == .serverError(status: 0))
        #expect(await source.commentCalls == 0)
    }

    @Test(
        "`load` 的 `fullName` 不是 `owner/name` 形状 ⇒ 抛错（与其余入口同一条契约）",
        arguments: ["noSlash", "a/b/c", "/name", "owner/", ""]
    )
    func malformedFullNameThrows(_ fullName: String) async throws {
        let source = ScriptedDetailSource(detail: .success(detailDTO()))

        var threw = false
        do {
            _ = try await LoadIssueDetail(source: source).load(fullName: fullName, number: 42)
        } catch let error as RepositoryMappingError {
            #expect(error == .malformedFullName(fullName))
            threw = true
        }
        #expect(threw, "`\(fullName)` 应当被拒绝")
    }

    @Test("编号原样传给端点（传错会打开别人的 Issue）")
    func numberIsForwarded() async throws {
        let source = ScriptedDetailSource(detail: .success(detailDTO(number: 7)))

        let snapshot = try await LoadIssueDetail(source: source).load(fullName: "a/b", number: 7)

        #expect(snapshot.detail.number == 7)
    }

    @Test("`state == \"closed\"` ⇒ `isOpen == false`（不按「我们请求的是开放」写死）")
    func closedStateIsReflected() async throws {
        let source = ScriptedDetailSource(
            detail: .success(detailDTO(state: "closed", closedAt: base))
        )

        let snapshot = try await LoadIssueDetail(source: source).load(fullName: "a/b", number: 42)

        #expect(snapshot.detail.isOpen == false)
        #expect(snapshot.detail.closedAt == base)
    }

    // MARK: - 评论模型

    @Test("⚠️ 作者为 `nil` ⇒ `已注销账号`（**不写「未知用户」** —— 那听起来像一个真账号名）")
    func deletedAuthorHasAHonestName() {
        let comment = IssueComment(id: 1, body: "b", createdAt: base)
        #expect(comment.displayAuthor == "已注销账号")
        #expect(comment.displayAuthor != "未知用户")
    }

    // MARK: - 发送

    @Test("`canSend`：只有空白 / 换行 视为空（`!body.isEmpty` 会放它过去）")
    func canSendRejectsBlank() {
        #expect(PostIssueComment.canSend("") == false)
        #expect(PostIssueComment.canSend("   ") == false)
        #expect(PostIssueComment.canSend("\n\n\t ") == false)
        #expect(PostIssueComment.canSend("x") == true)
        #expect(PostIssueComment.canSend("  正文  ") == true)
    }

    @Test("⚠️ 正文**原样发出**（前导缩进在 Markdown 里有意义，裁掉会把代码块变成段落）")
    func bodyIsSentVerbatim() async throws {
        let source = CommentPostSpy()
        let body = "    这是缩进过的代码块\n\n第二段"

        _ = try await PostIssueComment(source: source).send(
            fullName: "a/b", number: 42, body: body
        )

        #expect(await source.bodies == [body], "发出的正文必须逐字等于用户写的")
    }

    @Test("返回的是**服务端回的那条评论**（id / 时间以服务端为准，不自造「刚刚」）")
    func returnsServerComment() async throws {
        let posted = commentDTO(id: 9, body: "服务端的正文", author: "me", createdAt: base)
        let source = CommentPostSpy(result: .success(posted))

        let comment = try await PostIssueComment(source: source).send(
            fullName: "a/b", number: 42, body: "本地写的"
        )

        #expect(comment.id == 9)
        #expect(comment.body == "服务端的正文")
        #expect(comment.authorLogin == "me")
        #expect(comment.createdAt == base)
    }

    @Test("`fullName` 形状不对 ⇒ 抛错，且一个请求都没发")
    func malformedFullNameSkipsTheRequest() async throws {
        let source = CommentPostSpy()
        var threw = false
        do {
            _ = try await PostIssueComment(source: source).send(
                fullName: "noSlash", number: 42, body: "x"
            )
        } catch is RepositoryMappingError {
            threw = true
        }
        #expect(threw)
        #expect(await source.calls == 0)
    }

    /// 发评论的替身。
    private actor CommentPostSpy: IssueCommentPosting {

        private let result: Result<IssueCommentDTO, any Error>
        private(set) var calls = 0
        private(set) var bodies: [String] = []
        private(set) var targets: [String] = []

        init(result: Result<IssueCommentDTO, any Error> = .success(
            IssueCommentDTO(id: 1, body: "b", createdAt: Date(timeIntervalSince1970: 0))
        )) {
            self.result = result
        }

        func createIssueComment(
            owner: String,
            repo: String,
            number: Int,
            body: String
        ) async throws -> IssueCommentDTO {
            calls += 1
            bodies.append(body)
            targets.append("\(owner)/\(repo)#\(number)")
            return try result.get()
        }
    }
}
