import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 新建 Issue：**占位标题** · **正文不 trim** · 标签顺序 · 成功提示（PRD §4.10）。
///
/// ## 这组断言守的四件事，出错时都"看起来正常"
///
/// 1. **占位标题是发出去的内容**，不只是界面上的话 —— GitHub 上那条 Issue 的标题就是它。
/// 2. **正文不许 trim** —— 前导缩进在 Markdown 里是有意义的，裁掉会把一段代码块
///    变成一个普通段落。那是一次**悄悄改用户内容**的错误。
/// 3. **已选标签的顺序 = 选中的先后顺序**（不是字母序）——
///    顺序换了不会报错，只会让人以为"它自己重排了"。
/// 4. **提示里的编号来自响应体**，不能靠"本地计数 +1"猜。
@Suite("新建 Issue · 占位标题 / 正文 / 标签 / 提示")
struct NewIssueTests {

    private let base = Date(timeIntervalSince1970: 1_786_000_000)

    // MARK: - 数据源替身

    private actor ComposerSpy: IssueComposerDataSource {

        private let result: Result<IssueDetailDTO, any Error>
        private(set) var calls = 0
        private(set) var titles: [String] = []
        private(set) var bodies: [String?] = []
        private(set) var labelSets: [[String]] = []
        private(set) var targets: [String] = []

        init(result: Result<IssueDetailDTO, any Error>? = nil) {
            self.result = result ?? .success(
                IssueDetailDTO(
                    number: 43,
                    title: "原型反馈：Issues 不可点开",
                    state: "open",
                    createdAt: Date(timeIntervalSince1970: 0)
                )
            )
        }

        func createIssue(
            owner: String,
            repo: String,
            title: String,
            body: String?,
            labels: [String]
        ) async throws -> IssueDetailDTO {
            calls += 1
            titles.append(title)
            bodies.append(body)
            labelSets.append(labels)
            targets.append("\(owner)/\(repo)")
            return try result.get()
        }
    }

    // MARK: - 占位标题

    @Test("标题为空 ⇒ 用占位标题 `新 Issue`")
    func emptyTitleFallsBackToPlaceholder() {
        var draft = NewIssueDraft.empty
        #expect(draft.effectiveTitle == "新 Issue")
        draft.title = "   "
        #expect(draft.effectiveTitle == "新 Issue", "只打了空格也算没写 —— 否则 GitHub 上会多一条空白标题的 Issue")
        draft.title = "\n\t"
        #expect(draft.effectiveTitle == "新 Issue")
    }

    @Test("标题有内容 ⇒ trim 后发出（单行输入，前后空格是噪声）")
    func titleIsTrimmed() {
        var draft = NewIssueDraft.empty
        draft.title = "  原型反馈：Issues 不可点开  "
        #expect(draft.effectiveTitle == "原型反馈：Issues 不可点开")
    }

    // MARK: - 正文

    @Test("⚠️ 正文为 `nil` 或**只有空白** ⇒ 不带这个字段")
    func blankBodyBecomesNil() {
        var draft = NewIssueDraft.empty
        #expect(draft.effectiveBody == nil)
        draft.body = ""
        #expect(draft.effectiveBody == nil)
        draft.body = "  \n\t  "
        #expect(draft.effectiveBody == nil)
    }

    @Test("⚠️ 正文**一字不改**地发出 —— 前导缩进属于内容")
    func bodyIsNotTrimmed() {
        var draft = NewIssueDraft.empty
        let body = "    缩进过的代码块\n\n结尾留一行\n"
        draft.body = body
        #expect(draft.effectiveBody == body, "裁掉前导空格会把一段代码块变成普通段落")
        #expect(draft.effectiveBody?.hasPrefix("    ") == true)
        #expect(draft.effectiveBody?.hasSuffix("\n") == true)
    }

    // MARK: - 已选标签

    @Test("标签行顺序 = **选中的先后顺序**（原型 `niLabels` 的 push 顺序）")
    func labelOrderIsSelectionOrder() {
        var draft = NewIssueDraft.empty
        let bug = Label(name: "bug", colorHex: "d73a4a")
        let enhancement = Label(name: "enhancement", colorHex: "a2eeef")
        let performance = Label(name: "performance", colorHex: "0075ca")

        draft.toggle(performance)
        draft.toggle(bug)
        draft.toggle(enhancement)

        #expect(draft.labels.map(\.name) == ["performance", "bug", "enhancement"])
        #expect(draft.effectiveLabelNames == ["performance", "bug", "enhancement"])
    }

    @Test("再点一次同一个标签 ⇒ 去掉它（原型 `toggleLabel` 的语义）")
    func toggleRemovesWhenAlreadySelected() {
        var draft = NewIssueDraft.empty
        let bug = Label(name: "bug", colorHex: "d73a4a")

        draft.toggle(bug)
        #expect(draft.isSelected(bug))
        draft.toggle(bug)
        #expect(!draft.isSelected(bug))
        #expect(draft.labels.isEmpty)
    }

    @Test("弹层里那枚 `✓` 的判据与 toggle **同一套比较**（按名字）")
    func selectionIsMatchedByName() {
        var draft = NewIssueDraft.empty
        draft.toggle(Label(name: "bug", colorHex: "d73a4a"))
        // 同一个标签、颜色不同的实例 —— 仍然算已选（弹层可能与标签行来自两次取数）。
        #expect(draft.isSelected(Label(name: "bug", colorHex: "000000")))
        #expect(!draft.isSelected(Label(name: "docs", colorHex: "0075ca")))
    }

    @Test("进页面重置 ⇒ 空草稿（上一次填的内容不许留在新页面上）")
    func emptyDraftIsReallyEmpty() {
        let fresh = NewIssueDraft.empty
        #expect(fresh.title.isEmpty)
        #expect(fresh.body.isEmpty)
        #expect(fresh.labels.isEmpty)
    }

    // MARK: - 提交

    @Test("提交时把三条 `effective*` 原样交给端点")
    func submitForwardsEffectiveValues() async throws {
        let source = ComposerSpy()
        var draft = NewIssueDraft.empty
        draft.title = "  原型反馈：Issues 不可点开 "
        draft.body = "    正文带缩进"
        draft.toggle(Label(name: "bug", colorHex: "d73a4a"))
        draft.toggle(Label(name: "performance", colorHex: "0075ca"))

        _ = try await CreateIssue(source: source).submit(fullName: "my-git/gitduo", draft: draft)

        #expect(await source.targets == ["my-git/gitduo"])
        #expect(await source.titles == ["原型反馈：Issues 不可点开"])
        #expect(await source.bodies == ["    正文带缩进"])
        #expect(await source.labelSets == [["bug", "performance"]], "标签按**名字**传，顺序即胶囊顺序")
    }

    @Test("标题为空时，**发出去的占位标题**是 `新 Issue`（不是空串）")
    func placeholderTitleIsActuallySent() async throws {
        let source = ComposerSpy()

        _ = try await CreateIssue(source: source).submit(fullName: "a/b", draft: .empty)

        #expect(await source.titles == ["新 Issue"])
        #expect(await source.bodies == [nil], "空正文不带这个字段")
        #expect(await source.labelSets == [[]], "未选标签 ⇒ 空数组（端点据此**不带** labels 字段）")
    }

    @Test("⚠️ 成功提示里的编号来自**响应体**（不是本地猜的）")
    func createdNumberComesFromTheServer() async throws {
        let source = ComposerSpy(
            result: .success(
                IssueDetailDTO(number: 137, title: "服务端取的名字", state: "open", createdAt: base)
            )
        )
        var draft = NewIssueDraft.empty
        draft.title = "本地写的标题"

        let created = try await CreateIssue(source: source).submit(fullName: "a/b", draft: draft)

        #expect(created.number == 137)
        #expect(created.title == "服务端取的名字", "提示里说「已创建 X」而 GitHub 上叫 Y，是用户唯一的线索")
    }

    @Test("提示逐字：有标签时 `已创建 Issue #43 · “标题” · 标签 3 个`")
    func toastWithLabels() {
        var draft = NewIssueDraft.empty
        draft.title = "t"
        draft.toggle(Label(name: "bug", colorHex: "d73a4a"))
        draft.toggle(Label(name: "enhancement", colorHex: "a2eeef"))
        draft.toggle(Label(name: "performance", colorHex: "0075ca"))

        let created = CreatedIssue(number: 43, title: "原型反馈：Issues 不可点开", labelCount: draft.labels.count)

        #expect(
            created.toastMessage == "已创建 Issue #43 · “原型反馈：Issues 不可点开” · 标签 3 个"
        )
    }

    @Test("提示逐字：**没标签时不缀** `标签 0 个`（多余的坏消息）")
    func toastWithoutLabels() {
        let created = CreatedIssue(number: 43, title: "新 Issue", labelCount: 0)

        #expect(created.toastMessage == "已创建 Issue #43 · “新 Issue”")
        #expect(!created.toastMessage.contains("标签"))
    }

    @Test("`fullName` 形状不对 ⇒ 抛错，且一个请求都没发")
    func malformedFullNameSkipsTheRequest() async throws {
        let source = ComposerSpy()
        var threw = false
        do {
            _ = try await CreateIssue(source: source).submit(fullName: "noSlash", draft: .empty)
        } catch is RepositoryMappingError {
            threw = true
        }
        #expect(threw)
        #expect(await source.calls == 0)
    }
}
