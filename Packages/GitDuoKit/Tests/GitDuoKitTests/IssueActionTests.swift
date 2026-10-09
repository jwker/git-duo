import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// Issue 的两个操作：关闭 / 重新打开（PRD §4.9 操作区、TECH_SPEC §9.8、决策 **#79**）。
///
/// ## 这组断言守的四件事，出错时都"看起来正常"
///
/// 1. **判据是两个条件的析取**（我是作者 ∨ 我对这个仓库有写权限）。
///    少任何一半，都会让某一类 Issue 少一颗按钮 —— 而屏幕上别的全对：
///    标题、状态胶囊、评论、元信息，一处都看不出问题。
/// 2. **作者判定大小写不敏感**。这条最隐蔽：GitHub 登录名本身大小写不敏感，
///    按 `==` 比会让「我自己提的 Issue」认不出自己。
/// 3. **关闭 / 重新打开用服务端回的那份详情**，不在本地改字段 ——
///    否则"界面说已关闭、服务端说还开着"成为可能。
/// 4. **`state` 那两个字符串逐字发出**：`updateIssueState` 故意不校验取值，
///    拼错一个不会有任何编译期或运行期提示。
@Suite("Issue 操作 · 关闭 / 重新打开（决策 #79）")
struct IssueActionTests {

    private let base = Date(timeIntervalSince1970: 1_786_000_000)

    // MARK: - 造数据

    private func makeDetail(authorLogin: String?, isOpen: Bool = true) -> IssueDetail {
        IssueDetail(
            number: 42,
            title: "README 里的相对链接点了没反应",
            isOpen: isOpen,
            body: "见正文",
            authorLogin: authorLogin,
            createdAt: base,
            closedAt: isOpen ? nil : base.addingTimeInterval(3600)
        )
    }

    private func makeDTO(state: String, authorLogin: String?) -> IssueDetailDTO {
        IssueDetailDTO(
            number: 42,
            title: "README 里的相对链接点了没反应",
            state: state,
            body: "见正文",
            user: authorLogin.map { AuthorDTO(login: $0) },
            createdAt: base,
            closedAt: state == "closed" ? base.addingTimeInterval(3600) : nil
        )
    }

    // MARK: - 数据源替身

    private actor ScriptedIssueActionSource: IssueActionDataSource {

        private let patchResult: Result<IssueDetailDTO, any Error>

        private(set) var patchStates: [String] = []
        private(set) var patchTargets: [String] = []

        init(patch: Result<IssueDetailDTO, any Error>) {
            self.patchResult = patch
        }

        func updateIssueState(
            owner: String,
            repo: String,
            number: Int,
            state: String
        ) async throws -> IssueDetailDTO {
            patchStates.append(state)
            patchTargets.append("\(owner)/\(repo)#\(number)")
            return try patchResult.get()
        }
    }

    private struct Boom: Error {}

    // MARK: - 判据（PRD §4.9 操作区那三档）

    @Test("⚠️⚠️ 判据是**两个条件的析取**：我是作者 ∨ 我对这个仓库有写权限")
    func decideIsADisjunction() {
        // ① 有仓库写权限（自己的仓库）⇒ 别人提的 Issue 也能关 —— 维护者的日常。
        #expect(IssueOperationAvailability.decide(readOnly: false, isAuthor: false, isOpen: true) == .close)

        // ② **我是作者** ⇒ 即使入口说「只读」（他人仓库）**仍然能关**。
        //    这一条是决策 #79 的要害：GitHub 的规则就是「谁提的谁可关」。
        #expect(IssueOperationAvailability.decide(readOnly: true, isAuthor: true, isOpen: true) == .close)

        // ③ 两个都不成立 ⇒ 只有那一行提示。
        #expect(IssueOperationAvailability.decide(readOnly: true, isAuthor: false, isOpen: true) == .readOnly)
    }

    @Test("⚠️ 三档的**顺序**：作者身份先于只读 —— 反了就把用户报的那一条判成只读")
    func authorIsCheckedBeforeReadOnly() {
        // 反过来的写法（先 `if readOnly { return .readOnly }`）在这两条上都错。
        // 而它们正是「我的 Issue」那一屏的情形：入口保守、条目全是自己提的。
        #expect(IssueOperationAvailability.decide(readOnly: true, isAuthor: true, isOpen: true) != .readOnly)
        #expect(IssueOperationAvailability.decide(readOnly: true, isAuthor: true, isOpen: false) == .reopen)
    }

    @Test("已关闭那一档是「重新打开」（状态是判据的另一半）")
    func closedMapsToReopen() {
        #expect(IssueOperationAvailability.decide(readOnly: false, isAuthor: false, isOpen: false) == .reopen)
        #expect(IssueOperationAvailability.decide(readOnly: true, isAuthor: true, isOpen: false) == .reopen)
        // 不能管的人看已关闭的 Issue，仍然是只读（不是"重新打开"）。
        #expect(IssueOperationAvailability.decide(readOnly: true, isAuthor: false, isOpen: false) == .readOnly)
    }

    // MARK: - 作者判定

    @Test("⚠️⚠️ 作者判定**大小写不敏感**（按 `==` 比会让「我自己提的 Issue」变成只读）")
    func authorComparisonIgnoresCase() {
        let detail = makeDetail(authorLogin: "JiangJiang")
        #expect(detail.isAuthored(by: "jiangjiang"))
        #expect(detail.isAuthored(by: "JIANGJIANG"))
        #expect(detail.isAuthored(by: "JiangJiang"))
        #expect(!detail.isAuthored(by: "someone-else"))
        // ⚠️ 前缀不算相等（别用 `hasPrefix` 这类近似判断）。
        #expect(!detail.isAuthored(by: "jiang"))
    }

    @Test("⚠️ 作者取不到 ⇒ **不是作者**（宁可少一颗按钮，也不给一颗点下去必 403 的）")
    func missingAuthorIsNeverMe() {
        #expect(!makeDetail(authorLogin: nil).isAuthored(by: "jiangjiang"))
        // 登录名取不到时同样取保守侧（虽然登录态下取不到，但判据不该依赖"取得到"）。
        #expect(!makeDetail(authorLogin: "jiangjiang").isAuthored(by: nil))
    }

    @Test("⚠️⚠️ 「我的 Issue」入口：`readOnly: true`，但每条都是我提的 ⇒ **全部可操作**")
    func myIssuesEntryStaysActionable() {
        // 这一条**就是用户走查报回的那个现象**（「从我的 Issue 进详情后不能改状态」）。
        // 那个入口传的是 `readOnly: true`（搜索端点不返回可写性 ⇒ 取保守侧），
        // 而它的列表口径是 `author:@me` ⇒ **作者身份把保守侧抵消掉了**。
        let mine = makeDetail(authorLogin: "jiangjiang", isOpen: true)
        #expect(mine.operationAvailability(readOnly: true, viewerLogin: "jiangjiang") == .close)

        // 对照组：同一个入口下**别人提的** Issue 仍然是只读 —— 保守侧没有被整体取消。
        let theirs = makeDetail(authorLogin: "someone-else", isOpen: true)
        #expect(theirs.operationAvailability(readOnly: true, viewerLogin: "jiangjiang") == .readOnly)

        // 登录名大小写不同也不影响（入口给回来的登录名写法不一定与 Issue 作者一致）。
        #expect(mine.operationAvailability(readOnly: true, viewerLogin: "JiangJiang") == .close)
    }

    // MARK: - 两个操作

    @Test("关闭 / 重新打开：`state` 逐字发出，打的是**同一个仓库的同一个编号**")
    func actionsSendTheRightStateAndTarget() async throws {
        let source = ScriptedIssueActionSource(patch: .success(makeDTO(state: "closed", authorLogin: "jiangjiang")))
        let action = IssueAction(source: source)

        _ = try await action.close(fullName: "my-git/gitduo", number: 42)
        #expect(await source.patchStates == ["closed"])
        #expect(await source.patchTargets == ["my-git/gitduo#42"])

        _ = try await action.reopen(fullName: "my-git/gitduo", number: 42)
        // ⚠️ 两个动作唯一的差别就是这个字符串：`"close"` / `"closeIssue"` 这类拼错
        //    不会有任何提示（数据层故意不校验取值）。
        #expect(await source.patchStates == ["closed", "open"])
    }

    @Test("⚠️ 用的是**服务端回的那份详情**（状态跟着它走，不写死 `true`）")
    func detailFollowsTheServerResponse() async throws {
        // 服务端说这一发把它关掉了。
        let closeSource = ScriptedIssueActionSource(patch: .success(makeDTO(state: "closed", authorLogin: "jiangjiang")))
        let closed = try await IssueAction(source: closeSource).close(fullName: "my-git/gitduo", number: 42)
        #expect(!closed.isOpen)
        #expect(closed.closedAt != nil)

        // ⚠️ 反过来：服务端回 `open` ⇒ 详情必须是开放的。
        //    写死 `isOpen: true` 的实现在上面那条也许能过（碰巧），但在这里会当场红。
        let reopenSource = ScriptedIssueActionSource(patch: .success(makeDTO(state: "open", authorLogin: "jiangjiang")))
        let reopened = try await IssueAction(source: reopenSource).reopen(fullName: "my-git/gitduo", number: 42)
        #expect(reopened.isOpen)
        #expect(reopened.closedAt == nil)
    }

    @Test("请求失败照常抛 —— **不折成「已经关了」**")
    func failuresThrow() async {
        let source = ScriptedIssueActionSource(patch: .failure(Boom()))
        await #expect(throws: Boom.self) {
            _ = try await IssueAction(source: source).close(fullName: "my-git/gitduo", number: 42)
        }
    }

    // MARK: - 文案契约（PRD §4.9 操作区 / §5.18）

    @Test("操作区两颗按钮 · 弹层两句 · 两条成功提示，**逐字**（写的是期望值，不是同义反复）")
    func actionCopyIsExact() {
        #expect(IssueCopy.closeAction == "关闭 Issue")
        #expect(IssueCopy.reopenAction == "重新打开 Issue")
        #expect(IssueCopy.closeSheetTitle == "关闭这条 Issue？")
        #expect(IssueCopy.closeSheetHint == "关闭之后仍然可以重新打开，评论都会保留。")
        #expect(IssueCopy.closedToast(number: 42) == "已关闭 #42")
        #expect(IssueCopy.reopenedToast(number: 42) == "已重新打开 #42")
    }

    @Test("⚠️ 两个动作的话**不能互相顶替**（关 / 重开是反动作，串用之后界面照样说得通、只是说反了）")
    func closeAndReopenCopyAreNotSwapped() {
        // 这一族句子里，"关闭"与"重新打开"互为反动作 —— 串用不会报错，
        // 而说反的那一处（提示条）几秒后就没了，事后很难发现。
        #expect(IssueCopy.closeAction != IssueCopy.reopenAction)
        #expect(IssueCopy.reopenAction.contains("重新"))
        #expect(IssueCopy.closeAction != IssueCopy.closeSheetTitle)
        #expect(!IssueCopy.closeAction.contains("？"))
        // §5.18 的确认按钮**就是**操作区那一串（弹层里那一颗读的就是 `closeAction`）：
        // 弹层里再写一遍"关闭 Issue"这种副本迟早会漂。
        #expect(IssueCopy.closeSheetTitle.hasSuffix("？"))
        #expect(IssueCopy.closeSheetHint.contains("重新打开"))
        // 弹层那句说明是一个**可验证的承诺**：能关的人就能重开（两档走同一个判据）。
        // 这里同时钉住两条提示是两句不同的话。
        #expect(IssueCopy.closedToast(number: 7) != IssueCopy.reopenedToast(number: 7))
    }

    @Test("⚠️⚠️ 操作区那行提示**不是**探索 Issues 列表的页脚（只差一个分隔符，说的却是两件事）")
    func readOnlyHintIsNotTheListFooter() {
        // 两句长得极像 ⇒ 迟早有人"顺手统一"它们。这一条就是为那一次清理准备的：
        // 列表页脚说"这个列表能做什么"，详情页那一行说"这一页为什么没有按钮"。
        #expect(IssueCopy.readOnlyHint != OpenIssueIndicator.footer)

        // 逐个记下它们的差别（只差分隔符，其余必须一致 —— 否则就是抄错了）。
        #expect(IssueCopy.readOnlyHint == "他人仓库 · 可评论参与讨论，关闭 Issue 需维护者权限")
        #expect(OpenIssueIndicator.footer == "他人仓库：可评论参与讨论，关闭 Issue 需维护者权限")

        // ⚠️ 详情页这一句跟的是**原型里 PR 详情页那一处**（`08-pr.js:50`，用 ` · `），
        //    不是列表页脚（`10-explore-repo.js:126`，用 `：`）。
        #expect(IssueCopy.readOnlyHint.contains(" · "))
        #expect(!IssueCopy.readOnlyHint.contains("："))
    }
}
