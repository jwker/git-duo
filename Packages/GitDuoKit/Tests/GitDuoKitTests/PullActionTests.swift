import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// PR 的三个操作：**合并三方式** · 关闭 / 重新打开 · 结局与错误分开说
/// （PRD §4.11 / §5.3、TECH_SPEC §9.9）。
///
/// ## 这组断言守的四件事，出错时都"看起来正常"
///
/// 1. **200 不等于成功** —— 响应体里的 `merged: false` 也是"没合上"。
///    只看状态码会把一间什么都没发生的仓库报成"已合并"，还会把讨论锁上。
/// 2. **三种合并方式逐字发出** —— `merge_method` 拼错一个字母不会有任何提示，
///    只会让服务端用默认方式合（`rebase` 变成了 `merge`，历史形状完全不同）。
/// 3. **关闭 / 重新打开用服务端回的那份详情** —— 本地改字段会让
///    "界面说已关闭、服务端说还开着"成为可能。
/// 4. **409 / 403 / 404 照常抛**，不折成"不能合" —— §9.9 要求三种结局分开说。
@Suite("PR 操作 · 合并 / 关闭 / 重新打开")
struct PullActionTests {

    private let base = Date(timeIntervalSince1970: 1_786_000_000)

    // MARK: - 数据源替身

    private actor ScriptedActionSource: PullActionDataSource {

        private let mergeResult: Result<PullMergeOutcome, any Error>
        private let patchResult: Result<PullDetailDTO, any Error>

        private(set) var mergeCalls = 0
        private(set) var mergeMethods: [PullMergeMethod] = []
        private(set) var patchStates: [String] = []
        private(set) var patchTargets: [String] = []

        init(
            merge: Result<PullMergeOutcome, any Error> = .success(
                .merged(PullMergeResultDTO(sha: "abc1234", merged: true))
            ),
            patch: Result<PullDetailDTO, any Error>? = nil
        ) {
            self.mergeResult = merge
            self.patchResult = patch ?? .success(
                PullDetailDTO(
                    number: 57,
                    title: "重构导航栈",
                    state: "closed",
                    head: PullRefDTO(ref: "feature/repo-hub"),
                    base: PullRefDTO(ref: "main"),
                    additions: 842,
                    deletions: 156,
                    changedFiles: 12
                )
            )
        }

        func mergePull(
            owner: String,
            repo: String,
            number: Int,
            method: PullMergeMethod
        ) async throws -> PullMergeOutcome {
            mergeCalls += 1
            mergeMethods.append(method)
            return try mergeResult.get()
        }

        func updatePullState(
            owner: String,
            repo: String,
            number: Int,
            state: String
        ) async throws -> PullDetailDTO {
            patchStates.append(state)
            patchTargets.append("\(owner)/\(repo)#\(number)")
            return try patchResult.get()
        }
    }

    private func makeAction(source: ScriptedActionSource) -> PullAction {
        PullAction(source: source)
    }

    // MARK: - 合并

    @Test("合并成功 ⇒ `.merged(at:sha:)`，`at` 是**调用方给的那个时间**")
    func mergeReturnsMergedWithTheGivenTimestamp() async throws {
        let source = ScriptedActionSource()

        let result = try await makeAction(source: source)
            .merge(fullName: "a/b", number: 57, method: .merge, now: base)

        guard case let .merged(at, sha) = result else {
            Issue.record("合上了就该是 .merged，实际：\(result)")
            return
        }
        #expect(at == base, "合并响应体里没有时间 ⇒ 只能用调用方给的那一个（一处决定，不散到各处 Date()）")
        #expect(sha == "abc1234")
    }

    @Test("⚠️ **200 但响应体说 `merged: false` ⇒ `.notMergeable`**（数据层已经折过，这里不反悔）")
    func mergeBodySayingNotMergedIsNotASuccess() async throws {
        let source = ScriptedActionSource(
            merge: .success(.notMergeable)
        )

        let result = try await makeAction(source: source)
            .merge(fullName: "a/b", number: 57, method: .merge, now: base)

        #expect(result == .notMergeable, "报成已合并会立刻把状态改成已合并、把讨论锁上，而仓库里什么都没发生")
    }

    @Test("三种合并方式**逐字**发出（拼错一个字母不会有任何提示，只会换个方式合）")
    func mergeSendsTheMethodVerbatim() async throws {
        for method in PullMergeMethod.allCases {
            let source = ScriptedActionSource()
            _ = try await makeAction(source: source)
                .merge(fullName: "a/b", number: 57, method: method, now: base)
            #expect(await source.mergeMethods == [method])
        }
    }

    @Test("合并只发一次 —— 写操作**不自动重试**（重放会真的产生第二个合并提交）")
    func mergeIsNotRetried() async throws {
        let source = ScriptedActionSource()

        _ = try await makeAction(source: source)
            .merge(fullName: "a/b", number: 57, method: .squash, now: base)

        #expect(await source.mergeCalls == 1)
    }

    @Test(
        "409 / 403 / 404 **照常抛**，不折成「不能合」（§9.9 要求三种结局分开说）",
        arguments: [
            GitHubError.conflict,
            GitHubError.forbidden("Resource not accessible by integration"),
            GitHubError.notFound,
        ]
    )
    func mergeErrorsPropagate(_ error: GitHubError) async throws {
        let source = ScriptedActionSource(merge: .failure(error))

        var caught: GitHubError?
        do {
            _ = try await makeAction(source: source)
                .merge(fullName: "a/b", number: 57, method: .merge, now: base)
        } catch let thrown as GitHubError {
            caught = thrown
        }

        #expect(caught == error)
    }

    @Test("⚠️ 405 那一档**由数据层**折成 `.notMergeable`，领域层不再包一层错误")
    func notMergeableIsNotAnError() async throws {
        // 数据层把 405 折成 `.notMergeable`（`GitHubRepoPullsEndpoint.mergePull`），
        // 于是领域层拿到的就是一个"确凿的答案"而不是一个抛错。
        let source = ScriptedActionSource(merge: .success(.notMergeable))

        let result = try await makeAction(source: source)
            .merge(fullName: "a/b", number: 57, method: .rebase, now: base)

        #expect(result == .notMergeable)
    }

    @Test("`fullName` 形状不对 ⇒ 抛错，且一个请求都没发")
    func malformedFullNameSkipsMerge() async throws {
        let source = ScriptedActionSource()
        var threw = false
        do {
            _ = try await makeAction(source: source)
                .merge(fullName: "noSlash", number: 57, method: .merge, now: base)
        } catch is RepositoryMappingError {
            threw = true
        }
        #expect(threw)
        #expect(await source.mergeCalls == 0)
    }

    // MARK: - 关闭 / 重新打开

    @Test("关闭发 `state=closed`，并用**服务端回的那份详情**（不本地改字段）")
    func closeUsesTheServerResponse() async throws {
        let source = ScriptedActionSource(
            patch: .success(
                PullDetailDTO(
                    number: 57,
                    title: "重构导航栈",
                    state: "closed",
                    head: PullRefDTO(ref: "feature/repo-hub"),
                    base: PullRefDTO(ref: "main"),
                    additions: 1,
                    deletions: 2,
                    changedFiles: 3
                )
            )
        )

        let detail = try await makeAction(source: source).close(fullName: "a/b", number: 57)

        #expect(await source.patchStates == ["closed"])
        #expect(await source.patchTargets == ["a/b#57"])
        #expect(detail.state == .closed)
        #expect(detail.number == 57)
    }

    @Test("重新打开发 `state=open`")
    func reopenSendsOpen() async throws {
        let source = ScriptedActionSource(
            patch: .success(
                PullDetailDTO(
                    number: 57,
                    title: "重构导航栈",
                    state: "open",
                    head: PullRefDTO(ref: "feature/repo-hub"),
                    base: PullRefDTO(ref: "main"),
                    additions: 1,
                    deletions: 2,
                    changedFiles: 3
                )
            )
        )

        let detail = try await makeAction(source: source).reopen(fullName: "a/b", number: 57)

        #expect(await source.patchStates == ["open"], "两个操作只差这一个字符串 —— 拼错不会有任何提示")
        #expect(detail.state == .open)
    }

    @Test("⚠️ 关闭 / 重新打开的**三档判定跟着服务端走**：`closed` + `mergedAt` ⇒ `.merged`")
    func closeKeepsTheThreeStateJudgement() async throws {
        let source = ScriptedActionSource(
            patch: .success(
                PullDetailDTO(
                    number: 57,
                    title: "重构导航栈",
                    state: "closed",
                    mergedAt: base,
                    head: PullRefDTO(ref: "feature/repo-hub"),
                    base: PullRefDTO(ref: "main"),
                    additions: 1,
                    deletions: 2,
                    changedFiles: 3
                )
            )
        )

        let detail = try await makeAction(source: source).close(fullName: "a/b", number: 57)

        #expect(detail.state == .merged, "写操作回来的那份也要走同一个判定（漏了会把已合并说成已关闭）")
        #expect(detail.mergedBanner(now: base) != nil)
    }

    @Test("关闭失败 ⇒ 抛错，界面不会显示成已关闭")
    func closeFailurePropagates() async throws {
        let source = ScriptedActionSource(patch: .failure(GitHubError.forbidden("nope")))

        var caught: GitHubError?
        do {
            _ = try await makeAction(source: source).close(fullName: "a/b", number: 57)
        } catch let thrown as GitHubError {
            caught = thrown
        }

        #expect(caught == .forbidden("nope"))
    }

    @Test("`fullName` 形状不对 ⇒ 关闭也抛错，且一个请求都没发")
    func malformedFullNameSkipsClose() async throws {
        let source = ScriptedActionSource()
        var threw = false
        do {
            _ = try await makeAction(source: source).close(fullName: "a/b/c", number: 57)
        } catch is RepositoryMappingError {
            threw = true
        }
        #expect(threw)
        #expect(await source.patchStates.isEmpty)
    }

    // MARK: - 合并弹层的选项（§5.3）

    @Test("弹层三个选项的顺序与文案逐字对齐 §5.3，**默认第一项**")
    func mergeSheetOptions() {
        let options = PullCopy.mergeMethodOptions

        #expect(options.map(\.method) == [.merge, .squash, .rebase])
        #expect(options.map(\.title) == ["Merge commit", "Squash and merge", "Rebase and merge"])
        #expect(
            options.map(\.detail)
                == ["保留全部分支提交历史", "压成一个提交，历史更干净", "线性历史，不含合并节点"]
        )
        #expect(PullCopy.defaultMergeMethod == options[0].method)
        #expect(PullCopy.defaultMergeMethod == .merge)
    }

    @Test("⚠️ 提示里的短名与弹层上的标题**有意不同**（`Squash` 不是 `Squash and merge`）")
    func toastNamesDifferFromSheetTitles() {
        #expect(PullCopy.mergeMethodName(.merge) == "Merge commit")
        #expect(PullCopy.mergeMethodName(.squash) == "Squash")
        #expect(PullCopy.mergeMethodName(.rebase) == "Rebase")
        #expect(
            PullCopy.mergedToast(method: .squash, number: 57, base: "main")
                == "已用 Squash 合并 #57 进 main"
        )
    }

    @Test("关闭 / 重新打开的提示逐字（原型）")
    func operationToastsMatchPrototype() {
        #expect(PullCopy.closedToast == "已关闭 Pull Request，未合并")
        #expect(PullCopy.reopenedToast == "已重新打开 Pull Request")
    }

    @Test("合并弹层的标题与按钮用的是**分支名**，不是整条流向")
    func mergeSheetUsesBaseBranch() {
        #expect(PullCopy.mergeSheetTitle(branchFlow: "feature/x → main") == "合并 · feature/x → main")
        #expect(PullCopy.mergeConfirmAction(base: "main") == "确认合并进 main")
        #expect(!PullCopy.mergeConfirmAction(base: "main").contains("→"))
    }

    @Test("⚠️ 两种合并失败各有一句、且**两两不同**（折成一句会让用户以为这个 PR 就此不能合了）")
    func mergeFailureMessagesAreDistinct() {
        #expect(PullCopy.mergeNotMergeableToast != PullCopy.mergeConflictToast)
        #expect(PullCopy.mergeNotMergeableToast.contains("网页端"))
        #expect(PullCopy.mergeConflictToast.contains("冲突"))
        #expect(PullCopy.mergeSheetHint.contains("冲突"))
    }
}
