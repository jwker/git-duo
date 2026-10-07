import Testing
import Foundation
import GitHubAPI
@testable import GitDuoKit

/// `LoadState` —— 一次性取数的加载态（§8.5 三档）。
///
/// 这里钉住的都是"写错了会看起来很正常"的几条：
/// 首帧不得说"没有数据"、失败态不得被读成有值、`idle` 与 `loading` 必须同貌。
@Suite("LoadState · 一次性取数的加载态")
struct LoadStateTests {

    private typealias State = LoadState<[String]>

    /// 只为造一个"底层错误"用的最小类型 —— `GitHubError.decoding` 收 `any Error`。
    private struct Boom: Error, Equatable { let detail: String }

    // MARK: - 首帧

    @Test("⚠️ idle 与 loading 都是骨架屏 —— 不得让首帧闪一下「还没有数据」")
    func idleAndLoadingBothSkeleton() {
        let idle: State = .idle
        let loading: State = .loading

        #expect(idle.presentation == .skeleton)
        #expect(loading.presentation == .skeleton)
    }

    @Test("idle 与 loading 都算「还没完成」")
    func notFinishedBeforeResult() {
        #expect(State.idle.hasFinished == false)
        #expect(State.loading.hasFinished == false)
    }

    // MARK: - 成功

    @Test("成功 ⇒ 有值 + 内容态；空数组也是「有内容」")
    func loadedCarriesValue() {
        // ⚠️ 空数组**必须**是 .content —— 空态文案由调用方按自己的措辞渲染
        //    （置顶说「还没有置顶仓库」，贡献者说「还没有贡献者」），
        //    状态机不知道这些词，也就不该替它们决定。
        let empty: State = .loaded([])
        #expect(empty.presentation == .content)
        #expect(empty.value == [])
        #expect(empty.error == nil)

        let full: State = .loaded(["a", "b"])
        #expect(full.presentation == .content)
        #expect(full.value == ["a", "b"])
        #expect(full.hasFinished)
    }

    // MARK: - 失败

    @Test("失败 ⇒ 带上错误 + 失败态，且**读不出值**")
    func failedCarriesError() {
        let offline = GitHubError.transport(URLError(.notConnectedToInternet))
        let state: State = .failed(offline)

        guard case let .failure(error) = state.presentation else {
            Issue.record("失败态必须映射到 .failure")
            return
        }
        #expect(error == offline)
        // ⚠️ 从失败态里"抠"出一份旧值继续用，正是"断网 ≠ 登出"要挡的那类谎报。
        #expect(state.value == nil)
        #expect(state.hasFinished)
    }

    @Test("失败**不代表**在加载 —— 否则界面会永远转圈")
    func failureIsNotLoading() {
        let throttled = GitHubError.rateLimited(resetAt: Date(), isSecondary: false)
        #expect(State.failed(throttled).isLoading == false)
    }

    // MARK: - 迁移

    @Test("迁移：begin → succeed / fail，reset 回 idle")
    func transitions() {
        var state: State = .idle

        state.begin()
        #expect(state.isLoading)
        #expect(state.presentation == .skeleton)

        state.succeed(["x"])
        #expect(state.value == ["x"])
        #expect(state.isLoading == false)

        state.begin()
        state.fail(.decoding(Boom(detail: "形状不对")))
        #expect(state.error != nil)
        #expect(state.value == nil)

        state.reset()
        #expect(state.presentation == .skeleton)
        #expect(state.hasFinished == false)
    }

    @Test("失败后再次 begin ⇒ 清掉上一次的错误（不显示过期报错）")
    func beginClearsPreviousError() {
        var state: State = .failed(.transport(URLError(.timedOut)))
        state.begin()

        #expect(state.error == nil)
        #expect(state.isLoading)
    }
}
