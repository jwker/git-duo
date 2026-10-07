import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// Star 的领域用例：**先确认基准，再幂等切换**（决策 #41、PRD §4.13）。
///
/// ## 这组断言守的是"多算一颗星"与"把话说反"
///
/// `PUT` / `DELETE /user/starred/{o}/{r}` 两个端点都只回 **204**，
/// 响应里**没有新计数** —— 所以本地 `±1` 必须先知道**操作前的状态**。
/// 不加这一步的话，一个你已经 Star 过、共 100 星的仓库会按"未 Star"起手显示
/// `Star · 100`；点一下发出的是被服务端忽略的幂等请求，界面却显示成
/// `已 Star · 101` —— 既多算一颗，也把"你已经 Star 过"这件事说反了。
///
/// 另一件是**失败不许静默吞掉**：进页那次基准查询失败**不抛错**（不该让整页打不开），
/// 但用户真去点的时候，补查询仍然失败就必须**带着错误收场**，且**一个计数也不许动**。
@Suite("Star · 基准确认与幂等切换")
struct StarToggleTests {

    // MARK: - 数据源替身

    /// 脚本化的 Star 端点 —— 记录**每一次**读写调用，因为"有没有多发一次写请求"
    /// 正是这组断言的要点（幂等端点写错了不会报错，只会让计数悄悄多一颗）。
    private actor ScriptedStarSource: StarDataSource {

        private var starred: Bool
        private var readFailure: GitHubError?
        private var writeFailure: GitHubError?

        private(set) var readCount = 0
        private(set) var starCalls = 0
        private(set) var unstarCalls = 0

        init(starred: Bool) { self.starred = starred }

        func failRead(with error: GitHubError) { readFailure = error }
        func failWrite(with error: GitHubError) { writeFailure = error }

        /// 让下一次读恢复成功（模拟"网络回来了，用户这才点了那一下"）。
        func clearReadFailure() { readFailure = nil }

        func isStarred(owner: String, repo: String) async throws -> Bool {
            readCount += 1
            if let readFailure { throw readFailure }
            return starred
        }

        func star(owner: String, repo: String) async throws {
            starCalls += 1
            if let writeFailure { throw writeFailure }
            starred = true
        }

        func unstar(owner: String, repo: String) async throws {
            unstarCalls += 1
            if let writeFailure { throw writeFailure }
            starred = false
        }
    }

    private let offline = GitHubError.transport(URLError(.notConnectedToInternet))

    // MARK: - 进页确认基准

    @Test("进页成功 ⇒ 基准已确认，`isStarred` 照服务端")
    func initialStateConfirmsBaseline() async {
        let source = ScriptedStarSource(starred: true)

        let state = await ToggleStar(source: source).initialState(fullName: "a/b", starCount: 100)

        #expect(state.baselineConfirmed)
        #expect(state.isStarred)
        #expect(state.starCount == 100)
        #expect(await source.readCount == 1)
    }

    @Test("⚠️ 进页查询失败 ⇒ **不抛错**，只把基准标成未确认（不该让整个详情页打不开）")
    func initialStateFailureDegradesInsteadOfThrowing() async {
        let source = ScriptedStarSource(starred: true)
        await source.failRead(with: offline)

        let state = await ToggleStar(source: source).initialState(fullName: "a/b", starCount: 100)

        #expect(!state.baselineConfirmed, "基准没拿到就别说已确认")
        #expect(!state.isStarred, "⚠️ 不许谎称已 Star —— 显示成未激活的 `Star · {n}`")
        #expect(state.starCount == 100, "星数来自详情，与基准查询无关，不该被抹掉")
    }

    // MARK: - 切换

    @Test("未 Star → Star：`+1`，动作是 `.starred`，**只发一次写**")
    func starIncrementsOnce() async throws {
        let source = ScriptedStarSource(starred: false)
        let toggle = ToggleStar(source: source)
        let current = await toggle.initialState(fullName: "a/b", starCount: 100)

        let (next, action) = try await toggle.toggle(current)

        #expect(next.isStarred)
        #expect(next.starCount == 101)
        #expect(action == .starred)
        #expect(await source.starCalls == 1)
        #expect(await source.unstarCalls == 0)
    }

    @Test("已 Star → 取消：`−1`，动作是 `.unstarred`，**只发一次写**")
    func unstarDecrementsOnce() async throws {
        let source = ScriptedStarSource(starred: true)
        let toggle = ToggleStar(source: source)
        let current = await toggle.initialState(fullName: "a/b", starCount: 100)

        let (next, action) = try await toggle.toggle(current)

        #expect(!next.isStarred)
        #expect(next.starCount == 99)
        #expect(action == .unstarred)
        #expect(await source.unstarCalls == 1)
        #expect(await source.starCalls == 0)
    }

    @Test("⚠️ 基准未确认时点击 ⇒ **先补一次基准查询**，而且按补到的真相走")
    func toggleRefreshesBaselineBeforeWriting() async throws {
        // 用户其实早已 Star 过（共 100 星），但进页那次基准查询失败了。
        let source = ScriptedStarSource(starred: true)
        await source.failRead(with: offline)
        let toggle = ToggleStar(source: source)

        let degraded = await toggle.initialState(fullName: "a/b", starCount: 100)
        #expect(!degraded.baselineConfirmed)
        #expect(!degraded.isStarred)          // 降级显示成"未 Star"

        // 网络恢复了，用户点了一下。
        await source.clearReadFailure()
        let (next, action) = try await toggle.toggle(degraded)

        // 真相是"已 Star" ⇒ 这一下应当是**取消**，而不是"新增一颗"。
        #expect(action == .unstarred, "按降级状态直接 +1 会把'你已经 Star 过'说反")
        #expect(next.starCount == 99)
        #expect(await source.readCount == 2, "补基准 = 第二次读")
        #expect(await source.starCalls == 0)
        #expect(await source.unstarCalls == 1)
    }

    @Test("⚠️ 基准补不上 ⇒ **抛错，且一个写请求都不发**")
    func toggleThrowsWhenBaselineCannotBeConfirmed() async {
        let source = ScriptedStarSource(starred: false)
        await source.failRead(with: offline)
        let toggle = ToggleStar(source: source)
        let degraded = await toggle.initialState(fullName: "a/b", starCount: 100)

        var threw = false
        do {
            _ = try await toggle.toggle(degraded)
        } catch {
            threw = true
        }

        #expect(threw)
        #expect(await source.starCalls == 0, "不知道基准就写，等于往屏幕上放一个没有依据的计数")
        #expect(await source.unstarCalls == 0)
    }

    @Test("⚠️ 写请求失败 ⇒ 抛错（调用方据此把按钮恢复可点并给 toast）")
    func writeFailurePropagates() async {
        let source = ScriptedStarSource(starred: false)
        await source.failWrite(with: offline)
        let toggle = ToggleStar(source: source)
        let current = await toggle.initialState(fullName: "a/b", starCount: 100)

        var threw = false
        do {
            _ = try await toggle.toggle(current)
        } catch {
            threw = true
        }

        #expect(threw)
    }

    @Test(
        "`fullName` 不是 `owner/name` 形状 ⇒ 抛错（两个动作都不许发出请求）",
        arguments: ["noSlash", "a/b/c", "/name", "owner/", ""]
    )
    func malformedFullNameThrows(_ fullName: String) async {
        let source = ScriptedStarSource(starred: false)
        let toggle = ToggleStar(source: source)
        let bogus = StarState(fullName: fullName, isStarred: false, starCount: 1, baselineConfirmed: true)

        var threw = false
        do {
            _ = try await toggle.toggle(bogus)
        } catch {
            threw = true
        }

        #expect(threw, "`\(fullName)` 应当被拒绝")
        #expect(await source.starCalls == 0)
    }

    // MARK: - 计数

    @Test("⚠️ 星数**永不为负**：0 星时取消 Star 显示 0，而不是 `Star · -1`")
    func starCountNeverGoesNegative() async throws {
        let source = ScriptedStarSource(starred: true)
        let toggle = ToggleStar(source: source)
        let current = await toggle.initialState(fullName: "a/b", starCount: 0)

        let (next, _) = try await toggle.toggle(current)

        #expect(next.starCount == 0)
    }

    @Test("构造时就把负数夹到 0（服务端计数与本地显示之间可能差一个窗口）")
    func initClampsNegativeCount() {
        #expect(StarState(fullName: "a/b", isStarred: false, starCount: -5,
                          baselineConfirmed: true).starCount == 0)
    }

    // MARK: - 文案

    @Test("按钮文案：`Star · {n}` / `已 Star · {n}`，且**千分位全量、不缩写**")
    func buttonTitleIsGroupedNotAbbreviated() {
        // ⚠️ 与仓库卡片上的 `2.3k` **有意不同**：卡片窄、要省宽度；
        //    头部这三个数是用户要读准的（2026-10-06 用户拍板）。
        #expect(StarCopy.buttonTitle(isStarred: false, starCount: 2_341) == "Star · 2,341")
        #expect(StarCopy.buttonTitle(isStarred: true, starCount: 2_341) == "已 Star · 2,341")
        #expect(!StarCopy.buttonTitle(isStarred: false, starCount: 2_341).contains("k"))
    }

    @Test("两句 toast 是「操作真的发生了」的唯一可见凭证（PRD §7）")
    func toastCopyIsPinned() {
        #expect(StarCopy.toast(for: .starred) == "已 Star · 公开星标，仓库计数 +1")
        // ⚠️ 这里的减号是 U+2212（真正的减号），不是连字符 —— 与 `+1` 的字宽对称。
        #expect(StarCopy.toast(for: .unstarred) == "已取消 Star · 仓库计数 −1")
        #expect(StarCopy.toast(for: .unstarred).contains("\u{2212}"))
    }

    @Test("读屏标签要把状态念出来（星形图标本身念不出「已 Star」）")
    func accessibilityLabelStatesTheStatus() {
        #expect(StarCopy.accessibilityLabel(isStarred: true, starCount: 12).contains("已 Star"))
        #expect(StarCopy.accessibilityLabel(isStarred: false, starCount: 12).contains("点按加星"))
    }
}
