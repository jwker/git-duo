import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// Star 的**可写范围**：一个仓库点得动那颗星标吗（TECH_SPEC **§3.5.5**、决策 **#80**）。
///
/// ## 这组断言守的是"**别替用户断言一件没有依据的事**"
///
/// 真因是实测出来的：GitHub App 的用户令牌**写 Star 只对「App 安装范围内的仓库」有效**
/// （自己的仓库 204、别人的仓库 403 `Resource not accessible by integration`）⇒
/// 界面要如实说出来，而不是让用户白点一下再收到 `操作失败 · 请重试`。
///
/// 而"如实"在这件事上**只能做到一半**：我们手里能查到的是"哪些账号装了 GitDuo"，
/// 查不到的比查得到的多（安装可能只勾了部分仓库；这一次查询还可能失败）。
/// ⇒ 规则定成 **只有"确定不可写"才拦**，其余一律放行 —— 下面每一条断言都在钉这一点。
@Suite("Star 可写范围 · 判定 / 取数 / 缓存")
struct StarWriteScopeTests {

    // MARK: - 判定

    @Test("⚠️ `.unknown`（还没查到）⇒ 一律不拦")
    func unknownNeverBlocks() {
        let scope = StarWriteScope.unknown

        #expect(scope.canWrite(fullName: "jwker/my-blog"))
        #expect(scope.canWrite(fullName: "github/gitignore"))
    }

    @Test("查到了、owner 在名单里 ⇒ 可写")
    func knownAccountIsWritable() {
        let scope = StarWriteScope.known(accounts: ["jwker"])

        #expect(scope.canWrite(fullName: "jwker/my-blog"))
    }

    @Test("⚠️ 查到了、owner 不在名单里 ⇒ **拦**（唯一会拦的一档）")
    func unknownAccountIsBlocked() {
        let scope = StarWriteScope.known(accounts: ["jwker"])

        // 就是实测里那两条 403（别人的仓库）。
        #expect(!scope.canWrite(fullName: "github/gitignore"))
        #expect(!scope.canWrite(fullName: "robbietilton/Compositor"))
    }

    @Test(
        "⚠️ 比较**大小写不敏感** —— GitHub 登录名本身不分大小写",
        arguments: ["jwker/my-blog", "JWKER/my-blog", "Jwker/My-Blog"]
    )
    func comparisonIsCaseInsensitive(_ fullName: String) {
        // ⚠️ 按 `==` 比会让"自己名下的仓库"认不出自己，
        //    而那一条在屏幕上**看起来完全正常**（只是按钮莫名其妙是灰的）。
        #expect(StarWriteScope.known(accounts: ["jwker"]).canWrite(fullName: fullName))
        #expect(StarWriteScope.known(accounts: ["JWKER"]).canWrite(fullName: fullName))
    }

    @Test("⚠️ `owner/name` 形状不认识 ⇒ **不拦**（那是另一类问题的症状，别在这里表现成「不能 Star」）")
    func malformedFullNameIsNotBlocked() {
        let scope = StarWriteScope.known(accounts: ["jwker"])

        for fullName in ["noSlash", "a/b/c", "/name", "owner/", ""] {
            #expect(scope.canWrite(fullName: fullName), "`\(fullName)` 不该被拦")
        }
    }

    @Test("一个安装都没有 ⇒ 什么都写不了（但这一档现实里不该出现 —— 能登录就说明装过）")
    func emptyAccountListBlocksEverything() {
        let scope = StarWriteScope.known(accounts: [])

        #expect(!scope.canWrite(fullName: "jwker/my-blog"))
        #expect(!scope.canWrite(fullName: "github/gitignore"))
    }

    @Test("多个安装（自己 + 组织）时，两边的仓库都可写")
    func multipleAccountsAreAllWritable() {
        let scope = StarWriteScope.known(accounts: ["jwker", "my-git"])

        #expect(scope.canWrite(fullName: "jwker/my-blog"))
        #expect(scope.canWrite(fullName: "my-git/gitduo"))
        #expect(!scope.canWrite(fullName: "github/gitignore"))
    }

    // MARK: - 取数

    @Test("成功 ⇒ `.known`（账号名来自端点）")
    func loaderSucceeds() async {
        let source = ScriptedScopeSource(result: .success(["jwker", "my-git"]))

        let scope = await LoadStarWriteScope(source: source).run()

        #expect(scope == .known(accounts: ["jwker", "my-git"]))
    }

    @Test("⚠️ 失败 ⇒ 折叠成 `.unknown`，**不抛错**（这次查询失败不该让任何页面打不开）")
    func loaderFoldsFailureIntoUnknown() async {
        let source = ScriptedScopeSource(result: .failure(GitHubError.transport(
            URLError(.notConnectedToInternet)
        )))

        let scope = await LoadStarWriteScope(source: source).run()

        #expect(scope == .unknown)
        #expect(scope.canWrite(fullName: "github/gitignore"), "不知道就别拦")
    }

    // MARK: - 缓存

    @Test("成功 ⇒ 缓存；第二次不再打请求（这一份名单一个会话里基本不变）")
    func cacheHitsAfterSuccess() async {
        let source = ScriptedScopeSource(result: .success(["jwker"]))
        let cache = StarWriteScopeCache(loader: LoadStarWriteScope(source: source))

        _ = await cache.current()
        _ = await cache.current()

        #expect(await source.callCount == 1)
    }

    @Test("⚠️ 失败 ⇒ **不缓存**（缓存一次失败等于把它变成永久失败：之后再没有一次查询会重试）")
    func cacheDoesNotStoreFailure() async {
        let source = ScriptedScopeSource(result: .failure(GitHubError.notFound))
        let cache = StarWriteScopeCache(loader: LoadStarWriteScope(source: source))

        let first = await cache.current()
        let second = await cache.current()

        #expect(first == .unknown)
        #expect(second == .unknown)
        #expect(await source.callCount == 2, "第一次没问到 ⇒ 第二次要再问一次")
    }

    @Test("两处同时问 ⇒ **共用同一次在途请求**（不打两次）")
    func cacheSharesInFlightRequest() async {
        let source = GatedScopeSource(accounts: ["jwker"])
        let cache = StarWriteScopeCache(loader: LoadStarWriteScope(source: source))

        async let first = cache.current()
        async let second = cache.current()

        // ⚠️ 这里等的是 **1**，不是 2 —— 而这是一个踩过的坑，别"顺手改大"：
        //    本用例要证的就是"两处只打**一次**源调用"，所以源被调用的次数**永远到不了 2**；
        //    写成 `waitForCallers(2)` 会让这个测试**永久挂住**（`swift-testing` 默认没有超时，
        //    表现是整套 `make test-…` 卡死、一个字都不打印，看起来像"编译很慢"）。
        //    要等的是"**那唯一一次**请求真的飞起来了"，不是"两个调用者都进来了"。
        await source.waitForCallers(1)
        await source.open()

        let scopes = await [first, second]
        #expect(scopes == [.known(accounts: ["jwker"]), .known(accounts: ["jwker"])])
        #expect(await source.callCount == 1)
    }

    @Test("`clear()` 之后重新问一次（登出 / 换账号）")
    func clearForcesRefetch() async {
        let source = ScriptedScopeSource(result: .success(["jwker"]))
        let cache = StarWriteScopeCache(loader: LoadStarWriteScope(source: source))

        _ = await cache.current()
        await cache.clear()
        _ = await cache.current()

        #expect(await source.callCount == 2)
    }

    @Test("⚠️⚠️ `clear()` 期间那次在途请求，结果**不许写回缓存**（那是上一个账号的授权范围）")
    func clearDuringInFlightDiscardsResult() async {
        let source = GatedScopeSource(accounts: ["jwker"])
        let cache = StarWriteScopeCache(loader: LoadStarWriteScope(source: source))

        // 第一次查询已经在飞（还没回来）。
        let inFlight = Task { await cache.current() }
        await source.waitForCallers(1)

        // 用户在那一刻登出了。
        await cache.clear()

        // 旧账号的答案现在才回来。
        await source.open()
        _ = await inFlight.value

        // ⇒ 下一次问必须是**真的一次新请求**。少了那道代次比对，
        //    这里会命中被写回的旧缓存（`callCount` 停在 1），
        //    表现是"新账号的界面按上一个账号的授权范围画按钮"。
        let scope = await cache.current()
        #expect(await source.callCount == 2)
        #expect(scope == .known(accounts: ["jwker"]), "第二次拿到的是新请求的答案")
    }

    // MARK: - 替身

    /// 脚本化的取数：一次成功 / 一次失败，记录被问了几次。
    private actor ScriptedScopeSource: StarScopeDataSource {

        private let result: Result<[String], any Error>
        private(set) var callCount = 0

        init(result: Result<[String], any Error>) {
            self.result = result
        }

        func installedAccounts() async throws -> [String] {
            callCount += 1
            return try result.get()
        }
    }

    /// 可以"卡住"的取数 —— 用来把"在途那一刻"变成一个可断言的状态。
    private actor GatedScopeSource: StarScopeDataSource {

        private let accounts: [String]
        private(set) var callCount = 0
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var arriving: [CheckedContinuation<Void, Never>] = []

        init(accounts: [String]) {
            self.accounts = accounts
        }

        func installedAccounts() async throws -> [String] {
            callCount += 1
            resumeArriving()
            if !isOpen {
                await withCheckedContinuation { waiters.append($0) }
            }
            return accounts
        }

        /// 等到"已经有 n 个调用者进来了"。
        ///
        /// ## ⚠️ `n` 写大了会让整个测试套件**永久挂住**（不是失败）
        ///
        /// `swift-testing` 默认**没有超时**：`callCount` 到不了 `n` 就永远等下去，
        /// 而外部看到的只是"命令一直不结束、一个字不打印"—— 最容易被误读成"编译慢"。
        /// ⇒ 用时先数清**这段代码最多会打到源几次**，`n` 不能超过它。
        /// （`cacheSharesInFlightRequest` 那条正是踩在这里：它的要害是"只打一次"。）
        func waitForCallers(_ n: Int) async {
            while callCount < n {
                await withCheckedContinuation { arriving.append($0) }
            }
        }

        /// 放行所有卡住的调用。
        func open() {
            isOpen = true
            let pending = waiters
            waiters = []
            for waiter in pending { waiter.resume() }
        }

        private func resumeArriving() {
            let pending = arriving
            arriving = []
            for waiter in pending { waiter.resume() }
        }
    }
}
