import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 分支解析（TECH_SPEC §9.4.1）· 删除判据（决策 #53）· 按仓库记忆（PRD §3.10）。
///
/// ## 为什么这一整套必须被钉住
///
/// 三条规则错了都不会报错，只会**显示成另一个正确的样子**：
/// - 解析错了 ⇒ 页面显示 `main`，而它其实该显示 `feature/x`（用户以为记忆丢了）；
/// - 删除判据错了 ⇒ 用户删掉自己的默认分支，App 一切正常，直到他下次打开仓库；
/// - 记忆串了仓库 ⇒ **彻底无法察觉**（`feature/x` 是个合法分支名，只是不属于这个仓库）。
@Suite("分支解析 · 两段式 / 回落 / 删除判据 / 按仓库记忆")
struct BranchResolutionTests {

    private let branches = ["main", "develop", "feature/repo-hub"]

    // MARK: - 第一段：立即取值

    @Test("第一段**不校验**记忆值是否仍存在 —— 那一刻没有依据，等它就白等一个 RTT")
    func initialUsesMemoryWithoutVerifying() {
        // 记的是一条**已经不在列表里**的分支，第一段照样用它。
        #expect(BranchResolver.initial(remembered: "gone", defaultBranch: "main") == "gone")
        #expect(BranchResolver.initial(remembered: "develop", defaultBranch: "main") == "develop")
    }

    @Test("无记忆（或空串）⇒ 默认分支")
    func initialFallsBackToDefault() {
        #expect(BranchResolver.initial(remembered: nil, defaultBranch: "main") == "main")
        #expect(BranchResolver.initial(remembered: "", defaultBranch: "main") == "main")
    }

    // MARK: - 第二段：校正

    @Test("记忆的分支仍在列表里 ⇒ 沿用，且**不算回落**")
    func keepsExistingMemory() {
        let result = BranchResolver.resolved(remembered: "develop", available: branches, defaultBranch: "main")

        #expect(result.branch == "develop")
        #expect(result.didFallBack == false)
    }

    @Test("⚠️ 记忆的分支已不存在 ⇒ 回落默认分支，且 `didFallBack == true`")
    func fallsBackWhenMemoryIsGone() {
        let result = BranchResolver.resolved(remembered: "deleted-branch", available: branches, defaultBranch: "main")

        #expect(result.branch == "main")
        #expect(result.didFallBack)
    }

    @Test("⚠️ 「无记忆」也返回默认分支，但**不算回落**")
    func noMemoryIsNotAFallBack() {
        let result = BranchResolver.resolved(remembered: nil, available: branches, defaultBranch: "main")

        #expect(result.branch == "main")
        // 这条断言是实打实的：`didFallBack` 会触发"清缓存 + forget 记忆"，
        // 首次进仓库时白做一次，用户看到的是多一次加载。
        #expect(result.didFallBack == false)
    }

    @Test("⚠️ 分支列表**为空**视为「无法验证」，保留记忆值而不是回落")
    func emptyListKeepsMemory() {
        let result = BranchResolver.resolved(remembered: "develop", available: [], defaultBranch: "main")

        // 把空列表当"什么都不存在"会**写盘**抹掉记忆（`forget`），
        // 而一次临时的空响应不该造成不可自愈的损失。
        #expect(result.branch == "develop")
        #expect(result.didFallBack == false)
    }

    @Test("记忆值恰好就是默认分支 ⇒ 沿用（不因为「不在列表里」而回落，那是另一回事）")
    func memoryEqualToDefault() {
        let result = BranchResolver.resolved(remembered: "main", available: branches, defaultBranch: "main")

        #expect(result.branch == "main")
        #expect(result.didFallBack == false)
    }

    // MARK: - 第三段：静默重发

    @Test("⚠️ 只有在 404 **且** 用的不是默认分支时才静默重发")
    func silentRetryOnlyOnNotFoundWithNonDefaultBranch() {
        // 应该重发：记忆值那条 ref 没了 ⇒ 回落规则本该吸收它。
        #expect(
            BranchResolver.shouldSilentlyRetry(
                after: .notFound, attemptedBranch: "feature/x", defaultBranch: "main"
            )
        )

        // ⚠️ 不该重发：已经在用默认分支还 404 ⇒ 是仓库整体不可达 / 没权限，
        //    重发只会再吃一次 404（无限重试的入口）。必须如实报错。
        #expect(
            BranchResolver.shouldSilentlyRetry(
                after: .notFound, attemptedBranch: "main", defaultBranch: "main"
            ) == false
        )

        // ⚠️ 不该重发：断网 / 限流 / 5xx 与"ref 不存在"无关，重发解决不了，
        //    而且会把一次真实的网络故障伪装成"分支切换成功"。
        #expect(
            BranchResolver.shouldSilentlyRetry(
                after: .transport(URLError(.notConnectedToInternet)),
                attemptedBranch: "feature/x",
                defaultBranch: "main"
            ) == false
        )
        #expect(
            BranchResolver.shouldSilentlyRetry(
                after: .rateLimited(resetAt: Date(), isSecondary: false),
                attemptedBranch: "feature/x",
                defaultBranch: "main"
            ) == false
        )
        #expect(
            BranchResolver.shouldSilentlyRetry(
                after: .serverError(status: 502), attemptedBranch: "feature/x", defaultBranch: "main"
            ) == false
        )
    }

    // MARK: - 删除判据（决策 #53）

    @Test("⚠️ 删除入口的判据是**非默认 且 非受保护**，缺一不可")
    func canDeleteRequiresNotDefaultAndNotProtected() {
        let defaultBranch = BranchSummary(name: "main", commitSHA: "a")
        let protected = BranchSummary(name: "release", commitSHA: "b", isProtected: true)
        let deletable = BranchSummary(name: "feature/x", commitSHA: "c")

        #expect(defaultBranch.canDelete(defaultBranch: "main") == false)
        // ⚠️ 这条是决策 #53 的全部要点：服务端对受保护分支**直接拒绝**，
        //    照 PRD 原话"非默认就画"会给出一个必然报错的按钮。
        #expect(protected.canDelete(defaultBranch: "main") == false)
        #expect(deletable.canDelete(defaultBranch: "main"))
    }

    @Test("不给删除入口的**原因**分成两类（两句提示含义不同，不能合成一句）")
    func deleteBlockReasonDistinguishesTheTwo() {
        let defaultBranch = BranchSummary(name: "main", commitSHA: "a")
        let protected = BranchSummary(name: "release", commitSHA: "b", isProtected: true)

        #expect(defaultBranch.deleteBlockReason(defaultBranch: "main") == .defaultBranch)
        #expect(protected.deleteBlockReason(defaultBranch: "main") == .protected)
        #expect(defaultBranch.deleteBlockReason(defaultBranch: "dev") == nil)

        #expect(
            BranchCopy.defaultBranchBlockedToast(branch: "main").contains("默认分支")
        )
        #expect(
            BranchCopy.protectedBranchBlockedToast(branch: "release").contains("受保护")
        )
    }

    @Test("⚠️ 未合并判定只读 `aheadBy`（`commits` 数组会被服务端截断，数它必错）")
    func unmergedJudgementUsesAheadByOnly() {
        let clean = RepoComparison(status: .identical, aheadBy: 0, behindBy: 0, totalCommits: 0)
        let dirty = RepoComparison(status: .ahead, aheadBy: 3, behindBy: 0, totalCommits: 3)

        #expect(clean.hasUnmergedCommits == false)
        #expect(dirty.hasUnmergedCommits)

        // 阻止删除时的提示带上具体条数（用户要知道挡他的是什么量级）。
        #expect(BranchCopy.unmergedBlockedToast(branch: "feature/x", aheadBy: 3).contains("3"))
    }

    // MARK: - 记忆存储

    @Test("按仓库全名分桶 —— **绝不跨仓库**（PRD §3.10 的核心约束）")
    func memoryIsScopedPerRepository() async {
        let store = InMemoryBranchMemoryStore()

        await store.remember(branch: "feature/x", for: "my-git/gitduo")
        await store.remember(branch: "gh-pages", for: "my-git/notes")

        #expect(await store.branch(for: "my-git/gitduo") == "feature/x")
        #expect(await store.branch(for: "my-git/notes") == "gh-pages")
        // 没记过的仓库是 `nil`（而不是"最近一次用过的分支"）。
        #expect(await store.branch(for: "rust-lang/rust") == nil)
    }

    @Test("`forget` 抹掉一条、不动别的；`clear` 清空全部（登出走的就是后者）")
    func forgetAndClear() async {
        let store = InMemoryBranchMemoryStore(seed: ["a/b": "main", "c/d": "dev"])

        await store.forget(fullName: "a/b")
        #expect(await store.branch(for: "a/b") == nil)
        #expect(await store.branch(for: "c/d") == "dev")

        await store.clear()
        #expect(await store.branch(for: "c/d") == nil)
    }

    @Test("⚠️ 记忆落的是**分支名**，不是一个全局的「当前分支」—— 切回去能恢复现场")
    func memoryRestoresContextWhenSwitchingBack() async {
        let store = InMemoryBranchMemoryStore()

        await store.remember(branch: "develop", for: "my-git/gitduo")
        await store.remember(branch: "gh-pages", for: "my-git/notes")
        // 回到第一个仓库：拿到的是它自己那条，不是最后写的那条。
        #expect(await store.branch(for: "my-git/gitduo") == "develop")
    }
}
