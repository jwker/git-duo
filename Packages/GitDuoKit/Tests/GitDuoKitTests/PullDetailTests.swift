import Foundation
import GitHubAPI
import GitDuoCore
import Testing

@testable import GitDuoKit

/// PR 详情：**三档状态** · **评论与评审合成一条时间线** · 两分区懒加载 ·
/// **多文件 diff 边界**（PRD §4.11、TECH_SPEC §9.9、决策 #57 / #58 / #60）。
///
/// ## 这组断言守的五件事，出错时都"看起来正常"
///
/// 1. **`PENDING` 的评审不进时间线** —— 那是没提交的草稿，只有作者自己看得到。
/// 2. **两个来源的 `id` 会撞车** —— 键不带来源前缀会让 `ForEach` **少画一条**。
/// 3. **同刻要稳定** —— `sorted(by:)` 不保证稳定，不稳的表现是"列表在两次刷新之间抖动"。
/// 4. **`{N} 个文件` 用 `changedFiles`，不用这一页的条数** —— 两个都是"文件数"，
///    读错不会报错、只会显示一个偏小的数。
/// 5. **每个文件的 `patch` 是独立的一份 diff** —— 接成一份解析会把第二个文件的
///    hunk 算到第一个文件头上（本片的验证靶心，§11.2）。
@Suite("PR 详情 · 三档状态 / 时间线合并 / 懒加载分区 / 多文件 diff")
struct PullDetailTests {

    private let base = Date(timeIntervalSince1970: 1_786_000_000)

    /// `@Test(arguments:)` 里的表达式在**类型层面**求值 ⇒ 那里不能用实例属性 `base`，
    /// 得有一个静态的（这是写参数化测试时的固定坑）。
    private static let mergedStamp = Date(timeIntervalSince1970: 1_786_000_000)

    // MARK: - 数据源替身

    private actor ScriptedPullSource: PullDetailDataSource {

        private let detailResult: Result<PullDetailDTO, any Error>
        private let reviewResult: Result<Page<PullReviewDTO>, any Error>
        private let fileResult: Result<Page<PullFileDTO>, any Error>
        private let commitResult: Result<Page<CommitListItemDTO>, any Error>

        private(set) var detailCalls = 0
        private(set) var reviewCalls = 0
        private(set) var fileCalls = 0
        private(set) var commitCalls = 0

        init(
            detail: Result<PullDetailDTO, any Error>,
            reviews: Result<Page<PullReviewDTO>, any Error> = .success(
                Page(items: [], nextCursor: nil)
            ),
            files: Result<Page<PullFileDTO>, any Error> = .success(
                Page(items: [], nextCursor: nil)
            ),
            commits: Result<Page<CommitListItemDTO>, any Error> = .success(
                Page(items: [], nextCursor: nil)
            )
        ) {
            self.detailResult = detail
            self.reviewResult = reviews
            self.fileResult = files
            self.commitResult = commits
        }

        func pullRequest(owner: String, repo: String, number: Int) async throws -> PullDetailDTO {
            detailCalls += 1
            return try detailResult.get()
        }

        func pullReviews(
            owner: String, repo: String, number: Int, cursor: URL?
        ) async throws -> Page<PullReviewDTO> {
            reviewCalls += 1
            return try reviewResult.get()
        }

        func pullFiles(
            owner: String, repo: String, number: Int, cursor: URL?
        ) async throws -> Page<PullFileDTO> {
            fileCalls += 1
            return try fileResult.get()
        }

        func pullCommits(
            owner: String, repo: String, number: Int, cursor: URL?
        ) async throws -> Page<CommitListItemDTO> {
            commitCalls += 1
            return try commitResult.get()
        }
    }

    private actor ScriptedCommentSource: IssueCommentReading {

        private let result: Result<Page<IssueCommentDTO>, any Error>
        private(set) var calls = 0
        private(set) var perPages: [Int] = []

        init(result: Result<Page<IssueCommentDTO>, any Error> = .success(
            Page(items: [], nextCursor: nil)
        )) {
            self.result = result
        }

        func issueComments(
            owner: String, repo: String, number: Int, perPage: Int, cursor: URL?
        ) async throws -> Page<IssueCommentDTO> {
            calls += 1
            perPages.append(perPage)
            return try result.get()
        }
    }

    private struct Boom: Error {}

    // MARK: - 夹具

    private func pullDTO(
        number: Int = 57,
        title: String = "重构导航栈",
        state: String = "open",
        mergedAt: Date? = nil,
        head: String = "feature/repo-hub",
        base: String = "main",
        author: String? = "dev-j",
        updatedAt: Date? = nil,
        createdAt: Date? = nil,
        body: String? = nil,
        additions: Int = 842,
        deletions: Int = 156,
        changedFiles: Int = 12
    ) -> PullDetailDTO {
        PullDetailDTO(
            number: number,
            title: title,
            state: state,
            mergedAt: mergedAt,
            head: PullRefDTO(ref: head),
            base: PullRefDTO(ref: base),
            user: author.map(AuthorDTO.init(login:)),
            updatedAt: updatedAt,
            createdAt: createdAt,
            body: body,
            additions: additions,
            deletions: deletions,
            changedFiles: changedFiles
        )
    }

    private func commentDTO(
        id: Int, body: String = "评论", author: String? = "dev-j", createdAt: Date? = nil
    ) -> IssueCommentDTO {
        IssueCommentDTO(
            id: id,
            body: body,
            user: author.map(AuthorDTO.init(login:)),
            createdAt: createdAt ?? base
        )
    }

    /// ⚠️ `hasTimestamp: false` 才真的给出 `nil` —— 参数默认 `nil` + 内部回落 `base`
    /// 会让"没有时间的那一条"这条断言永远构造不出来（写测试时踩到的第一个坑）。
    private func reviewDTO(
        id: Int,
        state: String = "APPROVED",
        body: String? = "LGTM",
        author: String? = "dev-k",
        submittedAt: Date? = nil,
        hasTimestamp: Bool = true
    ) -> PullReviewDTO {
        PullReviewDTO(
            id: id,
            user: author.map(AuthorDTO.init(login:)),
            state: state,
            body: body,
            submittedAt: hasTimestamp ? (submittedAt ?? base) : nil
        )
    }

    private func makeLoader(
        pull: ScriptedPullSource,
        comments: ScriptedCommentSource = ScriptedCommentSource()
    ) -> LoadPullDetail {
        LoadPullDetail(detail: pull, comments: comments)
    }

    // MARK: - 三档状态

    @Test("开放 ⇒ `{作者} 请求合并到 {目标分支}`（原型逐字）")
    func openHeadNote() {
        let detail = PullDetail(
            number: 57, title: "t", state: .open, headRef: "feature/x", baseRef: "main",
            authorLogin: "dev-j", additions: 1, deletions: 1, changedFiles: 1
        )
        #expect(detail.headNote(now: base) == "dev-j 请求合并到 main")
    }

    @Test("已合并 ⇒ `已由 {作者} 合并进 {目标分支}`（**不是**「请求合并到」）")
    func mergedHeadNote() {
        let detail = PullDetail(
            number: 57, title: "t", state: .merged, headRef: "feature/x", baseRef: "main",
            authorLogin: "dev-j", additions: 1, deletions: 1, changedFiles: 1
        )
        #expect(detail.headNote(now: base) == "已由 dev-j 合并进 main")
    }

    @Test("已关闭 ⇒ `已关闭，未合并`（**不带任何变量** —— 照抄原型，不要「补全」）")
    func closedHeadNote() {
        let detail = PullDetail(
            number: 57, title: "t", state: .closed, headRef: "feature/x", baseRef: "main",
            authorLogin: "dev-j", additions: 1, deletions: 1, changedFiles: 1
        )
        #expect(detail.headNote(now: base) == "已关闭，未合并")
    }

    @Test("⚠️ 作者账号已删 ⇒ 三句里的名字用 `已注销账号`（不拼出 `已由  合并进 main`）")
    func deletedAuthorInHeadNote() {
        let detail = PullDetail(
            number: 57, title: "t", state: .merged, headRef: "feature/x", baseRef: "main",
            additions: 1, deletions: 1, changedFiles: 1
        )
        #expect(detail.headNote(now: base) == "已由 \(AuthorName.unknown) 合并进 main")
        #expect(!detail.headNote(now: base).contains("  "))
    }

    @Test("`state == \"closed\" + mergedAt` ⇒ `.merged`（三档判定只有一处）")
    func mergedStateComesFromMergedAt() {
        let detail = LoadPullDetailTestsFixtures.detail(
            number: 1, state: "closed", mergedAt: base
        )
        #expect(detail.state == .merged)
        // 另一半：同样是 closed 但没有 mergedAt ⇒ `.closed`
        let closed = LoadPullDetailTestsFixtures.detail(number: 1, state: "closed", mergedAt: nil)
        #expect(closed.state == .closed)
    }

    // MARK: - 头部元信息与统计

    @Test("分支流向两侧**有空格**：`feature/repo-hub → main`")
    func branchFlowHasSpaces() {
        let detail = LoadPullDetailTestsFixtures.detail(head: "feature/repo-hub", base: "main")
        #expect(detail.branchFlow == "feature/repo-hub → main")
    }

    @Test("头部元信息：`#57 · feature/repo-hub → main · 更新于 2 小时前`")
    func metaLabelMatchesPrototype() {
        let detail = LoadPullDetailTestsFixtures.detail(
            number: 57,
            head: "feature/repo-hub",
            base: "main",
            updatedAt: base.addingTimeInterval(-2 * 3_600)
        )
        #expect(detail.metaLabel(now: base) == "#57 · feature/repo-hub → main · 更新于 2 小时前")
    }

    @Test("⚠️ 拿不到 `updatedAt` ⇒ 整段去掉，不编时间")
    func metaLabelDropsMissingTime() {
        let detail = LoadPullDetailTestsFixtures.detail(number: 57, updatedAt: nil)
        let meta = detail.metaLabel(now: base)
        #expect(!meta.contains("更新于"))
        #expect(meta.hasPrefix("#57 · "))
    }

    @Test("⚠️ 增删统计的减号是 **U+2212 `−`**（不是 ASCII `-`，原型逐字）")
    func statsLabelUsesTheRightMinus() {
        let detail = LoadPullDetailTestsFixtures.detail(additions: 842, deletions: 156)
        #expect(detail.statsLabel == "+842 −156")
        #expect(detail.statsLabel.contains("\u{2212}"), "用的是 U+2212 减号")
        #expect(!detail.statsLabel.contains("-"))
        #expect(detail.filesSegmentTitle == "文件 +842 −156")
    }

    @Test("已合并信息条：`已由 {作者} 于 {时间} 合并进 {目标分支} · 讨论已锁定`")
    func mergedBannerMatchesPrototype() {
        let mergedAt = base.addingTimeInterval(-2 * 3_600)
        let detail = LoadPullDetailTestsFixtures.detail(
            state: "closed", mergedAt: mergedAt, base: "main", author: "dev-j"
        )
        #expect(
            detail.mergedBanner(now: base)
                == "已由 dev-j 于 2 小时前 合并进 main · 讨论已锁定"
        )
    }

    @Test("⚠️ 未合并 ⇒ **没有**信息条（`nil`，不是一句空串）")
    func noBannerWhenNotMerged() {
        let detail = LoadPullDetailTestsFixtures.detail(state: "open")
        #expect(detail.mergedBanner(now: base) == nil)
    }

    @Test("⚠️ 已合并但拿不到合并时间 ⇒ 去掉 `于 {时间}` 那一截，不拼出 `于  合并进`")
    func bannerWithoutTimestampDropsTheSegment() throws {
        // 状态是 merged 而 mergedAt 缺失：构造上与 `.merged` 的判据冲突，
        // 直接造模型（服务端理论上不会这么给，但"拿不到时间"这条规则要在）。
        let detail = PullDetail(
            number: 57, title: "t", state: .merged, headRef: "f", baseRef: "main",
            authorLogin: "dev-j", mergedAt: nil, additions: 1, deletions: 1, changedFiles: 1
        )
        let banner = try #require(detail.mergedBanner(now: base))
        #expect(banner == "已由 dev-j 合并进 main · 讨论已锁定")
        #expect(!banner.contains("于 "))
    }

    // MARK: - 操作区与输入区

    @Test("讨论已合并 ⇒ 锁上输入区（与自己的 / 他人的仓库无关）")
    func mergedLocksTheComposer() {
        #expect(LoadPullDetailTestsFixtures.detail(state: "open").canComment)
        #expect(LoadPullDetailTestsFixtures.detail(state: "closed").canComment)
        #expect(
            !LoadPullDetailTestsFixtures.detail(state: "closed", mergedAt: base).canComment,
            "只要合并了就锁 —— 原型那个条件没有别的分支"
        )
    }

    @Test(
        "操作区四档：他人仓库 ⇒ 提示；自己的 + 开放 ⇒ 合并/关闭；自己的 + 关闭 ⇒ 重开；自己的 + 已合并 ⇒ 无按钮",
        arguments: [
            (readOnly: true, state: "open", mergedAt: nil as Date?, expected: PullOperationAvailability.readOnly),
            (readOnly: true, state: "closed", mergedAt: Self.mergedStamp, expected: PullOperationAvailability.readOnly),
            (readOnly: false, state: "open", mergedAt: nil, expected: PullOperationAvailability.mergeAndClose),
            (readOnly: false, state: "closed", mergedAt: nil, expected: PullOperationAvailability.reopen),
            (readOnly: false, state: "closed", mergedAt: Self.mergedStamp, expected: PullOperationAvailability.noOperations),
        ]
    )
    func operationAvailability(
        readOnly: Bool,
        state: String,
        mergedAt: Date?,
        expected: PullOperationAvailability
    ) {
        let detail = LoadPullDetailTestsFixtures.detail(state: state, mergedAt: mergedAt)
        #expect(detail.operationAvailability(readOnly: readOnly) == expected)
    }

    @Test("⚠️ `readOnly` **先判** —— 他人仓库的开放 PR 不许长出合并按钮")
    func readOnlyBeatsOpenState() {
        #expect(
            PullOperationAvailability.decide(readOnly: true, state: .open) == .readOnly,
            "顺序反了会让他人仓库的开放 PR 出现「合并 Pull Request」"
        )
    }

    // MARK: - 时间线合并（决策 #60）

    @Test("评论与评审合成**一条按时间升序**的流")
    func conversationIsMergedInTimeOrder() {
        let conversation = LoadPullDetail.conversation(
            comments: Page(
                items: [
                    commentDTO(id: 1, createdAt: base.addingTimeInterval(-3_600)),
                    commentDTO(id: 2, createdAt: base.addingTimeInterval(-600)),
                ],
                nextCursor: nil
            ),
            reviews: Page(
                items: [reviewDTO(id: 7, submittedAt: base.addingTimeInterval(-1_800))],
                nextCursor: nil
            )
        )

        #expect(conversation.count == 3)
        #expect(conversation.items.map(\.id) == ["c-1", "r-7", "c-2"])
    }

    @Test("⚠️ **`PENDING` 的评审不进时间线**（那是没提交的草稿，只有作者看得到）")
    func pendingReviewsAreExcluded() {
        let conversation = LoadPullDetail.conversation(
            comments: Page(items: [], nextCursor: nil),
            reviews: Page(
                items: [
                    reviewDTO(id: 1, state: "PENDING", hasTimestamp: false),
                    reviewDTO(id: 2, state: "APPROVED"),
                ],
                nextCursor: nil
            )
        )

        #expect(conversation.items.map(\.id) == ["r-2"])
    }

    @Test("⚠️ 两个来源的 id 会撞车 ⇒ 键**必须带来源前缀**（不带会让 `ForEach` 少画一条）")
    func idsAreNamespacedByOrigin() {
        let conversation = LoadPullDetail.conversation(
            comments: Page(items: [commentDTO(id: 7)], nextCursor: nil),
            reviews: Page(items: [reviewDTO(id: 7)], nextCursor: nil)
        )

        #expect(conversation.items.count == 2, "评论 #7 与评审 #7 都该在")
        #expect(Set(conversation.items.map(\.id)).count == 2, "两个键必须不同")
        #expect(conversation.items.map(\.id) == ["c-7", "r-7"])
    }

    @Test("⚠️ **同刻稳定**：时间一样时按「评论在前、评审在后」的入列顺序，不随机")
    func sameTimestampIsStable() {
        func build() -> [String] {
            LoadPullDetail.conversation(
                comments: Page(
                    items: [commentDTO(id: 1, createdAt: base), commentDTO(id: 2, createdAt: base)],
                    nextCursor: nil
                ),
                reviews: Page(
                    items: [reviewDTO(id: 3, submittedAt: base), reviewDTO(id: 4, submittedAt: base)],
                    nextCursor: nil
                )
            ).items.map(\.id)
        }

        #expect(build() == ["c-1", "c-2", "r-3", "r-4"])
        #expect(build() == build(), "同一份输入必须永远得到同一份输出（否则列表会无理由抖动）")
    }

    @Test("⚠️ 没有时间的评审**排在最后**（不插在中间冒充有序）")
    func timelessReviewGoesLast() {
        let conversation = LoadPullDetail.conversation(
            comments: Page(items: [commentDTO(id: 1, createdAt: base)], nextCursor: nil),
            reviews: Page(
                items: [reviewDTO(id: 9, state: "COMMENTED", hasTimestamp: false)],
                nextCursor: nil
            )
        )

        #expect(conversation.items.map(\.id) == ["c-1", "r-9"])
        #expect(conversation.items.last?.createdAt == nil)
    }

    @Test("⚠️ 「已批准」胶囊**只**给 `APPROVED`（另外四档 PRD 没给口径 ⇒ 不出胶囊）")
    func onlyApprovedGetsAPill() {
        let conversation = LoadPullDetail.conversation(
            comments: Page(items: [], nextCursor: nil),
            reviews: Page(
                items: [
                    reviewDTO(id: 1, state: "APPROVED", submittedAt: base),
                    reviewDTO(id: 2, state: "CHANGES_REQUESTED", submittedAt: base),
                    reviewDTO(id: 3, state: "COMMENTED", submittedAt: base),
                    reviewDTO(id: 4, state: "DISMISSED", submittedAt: base),
                ],
                nextCursor: nil
            )
        )

        let pills = conversation.items.map(\.approvalPill)
        #expect(pills == ["已批准", nil, nil, nil])
    }

    @Test("评论不会带胶囊（胶囊来自评审，不是评论）")
    func commentsNeverGetPills() {
        let conversation = LoadPullDetail.conversation(
            comments: Page(items: [commentDTO(id: 1)], nextCursor: nil),
            reviews: Page(items: [], nextCursor: nil)
        )
        #expect(conversation.items.first?.approvalPill == nil)
        #expect(conversation.items.first?.origin == .comment)
    }

    @Test("未知的评审 `state` ⇒ `.unknown`，**仍然进时间线**（不因一个取值让整段讨论消失）")
    func unknownReviewStateStillShows() {
        let conversation = LoadPullDetail.conversation(
            comments: Page(items: [], nextCursor: nil),
            reviews: Page(items: [reviewDTO(id: 1, state: "SOMETHING_NEW")], nextCursor: nil)
        )
        #expect(conversation.items.count == 1)
        #expect(conversation.items.first?.origin == .review(.unknown))
        #expect(conversation.items.first?.approvalPill == nil)
    }

    @Test("`hasMore` = 两条流的**或**（合并后没有单一游标可用）")
    func hasMoreIsTheOr() {
        let next = URL(string: "https://api.github.com/x?page=2")!
        let onlyComments = LoadPullDetail.conversation(
            comments: Page(items: [], nextCursor: next),
            reviews: Page(items: [], nextCursor: nil)
        )
        #expect(onlyComments.hasMore)

        let onlyReviews = LoadPullDetail.conversation(
            comments: Page(items: [], nextCursor: nil),
            reviews: Page(items: [], nextCursor: next)
        )
        #expect(onlyReviews.hasMore)

        let neither = LoadPullDetail.conversation(
            comments: Page(items: [], nextCursor: nil),
            reviews: Page(items: [], nextCursor: nil)
        )
        #expect(!neither.hasMore)
    }

    @Test("只有点批准、不写话的评审：没有正文（气泡上只画作者 + 胶囊）")
    func approvalWithoutBodyHasNoBody() throws {
        let conversation = LoadPullDetail.conversation(
            comments: Page(items: [], nextCursor: nil),
            reviews: Page(items: [reviewDTO(id: 1, body: nil)], nextCursor: nil)
        )
        let item = try #require(conversation.items.first)
        #expect(item.hasBody == false)
        #expect(item.approvalPill == "已批准")
    }

    // MARK: - 正文块与时间（切片 7.4：视图直接喂给 `MarkdownBody` / `CommentBubble`）

    @Test("⚠️ 正文的块**在 `init` 里解析好**（`body` 与 `bodyBlocks` 不可能不一致）")
    func bodyBlocksAreParsedAtInit() throws {
        let item = PullTimelineItem(
            id: "c-1",
            origin: .comment,
            body: "**加粗** 与 `code`",
            createdAt: base
        )

        #expect(item.bodyBlocks == MarkdownDocument("**加粗** 与 `code`").blocks)
        // 两条"解析没做"的形态都要被挡住：它们不会崩，只会渲染出一条空气泡。
        #expect(!item.bodyBlocks.isEmpty)
        #expect(item.hasBody)
    }

    @Test("⚠️ 没有正文的评审 ⇒ `bodyBlocks` 是空数组（视图画不画仍看 `hasBody`）")
    func missingBodyYieldsNoBlocks() {
        let item = PullTimelineItem(id: "r-1", origin: .review(.approved), body: nil, createdAt: base)

        #expect(item.bodyBlocks.isEmpty)
        #expect(item.hasBody == false)
    }

    @Test("""
        ⚠️ `hasBody` 与 `bodyBlocks` 是**两条判据** —— 纯空白的正文两边都为空数组，
        但"要不要画"只由 `hasBody` 说（产品判断），不由解析器的结果说
        """)
    func hasBodyIsNotTheSameQuestionAsBlocksIsEmpty() {
        // `MarkdownParser` 声明了"空行不产生块" ⇒ 纯空白给出的确实是空数组。
        // 但这两条仍然是两件事：`hasBody` 是"用户到底写没写"，
        // `bodyBlocks` 是"原文解析成了什么"。视图改看 `blocks.isEmpty`
        // 就把那条产品判断降级成了实现细节（`PullTimelineItem.bodyBlocks` 的说明）。
        let blank = PullTimelineItem(id: "c-1", origin: .comment, body: "  \n\t ", createdAt: base)

        #expect(blank.hasBody == false)
        #expect(blank.bodyBlocks.isEmpty)
        // 于是这一档**不能**走"有内容、只是解析结果为空"那条路 —— 不画就是不画。
        // ⚠️ 先把结果取出来再断言：`#expect` 的宏展开吃不下 `allSatisfy` 这种
        //    `rethrows` 调用 + keypath 的组合（会报"call can throw"）。
        let allBlocksEmpty = blank.bodyBlocks.allSatisfy(\.isEmpty)
        #expect(allBlocksEmpty)
    }

    @Test("⚠️ 评审可以**没有提交时间** ⇒ 气泡头部的时间是 `nil`（不是空串）")
    func reviewWithoutSubmittedAtHasNoTimeLabel() {
        let pendingless = PullTimelineItem(
            id: "r-1",
            origin: .review(.commented),
            body: "LGTM",
            createdAt: nil
        )
        #expect(pendingless.timeLabel(now: base) == nil)

        let timed = PullTimelineItem(
            id: "r-2",
            origin: .review(.commented),
            body: "LGTM",
            createdAt: base.addingTimeInterval(-3 * 86_400)
        )
        #expect(timed.timeLabel(now: base) == "3 天前")
    }

    @Test("评论一定有时间 ⇒ 时间串与 `RelativeTime` 同一套（不给评论单独造一套格式）")
    func commentTimeUsesTheSharedRelativeFormatter() {
        let stamp = base.addingTimeInterval(-3 * 86_400)
        let item = PullTimelineItem(id: "c-1", origin: .comment, body: "b", createdAt: stamp)

        #expect(item.timeLabel(now: base) == RelativeTime.string(from: stamp, now: base))
        #expect(item.timeLabel(now: base) == "3 天前")
    }

    @Test("`PullTimelineItem` 是 `Hashable`（去重与 `ForEach` 的键要它）")
    func timelineItemIsHashable() {
        let a = PullTimelineItem(id: "c-1", origin: .comment, body: "同一段", createdAt: base)
        let b = PullTimelineItem(id: "c-1", origin: .comment, body: "同一段", createdAt: base)
        let c = PullTimelineItem(id: "c-1", origin: .comment, body: "另一段", createdAt: base)

        #expect(a == b)
        // ⚠️ 改正文就应当是不相等的值 —— 合成 `Hashable` 会把 `bodyBlocks` 也算进去，
        //    这条断言保证"解析结果确实参与了比较"，而不是被某个 `==` 实现忽略掉。
        #expect(a != c)
        #expect(Set([a, b, c]).count == 2)
    }

    // MARK: - 进页取数（决策 #57 的同一套形状）

    @Test("`load` = 详情 + 对话；评论与评审**两条路都发了**，页大小 100")
    func loadFetchesDetailAndConversation() async throws {
        let pull = ScriptedPullSource(
            detail: .success(pullDTO()),
            reviews: .success(Page(items: [reviewDTO(id: 3)], nextCursor: nil))
        )
        let comments = ScriptedCommentSource(
            result: .success(Page(items: [commentDTO(id: 1)], nextCursor: nil))
        )

        let snapshot = try await makeLoader(pull: pull, comments: comments)
            .load(fullName: "a/b", number: 57)

        #expect(snapshot.detail.number == 57)
        #expect(await pull.reviewCalls == 1)
        #expect(await comments.calls == 1)
        #expect(await comments.perPages == [100])
        let conversation = try #require(snapshot.conversation.value)
        #expect(conversation.count == 2)
    }

    @Test("⚠️ **评论失败 ⇒ 详情照常拿到**，对话折成 `.failed`（决策 #57 的要点）")
    func commentFailureDoesNotKillThePage() async throws {
        let pull = ScriptedPullSource(detail: .success(pullDTO()))
        let comments = ScriptedCommentSource(
            result: .failure(GitHubError.transport(URLError(.notConnectedToInternet)))
        )

        let snapshot = try await makeLoader(pull: pull, comments: comments)
            .load(fullName: "a/b", number: 57)

        #expect(snapshot.detail.title == "重构导航栈")
        #expect(snapshot.conversation.error == .transport(URLError(.notConnectedToInternet)))
    }

    @Test("⚠️ **评审失败同样不拖垮头部**（两条路任一失败都折进同一档）")
    func reviewFailureDoesNotKillThePage() async throws {
        let pull = ScriptedPullSource(
            detail: .success(pullDTO()),
            reviews: .failure(GitHubError.notFound)
        )

        let snapshot = try await makeLoader(pull: pull).load(fullName: "a/b", number: 57)

        #expect(snapshot.detail.number == 57)
        #expect(snapshot.conversation.error == .notFound)
    }

    @Test("⚠️ **详情失败 ⇒ 抛错，并且一次评论 / 评审请求都没发**")
    func detailFailureSkipsTheRest() async throws {
        let pull = ScriptedPullSource(detail: .failure(GitHubError.notFound))
        let comments = ScriptedCommentSource()

        var threw = false
        do {
            _ = try await makeLoader(pull: pull, comments: comments)
                .load(fullName: "a/b", number: 57)
        } catch let error as GitHubError {
            #expect(error == .notFound)
            threw = true
        }

        #expect(threw)
        #expect(await pull.reviewCalls == 0)
        #expect(await comments.calls == 0)
    }

    @Test("对话重试**只重取对话**，详情只被问过一次")
    func conversationRetryDoesNotRefetchDetail() async throws {
        let pull = ScriptedPullSource(detail: .success(pullDTO()))
        let comments = ScriptedCommentSource(
            result: .failure(GitHubError.transport(URLError(.timedOut)))
        )
        let loader = makeLoader(pull: pull, comments: comments)

        _ = try await loader.load(fullName: "a/b", number: 57)
        _ = await loader.conversation(fullName: "a/b", number: 57)

        #expect(await pull.detailCalls == 1, "重试对话不该重新拉详情 —— 那会让整页闪一次骨架屏")
        #expect(await comments.calls == 2, "评论与评审**一起**重取（两条路合成一条流）")
        #expect(await pull.reviewCalls == 2)
    }

    @Test("⚠️ 非 `GitHubError` 的抛出 ⇒ 折进未归类那一档，不谎称网络问题")
    func nonGitHubErrorFoldsToUnclassified() async throws {
        let pull = ScriptedPullSource(detail: .success(pullDTO()))
        let comments = ScriptedCommentSource(result: .failure(Boom()))

        let state = await makeLoader(pull: pull, comments: comments)
            .conversation(fullName: "a/b", number: 57)

        #expect(state.error == .serverError(status: 0))
    }

    @Test(
        "`fullName` 不是 `owner/name` 形状 ⇒ 抛错（与其余入口同一条契约）",
        arguments: ["noSlash", "a/b/c", "/name", "owner/", ""]
    )
    func malformedFullNameThrows(_ fullName: String) async throws {
        let pull = ScriptedPullSource(detail: .success(pullDTO()))

        var threw = false
        do {
            _ = try await makeLoader(pull: pull).load(fullName: fullName, number: 57)
        } catch let error as RepositoryMappingError {
            #expect(error == .malformedFullName(fullName))
            threw = true
        }
        #expect(threw, "`\(fullName)` 应当被拒绝")
    }

    // MARK: - 两个懒加载分区

    @Test("Commits 分区：进分区才取，且**复用** `RepoCommitMapper.summary`（短 SHA 不做两套）")
    func commitsSegmentLoadsOnDemand() async throws {
        let pull = ScriptedPullSource(
            detail: .success(pullDTO()),
            commits: .success(
                Page(
                    items: [
                        CommitListItemDTO(
                            sha: "c881f0b1234567890",
                            commit: CommitInfoDTO(
                                message: "feat: star toggle animation\n\n第二段不进列表行",
                                authoredAt: base
                            ),
                            author: CommitUserDTO(login: "dev-j")
                        )
                    ],
                    nextCursor: nil
                )
            )
        )
        let loader = makeLoader(pull: pull)

        // 进页时**不该**去取 Commits —— 否则打开 PR 就先拉一页提交。
        _ = try await loader.load(fullName: "a/b", number: 57)
        #expect(await pull.commitCalls == 0)

        let state = await loader.commits(fullName: "a/b", number: 57)
        let page = try #require(state.value)
        #expect(await pull.commitCalls == 1)
        #expect(page.items.first?.authorLogin == "dev-j")
        // ⚠️ 列表行只留**首行** —— 整段塞进去会被省略号截在随机位置。
        #expect(page.items.first?.message == "feat: star toggle animation")
    }

    @Test("Commits 失败 ⇒ 折进 `.failed`（换一个分区不该让整页开天窗）")
    func commitsFailureFolds() async throws {
        let pull = ScriptedPullSource(
            detail: .success(pullDTO()),
            commits: .failure(GitHubError.rateLimited(resetAt: base, isSecondary: false))
        )

        let state = await makeLoader(pull: pull).commits(fullName: "a/b", number: 57)

        #expect(state.error == .rateLimited(resetAt: base, isSecondary: false))
    }

    @Test("⚠️ `{N} 个文件` 用 `changedFiles`，**不用这一页的条数**")
    func fileCountComesFromTheDetailNotThePage() async throws {
        // 详情说 12 个文件，而这一页只回了 2 条（端点分页）。
        let pull = ScriptedPullSource(
            detail: .success(pullDTO(changedFiles: 12)),
            files: .success(
                Page(
                    items: [
                        PullFileDTO(filename: "a.swift", additions: 1, deletions: 0),
                        PullFileDTO(filename: "b.swift", additions: 2, deletions: 3),
                    ],
                    nextCursor: URL(string: "https://api.github.com/x?page=2")!
                )
            )
        )
        let loader = makeLoader(pull: pull)

        let snapshot = try await loader.load(fullName: "a/b", number: 57)
        let state = await loader.files(fullName: "a/b", number: 57)
        let page = try #require(state.value)

        #expect(snapshot.detail.changedFiles == 12)
        #expect(PullCopy.filesHint(count: snapshot.detail.changedFiles) == "12 个文件 · 点击文件卡片展开 diff")
        #expect(page.items.count == 2, "这一页只有 2 条")
        #expect(page.hasMore, "游标不能丢 —— 否则「还有下一页」在代码里没有任何地方知道")
    }

    // MARK: - 多文件 diff 边界（§9.9 / §11.2，本片的验证靶心）

    /// 一个 PR 的 `files[]` 里，**每个文件是独立的一份 patch** ——
    /// 各自从自己的 `@@` 开始，之间**没有** `diff --git` 分隔行。
    ///
    /// ⚠️ 把它们的 `patch` 接成一份去解析，`UnifiedDiffParser.files(from:)` 会
    /// 找不到任何 `diff --git` ⇒ 认为这是**一个**文件的两段 hunk，
    /// 于是第二个文件的改动被算到第一个文件头上 —— 而屏幕上看起来完全正常
    /// （同一个卡片里多了一段 hunk，用户会以为那个文件真的改了两处）。
    @Test("⚠️ **每个文件的 patch 各自从头编号** —— 必须逐个文件解析（§9.9 的验证靶心）")
    func eachFilePatchIsParsedIndependently() async throws {
        let firstPatch = """
        @@ -12,7 +12,9 @@
                 var body: some View {
        -     TabView(selection: $selection) {
        +     TabView {
        """
        let secondPatch = """
        @@ -40,9 +40,14 @@
                 PaginatedList(items: store.repos) {
        -             Button { selection = repo } label: {
        +             NavigationLink(value: repo) {
        """

        let pull = ScriptedPullSource(
            detail: .success(pullDTO(changedFiles: 2)),
            files: .success(
                Page(
                    items: [
                        PullFileDTO(
                            filename: "GitDuo/App/AppTabs.swift",
                            additions: 46, deletions: 12,
                            status: "modified", patch: firstPatch
                        ),
                        PullFileDTO(
                            filename: "GitDuo/Features/Repos/RepoListView.swift",
                            additions: 301, deletions: 88,
                            status: "modified", patch: secondPatch
                        ),
                    ],
                    nextCursor: nil
                )
            )
        )

        let state = await makeLoader(pull: pull).files(fullName: "a/b", number: 57)
        let files = try #require(state.value).items

        #expect(files.count == 2)

        // ── 正确做法：逐个文件解析，各得一段、行号各归各的。
        let firstHunks = UnifiedDiffParser.hunks(from: files[0].patch)
        let secondHunks = UnifiedDiffParser.hunks(from: files[1].patch)
        #expect(firstHunks.count == 1)
        #expect(secondHunks.count == 1)
        #expect(firstHunks[0].newStart == 12)
        #expect(secondHunks[0].newStart == 40, "第二个文件从第 40 行开始，与第一个文件的 12 无关")

        // ── 错误做法的**证据**：接成一份之后它被当成同一个文件的两段 hunk。
        let concatenated = [files[0].patch, files[1].patch].compactMap { $0 }.joined(separator: "\n")
        let asOne = UnifiedDiffParser.files(from: concatenated)
        #expect(asOne.count == 1, "没有 `diff --git` 分隔 ⇒ 解析器只能认为这是**一个**文件")
        #expect(
            asOne[0].hunks.count == 2,
            "于是第二个文件的 hunk 会被算到第一个文件头上 —— 这正是必须逐文件解析的理由"
        )
    }

    @Test("⚠️ 两个文件都从第 1 行开始（各自新建）时更危险：合并解析会看成同一文件的两段")
    func twoNewFilesWithIdenticalLineNumbersStaySeparate() async throws {
        let patchA = "@@ -0,0 +1,5 @@\n+第一段\n"
        let patchB = "@@ -0,0 +1,3 @@\n+第二段\n"

        let pull = ScriptedPullSource(
            detail: .success(pullDTO(changedFiles: 2)),
            files: .success(
                Page(
                    items: [
                        PullFileDTO(filename: "a.swift", additions: 5, deletions: 0, status: "added", patch: patchA),
                        PullFileDTO(filename: "b.swift", additions: 3, deletions: 0, status: "added", patch: patchB),
                    ],
                    nextCursor: nil
                )
            )
        )

        let state = await makeLoader(pull: pull).files(fullName: "a/b", number: 57)
        let files = try #require(state.value).items

        #expect(UnifiedDiffParser.hunks(from: files[0].patch)[0].newCount == 5)
        #expect(UnifiedDiffParser.hunks(from: files[1].patch)[0].newCount == 3)

        // 合并解析：两段 hunk 都在同一个"文件"里，而它们的 newStart 都是 1
        // —— 解析器**不会**察觉这是两个文件（它没有那个信息）。
        let concatenated = [patchA, patchB].joined(separator: "\n")
        let asOne = UnifiedDiffParser.files(from: concatenated)
        #expect(asOne.count == 1)
        #expect(asOne[0].hunks.map(\.newStart) == [1, 1])
    }

    @Test("`patch` 为 `nil` 的文件（二进制 / 改动过大）照常出现在列表里")
    func filesWithoutPatchStillAppear() async throws {
        let pull = ScriptedPullSource(
            detail: .success(pullDTO(changedFiles: 1)),
            files: .success(
                Page(
                    items: [
                        PullFileDTO(filename: "logo.png", additions: 0, deletions: 0, status: "modified", patch: nil)
                    ],
                    nextCursor: nil
                )
            )
        )

        let state = await makeLoader(pull: pull).files(fullName: "a/b", number: 57)
        let file = try #require(state.value?.items.first)

        #expect(file.filename == "logo.png")
        #expect(file.patch == nil)
        // 二进制判定复用 `FileChange.isBinary` 的扩展名白名单（切片 6.1），不另立一套。
        #expect(file.isBinary)
    }

    @Test("文件分区的行模型与提交详情用的是**同一个** `FileChange`（同形不分叉）")
    func fileRowsReuseTheCommitModel() async throws {
        let pull = ScriptedPullSource(
            detail: .success(pullDTO(changedFiles: 1)),
            files: .success(
                Page(
                    items: [
                        PullFileDTO(
                            filename: "x.swift", additions: 1, deletions: 2,
                            status: "renamed", patch: "@@ -1 +1 @@\n-a\n+b"
                        )
                    ],
                    nextCursor: nil
                )
            )
        )

        let state = await makeLoader(pull: pull).files(fullName: "a/b", number: 57)
        let file = try #require(state.value?.items.first)

        #expect(file.status == .renamed)
        #expect(file.additions == 1)
        #expect(file.deletions == 2)
        #expect(file.id == "x.swift")
    }
}

/// 直接造 `PullDetail` 的小夹具（DTO → 模型那条路已在别处覆盖）。
private enum LoadPullDetailTestsFixtures {

    static func detail(
        number: Int = 57,
        title: String = "重构导航栈",
        state: String = "open",
        mergedAt: Date? = nil,
        head: String = "feature/repo-hub",
        base: String = "main",
        author: String? = "dev-j",
        updatedAt: Date? = nil,
        additions: Int = 842,
        deletions: Int = 156,
        changedFiles: Int = 12
    ) -> PullDetail {
        PullDetail(
            number: number,
            title: title,
            state: PullRequestState(state: state, mergedAt: mergedAt),
            headRef: head,
            baseRef: base,
            authorLogin: author,
            updatedAt: updatedAt,
            mergedAt: mergedAt,
            additions: additions,
            deletions: deletions,
            changedFiles: changedFiles
        )
    }
}

// MARK: - 合并成功后的本地状态

/// `PullDetail.markingMerged(at:)` —— **一件事的三处后果**（PRD §4.11 / §5.3、TECH_SPEC §9.9）。
///
/// ## 为什么这条规则值得单独一组断言
///
/// `PUT …/merge` 的响应体里**没有 PR 对象**，所以"合并之后界面变成什么样"
/// 完全由本仓说了算。它一次要动三处，而其中任何一处漏掉，屏幕上都看不出来：
///
/// | 漏了哪一处 | 屏幕上看起来 |
/// |---|---|
/// | `state` | 头部继续说「X 请求合并到 main」，而它已经合了 |
/// | `mergedAt` | 对话区顶部那条信息条少了 `于 {时间}` 那一截（不报错，只是少说一句） |
/// | 派生的 `canComment` | **刚合并完还能继续评论** |
///
/// 第三行正是"收成一条领域层规则"而不是"视图改两个字段"的理由 ——
/// 它不是一个字段，是 `state` 的派生值。
@Suite("PR 详情 · 合并成功后的本地状态自洽")
struct PullDetailMarkingMergedTests {

    /// 服务端当初给的 `updated_at`（用来钉住"这条路不改写它"）。
    private let serverUpdatedAt = Date(timeIntervalSince1970: 1_786_000_000)

    /// 客户端收到成功响应那一刻。
    private let mergedAt = Date(timeIntervalSince1970: 1_786_100_000)

    private func openPull(updatedAt: Date?) -> PullDetail {
        PullDetail(
            number: 57,
            title: "重构导航栈",
            state: .open,
            headRef: "feature/repo-hub",
            baseRef: "main",
            authorLogin: "dev-j",
            createdAt: Date(timeIntervalSince1970: 1_785_000_000),
            updatedAt: updatedAt,
            mergedAt: nil,
            body: "仓库详情升级为四分区枢纽。",
            additions: 842,
            deletions: 156,
            changedFiles: 12
        )
    }

    @Test("状态转 .merged，合并时间落在传入的那一刻")
    func stateBecomesMerged() {
        let marked = openPull(updatedAt: serverUpdatedAt).markingMerged(at: mergedAt)

        #expect(marked.state == .merged)
        #expect(marked.mergedAt == mergedAt)
    }

    @Test("⚠️ 讨论因此锁上 —— canComment 不是字段，是 state 的派生值")
    func discussionGetsLocked() {
        let before = openPull(updatedAt: serverUpdatedAt)
        let after = before.markingMerged(at: mergedAt)

        // 前提：合并之前它是能评论的（否则这条断言会"因为别的原因"成立）。
        #expect(before.canComment)
        #expect(after.canComment == false)
    }

    @Test("头部说明换成「已由 X 合并进 main」，并出现那条信息条")
    func headerAndBannerFollowTheState() {
        let after = openPull(updatedAt: serverUpdatedAt).markingMerged(at: mergedAt)

        // ⚠️ 与 `PullCopy.mergedNote` 对照，不照抄字面量 —— 同一句话有两处出处时，
        //    抄一次就多一处要跟着改。这里要钉的是"走了 `merged` 那一支"。
        #expect(after.headNote(now: mergedAt) == PullCopy.mergedNote(author: "dev-j", base: "main"))

        let banner = after.mergedBanner(now: mergedAt)
        #expect(banner != nil)
        #expect(banner?.contains("讨论已锁定") == true)
        #expect(banner?.contains("main") == true)
    }

    @Test("其余字段一个不动 —— 这条路只负责让状态自洽")
    func otherFieldsAreUntouched() {
        let before = openPull(updatedAt: serverUpdatedAt)
        let after = before.markingMerged(at: mergedAt)

        #expect(after.number == before.number)
        #expect(after.title == before.title)
        #expect(after.headRef == before.headRef)
        #expect(after.baseRef == before.baseRef)
        #expect(after.authorLogin == before.authorLogin)
        #expect(after.createdAt == before.createdAt)
        #expect(after.body == before.body)
        #expect(after.additions == before.additions)
        #expect(after.deletions == before.deletions)
        #expect(after.changedFiles == before.changedFiles)
        // 分区的第三格标题（`文件 +842 −156`）因此也不变。
        #expect(after.filesSegmentTitle == before.filesSegmentTitle)
    }

    @Test("⚠️ updatedAt **不**被改写 —— 不替服务端编它的时间")
    func serverUpdatedAtIsNotFabricated() {
        let after = openPull(updatedAt: serverUpdatedAt).markingMerged(at: mergedAt)

        #expect(after.updatedAt == serverUpdatedAt)
        // 也就是说"更新于"仍然说服务端的那个时刻，而不是"刚刚"。
        #expect(after.metaLabel(now: mergedAt).contains("更新于"))
    }

    @Test("服务端没给 updatedAt 时也不会凭空多出一个")
    func nilUpdatedAtStaysNil() {
        let after = openPull(updatedAt: nil).markingMerged(at: mergedAt)

        #expect(after.updatedAt == nil)
        // `metaLabel` 拿不到时间时整段去掉，不编一个（同 `PullCopy.metaLabel` 的口径）。
        #expect(!after.metaLabel(now: mergedAt).contains("更新于"))
    }

    @Test("幂等：连着合两次，结果与合一次相同")
    func markingTwiceIsStable() {
        let once = openPull(updatedAt: serverUpdatedAt).markingMerged(at: mergedAt)
        let twice = once.markingMerged(at: mergedAt)

        #expect(twice == once)
    }
}

// MARK: - 正文气泡的时间

/// `PullDetail.bodyTimeLabel(now:)` —— 正文气泡上那一小截时间（PRD §4.11、原型 `08-pr.js:33-39`）。
///
/// ## 为什么值得单独钉住
///
/// 详情对象上**有两个时间**（`createdAt` 与 `updatedAt`），而头部用的是后者
/// （`更新于 {时间}`，与 Issue 的 `创建于` 有意不同）。正文气泡要用**前者** ——
/// 选错的表现是"这段描述看起来是刚刚写的"（每次改标题都会变），
/// 而那看起来完全正常。
@Suite("PR 详情 · 正文气泡的时间")
struct PullDetailBodyTimeTests {

    private let createdAt = Date(timeIntervalSince1970: 1_785_000_000)
    private let now = Date(timeIntervalSince1970: 1_785_000_000 + 3 * 86_400)

    private func detail(createdAt: Date?, updatedAt: Date?) -> PullDetail {
        PullDetail(
            number: 57,
            title: "重构导航栈",
            state: .open,
            headRef: "feature/repo-hub",
            baseRef: "main",
            authorLogin: "dev-j",
            createdAt: createdAt,
            updatedAt: updatedAt,
            mergedAt: nil,
            body: "仓库详情升级为四分区枢纽。",
            additions: 842,
            deletions: 156,
            changedFiles: 12
        )
    }

    @Test("拿**创建时刻**算，不是 updatedAt")
    func usesCreatedAtRatherThanUpdatedAt() {
        // 两个时间差得很远，于是"用错了一个"必然看得出来。
        let updatedAt = createdAt.addingTimeInterval(5 * 86_400)
        let label = detail(createdAt: createdAt, updatedAt: updatedAt).bodyTimeLabel(now: now)

        #expect(label == RelativeTime.string(from: createdAt, now: now))
        #expect(label != RelativeTime.string(from: updatedAt, now: now))
        // 走的是全项目统一的那一套相对时间（不含时刻、不含 `:`）。
        #expect(label?.contains(":") == false)
    }

    @Test("创建时刻拿不到 ⇒ `nil`（视图据此不画那一截，而不是编一个时间）")
    func missingCreatedAtGivesNil() {
        let label = detail(createdAt: nil, updatedAt: createdAt).bodyTimeLabel(now: now)

        #expect(label == nil)
    }

    @Test("正文的块在 `init` 里就解析好了（调用方不用记得这件事）")
    func bodyBlocksAreParsedAtInit() {
        let detail = detail(createdAt: createdAt, updatedAt: createdAt)

        #expect(!detail.bodyBlocks.isEmpty)
        // 逐字同一条规则：`MarkdownDocument` 是"原文 + 块"的唯一构造入口。
        #expect(detail.bodyBlocks == MarkdownDocument("仓库详情升级为四分区枢纽。").blocks)
    }

    @Test("没有正文 ⇒ 空数组（**不是** `nil`），且 `hasBody` 与它同向")
    func missingBodyGivesEmptyBlocks() {
        let noBody = PullDetail(
            number: 57,
            title: "重构导航栈",
            state: .open,
            headRef: "feature/repo-hub",
            baseRef: "main",
            additions: 1,
            deletions: 0,
            changedFiles: 1
        )

        let blocks = noBody.bodyBlocks
        #expect(blocks.isEmpty)
        #expect(noBody.hasBody == false)
        // ⚠️ 两条判据**同向但不同源**：`hasBody` 是"用户到底写没写"这条产品判断，
        //    `blocks` 是不是空数组是解析器的事实（`PullTimelineItem` 的说明写了这一条）。
        //    所以这里钉的是"这条输入的两种答案一致"，不是"两者是一回事"。
        #expect(noBody.bodyBlocks.isEmpty == !noBody.hasBody)
    }
}
