import Foundation
import Testing

@testable import GitDuoKit

/// 评论草稿：**键 = 仓库 + 编号** · 空内容即删 · 落盘编解码（决策 #59、PRD §4.9 / §4.11）。
///
/// ## 这组断言守的四件事，出错时都"看起来正常"
///
/// 1. **两个仓库的 `#42` 不能串** —— 串了就是"在 B 仓库的输入框里看到 A 仓库的半句话"。
/// 2. **内容清空 ⇒ 那条草稿要没掉** —— 用户删干净后离开是很常见的动作，
///    存一条空草稿会在磁盘上留着"他以为自己已经放弃的内容"的痕迹。
/// 3. **发送成功必须 `discard`** —— 不清的话下次进来输入框里是**上次已经发出去的那段话**。
/// 4. **解码失败整份作废** —— 半截草稿比没有草稿更坏（用户会在它基础上接着写并发出去）。
@Suite("评论草稿 · 键 / 空内容 / 编解码")
struct CommentDraftStoreTests {

    private let base = Date(timeIntervalSince1970: 1_786_000_000)

    // MARK: - 键

    @Test("存一条、读回来")
    func saveAndRead() async throws {
        let store = InMemoryCommentDraftStore()

        await store.save(fullName: "a/b", number: 42, body: "写了一半", at: base)
        let draft = try #require(await store.draft(fullName: "a/b", number: 42))

        #expect(draft.body == "写了一半")
        #expect(draft.fullName == "a/b")
        #expect(draft.number == 42)
        #expect(draft.savedAt == base)
    }

    @Test("⚠️ **两个仓库的同号讨论各自独立**（串了会在 B 仓库看到 A 仓库的半句话）")
    func repositoriesAreIsolated() async throws {
        let store = InMemoryCommentDraftStore()

        await store.save(fullName: "a/one", number: 42, body: "A 仓库的草稿", at: base)
        await store.save(fullName: "z/two", number: 42, body: "Z 仓库的草稿", at: base)

        #expect(await store.draft(fullName: "a/one", number: 42)?.body == "A 仓库的草稿")
        #expect(await store.draft(fullName: "z/two", number: 42)?.body == "Z 仓库的草稿")
    }

    @Test("同一个仓库里两个编号各自独立")
    func numbersAreIsolated() async throws {
        let store = InMemoryCommentDraftStore()

        await store.save(fullName: "a/b", number: 1, body: "第一条", at: base)
        await store.save(fullName: "a/b", number: 2, body: "第二条", at: base)

        #expect(await store.draft(fullName: "a/b", number: 1)?.body == "第一条")
        #expect(await store.draft(fullName: "a/b", number: 2)?.body == "第二条")
        #expect(await store.draft(fullName: "a/b", number: 3) == nil)
    }

    @Test("没写过 ⇒ `nil`（不是空草稿）")
    func missingDraftIsNil() async {
        let store = InMemoryCommentDraftStore()
        #expect(await store.draft(fullName: "a/b", number: 42) == nil)
    }

    @Test("再存一次覆盖旧的（同一处只留最新那份）")
    func saveOverwrites() async throws {
        let store = InMemoryCommentDraftStore()

        await store.save(fullName: "a/b", number: 42, body: "第一版", at: base)
        await store.save(fullName: "a/b", number: 42, body: "第二版", at: base.addingTimeInterval(60))

        #expect(await store.draft(fullName: "a/b", number: 42)?.body == "第二版")
        #expect(await store.allDrafts().count == 1)
    }

    // MARK: - 空内容

    @Test("⚠️ **空内容 ⇒ 那条草稿消失**（不是存一条空草稿）")
    func emptyBodyRemovesTheDraft() async {
        let store = InMemoryCommentDraftStore()
        await store.save(fullName: "a/b", number: 42, body: "写了一半", at: base)
        #expect(await store.draft(fullName: "a/b", number: 42) != nil)

        await store.save(fullName: "a/b", number: 42, body: "", at: base)

        #expect(await store.draft(fullName: "a/b", number: 42) == nil)
        #expect(await store.allDrafts().isEmpty)
    }

    @Test("⚠️ **只有空白也算空** —— 判据与 `PostIssueComment.canSend` 同一套")
    func whitespaceOnlyBodyRemovesTheDraft() async {
        let store = InMemoryCommentDraftStore()
        await store.save(fullName: "a/b", number: 42, body: "写了一半", at: base)

        await store.save(fullName: "a/b", number: 42, body: "  \n\t ", at: base)

        #expect(await store.draft(fullName: "a/b", number: 42) == nil)
    }

    @Test("⚠️ 存进去的正文**一字不改**（前导缩进在 Markdown 里有意义）")
    func bodyIsStoredVerbatim() async throws {
        let store = InMemoryCommentDraftStore()
        let body = "    缩进过的代码块\n\n结尾留一行\n"

        await store.save(fullName: "a/b", number: 42, body: body, at: base)

        #expect(await store.draft(fullName: "a/b", number: 42)?.body == body)
    }

    // MARK: - 删除

    @Test("⚠️ `discard` 之后读不到（发送成功必须调它 —— 否则下次进来是上次发过的那段话）")
    func discardRemovesTheDraft() async {
        let store = InMemoryCommentDraftStore()
        await store.save(fullName: "a/b", number: 42, body: "已经发出去了", at: base)

        await store.discard(fullName: "a/b", number: 42)

        #expect(await store.draft(fullName: "a/b", number: 42) == nil)
    }

    @Test("`discard` 只删那一条，别的仓库 / 编号不受影响")
    func discardIsScoped() async {
        let store = InMemoryCommentDraftStore()
        await store.save(fullName: "a/b", number: 42, body: "一", at: base)
        await store.save(fullName: "a/b", number: 43, body: "二", at: base)
        await store.save(fullName: "c/d", number: 42, body: "三", at: base)

        await store.discard(fullName: "a/b", number: 42)

        #expect(await store.draft(fullName: "a/b", number: 42) == nil)
        #expect(await store.draft(fullName: "a/b", number: 43) != nil)
        #expect(await store.draft(fullName: "c/d", number: 42) != nil)
    }

    @Test("⚠️ `clear()` 清空全部（登出第 ③ 步 —— 草稿里可能有还没发布的正文）")
    func clearRemovesEverything() async {
        let store = InMemoryCommentDraftStore()
        await store.save(fullName: "a/b", number: 1, body: "一", at: base)
        await store.save(fullName: "a/b", number: 2, body: "二", at: base)
        await store.save(fullName: "c/d", number: 3, body: "三", at: base)

        await store.clear()

        #expect(await store.allDrafts().isEmpty)
        #expect(await store.draft(fullName: "a/b", number: 1) == nil)
    }

    // MARK: - 落盘用的顺序与编解码

    @Test("⚠️ `allDrafts()` 的顺序**确定**（Dictionary 迭代顺序每次运行都可能不同）")
    func allDraftsIsDeterministic() async {
        let seeds = [
            CommentDraft(fullName: "z/two", number: 9, body: "c", savedAt: base),
            CommentDraft(fullName: "a/one", number: 42, body: "b", savedAt: base),
            CommentDraft(fullName: "a/one", number: 3, body: "a", savedAt: base),
        ]

        let first = await InMemoryCommentDraftStore(seed: seeds).allDrafts()
        let second = await InMemoryCommentDraftStore(seed: seeds.reversed()).allDrafts()

        #expect(first.map { "\($0.fullName)#\($0.number)" } == ["a/one#3", "a/one#42", "z/two#9"])
        #expect(first == second, "同一份内容两次读出必须得到同一个字节序列（否则落盘比对会变成间歇性失败）")
    }

    @Test("seed 里同一条重复出现 ⇒ 只留一条（不会长出两个同名键）")
    func seedDeduplicates() async {
        let seed = [
            CommentDraft(fullName: "a/b", number: 42, body: "旧", savedAt: base),
            CommentDraft(fullName: "a/b", number: 42, body: "新", savedAt: base.addingTimeInterval(1)),
        ]

        let store = InMemoryCommentDraftStore(seed: seed)

        #expect(await store.allDrafts().count == 1)
        #expect(await store.draft(fullName: "a/b", number: 42)?.body == "新")
    }

    @Test("编解码往返：正文里的换行 / 引号 / emoji 都逐字回来")
    func codingRoundTrip() throws {
        let drafts = [
            CommentDraft(fullName: "a/b", number: 42, body: "第一行\n第二行 \"引号\" 🎉", savedAt: base),
            CommentDraft(fullName: "c/d", number: 7, body: "  缩进\n", savedAt: base),
        ]

        let data = try #require(CommentDraft.encodeList(drafts))
        #expect(CommentDraft.decodeList(from: data) == drafts)
    }

    @Test("⚠️ 解码失败 ⇒ **空数组**（半截草稿比没有草稿更坏：用户会在它基础上接着写并发出去）")
    func decodeFailureYieldsNothing() {
        #expect(CommentDraft.decodeList(from: Data("不是 JSON".utf8)).isEmpty)
        #expect(CommentDraft.decodeList(from: Data()).isEmpty)
        // 形状对但不完整：缺 `body` 的那些应当让整份作废，而不是"能解出几条算几条"。
        let partial = Data(#"[{"fullName":"a/b","number":1}]"#.utf8)
        #expect(CommentDraft.decodeList(from: partial).isEmpty)
    }

    @Test("空列表编码后能解回空列表")
    func emptyRoundTrip() throws {
        let data = try #require(CommentDraft.encodeList([]))
        #expect(CommentDraft.decodeList(from: data).isEmpty)
    }

    @Test("Issue 与 PR 共用编号空间 ⇒ 键里不需要区分类型（`#42` 不可能同时是两者）")
    func noKindInTheKey() async throws {
        // 这条不是在验证"能区分"，而是在钉住"**不能**再往键里加一个类型维度"：
        // GitHub 的 Issue 与 PR 共用同一串编号，所以 (仓库, 编号) 已经是唯一键。
        // 加了类型维度的话，同一条讨论会有两个键 —— 而用户在 Issue 页存的草稿
        // 到了 PR 页（如果编号被复用到）就读不到了。
        let store = InMemoryCommentDraftStore()

        await store.save(fullName: "a/b", number: 42, body: "同一处讨论", at: base)

        let draft = try #require(await store.draft(fullName: "a/b", number: 42))
        #expect(draft.number == 42)
        #expect(await store.allDrafts().count == 1)
    }
}
