import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 列表加载状态机（TECH_SPEC §4.4 / §8.5）。
@Suite("PagedListState · 加载 / 追加 / 去重 / 失败")
struct PagedListStateTests {

    private struct Row: Identifiable, Sendable, Equatable {
        let id: String
    }

    private func page(_ ids: [String], next: String? = nil) -> Page<Row> {
        Page(
            items: ids.map(Row.init(id:)),
            nextCursor: next.flatMap(URL.init(string:)),
            headers: HTTPHeaders([:])
        )
    }

    // MARK: - 首帧

    @Test("⚠️ 初始状态是**骨架屏**，不是空态 —— 否则首帧会闪一下「还没有仓库」")
    func initialStateIsSkeleton() {
        let state = PagedListState<Row>()

        #expect(state.content() == .skeleton)
        #expect(state.items.isEmpty)
        #expect(!state.isLoading)
        #expect(!state.canLoadMore)
        #expect(state.error == nil)
        // 这条看着无聊，其实守着一个很显眼的瑕疵：`items` 空 + `isLoading` 假
        // 天然会被读成"已经加载过、确实没有"。而"还没开始"是另一回事。
    }

    @Test("开始加载（空列表）仍是骨架屏，不会先渲染成空态再变")
    func loadingKeepsSkeleton() {
        var state = PagedListState<Row>()

        state.beginLoad(reset: false)

        #expect(state.isLoading)
        #expect(state.content() == .skeleton)
    }

    // MARK: - 收到数据

    @Test("收到一页：条目落地，`canLoadMore` 取自 nextCursor，清掉 isLoading")
    func receivesPage() {
        var state = PagedListState<Row>()

        state.beginLoad(reset: false)
        state.received(page(["a", "b"], next: "https://api.github.com/x?page=2"))

        #expect(state.items.map(\.id) == ["a", "b"])
        #expect(state.canLoadMore)
        #expect(!state.isLoading)
        #expect(state.content() == .items)
    }

    @Test("没有 nextCursor ⇒ 到底了（`canLoadMore` 必须是假，否则会一直转圈）")
    func lastPageStopsLoadingMore() {
        var state = PagedListState<Row>()
        state.beginLoad(reset: false)

        state.received(page(["a"]))

        #expect(!state.canLoadMore)
    }

    @Test("续页**追加**而不是替换（替换会让用户每次滚到底都只剩一页）")
    func secondPageAppends() {
        var state = PagedListState<Row>()
        state.received(page(["a", "b"], next: "https://api.github.com/x?page=2"))

        state.beginLoad(reset: false)
        state.received(page(["c"], next: "https://api.github.com/x?page=3"))

        #expect(state.items.map(\.id) == ["a", "b", "c"])
        #expect(state.canLoadMore)
    }

    // MARK: - 去重

    @Test(
        "按 id 去重：同一条跨页重复出现时只留一份（`sort=updated` 下这事真的会发生）",
        arguments: [["b", "c"], ["a", "b"], ["c", "d"]]
    )
    func deduplicatesAcrossPages(_ secondPage: [String]) {
        var state = PagedListState<Row>()
        state.received(page(["a", "b"], next: "https://api.github.com/x?page=2"))

        state.beginLoad(reset: false)
        state.received(page(secondPage, next: nil))

        let ids = state.items.map(\.id)
        #expect(Set(ids).count == ids.count, "重复 id 会让 ForEach 报重复标识，视觉上是重复行")
    }

    @Test("去重保留**先出现的那一份**：已渲染的行不会因为后一页而换掉")
    func dedupeKeepsFirstOccurrence() {
        var state = PagedListState<Row>()
        state.received(page(["a"], next: "https://api.github.com/x?page=2"))

        state.beginLoad(reset: false)
        state.received(page(["a"], next: nil))

        #expect(state.items.map(\.id) == ["a"])
    }

    // MARK: - 下拉刷新

    @Test("⚠️ 下拉刷新期间**不清空**已有条目（§8.5：分页 / 刷新不得遮挡已有内容）")
    func refreshKeepsContentOnScreen() {
        var state = PagedListState<Row>()
        state.received(page(["a", "b"], next: "https://api.github.com/x?page=2"))

        state.beginLoad(reset: true)

        #expect(state.items.map(\.id) == ["a", "b"], "先清空会让整屏塌成骨架，且刷新失败后内容全没了")
    }

    @Test("下拉刷新完成后**整体替换**，不是追加")
    func refreshReplaces() {
        var state = PagedListState<Row>()
        state.received(page(["a", "b"], next: "https://api.github.com/x?page=2"))

        state.beginLoad(reset: true)
        state.received(page(["z"], next: nil))

        #expect(state.items.map(\.id) == ["z"])
        #expect(!state.canLoadMore)
    }

    @Test("下拉刷新失败：旧内容**留在屏幕上**，只是多了一条错误")
    func failedRefreshKeepsOldItems() {
        var state = PagedListState<Row>()
        state.received(page(["a", "b"]))

        state.beginLoad(reset: true)
        state.failed(.transport(URLError(.notConnectedToInternet)))

        #expect(state.items.map(\.id) == ["a", "b"])
        #expect(state.error != nil)
        #expect(state.content() == .items, "有内容时失败不该把整页换成错误页")
    }

    // MARK: - 失败

    @Test("首屏失败（列表为空）⇒ 整页失败态")
    func firstPageFailure() {
        var state = PagedListState<Row>()

        state.beginLoad(reset: false)
        state.failed(.serverError(status: 500))

        #expect(state.content() == .failure(.serverError(status: 500)))
        #expect(!state.isLoading)
    }

    @Test("分页失败**不动 `canLoadMore`** —— 清掉它用户就永远没有重试入口了")
    func pageFailureKeepsLoadMore() {
        var state = PagedListState<Row>()
        state.received(page(["a"], next: "https://api.github.com/x?page=2"))

        state.beginLoad(reset: false)
        state.failed(.serverError(status: 502))

        #expect(state.canLoadMore)
        #expect(state.items.map(\.id) == ["a"])
    }

    // MARK: - 空态 vs 还有下一页

    @Test("⚠️ 空、但还有下一页 ⇒ `.needsMore`，**不得**断言「还没有」")
    func emptyWithMoreIsNotAnEmptyState() {
        var state = PagedListState<Row>()

        state.beginLoad(reset: false)
        // 这一页恰好没有该段的条目（本地过滤的结果），但服务端还有下一页
        state.received(page([], next: "https://api.github.com/x?page=2"))

        #expect(state.content() == .needsMore)
        // 这是本地过滤三段的必然产物：空列表 + canLoadMore 时若显示「还没有公开仓库」，
        // 那是在说一句还没查完就下的结论。
    }

    @Test("空、且已到底 ⇒ `.empty`（此时才可以说「还没有…」）")
    func emptyAtEndIsEmptyState() {
        var state = PagedListState<Row>()

        state.beginLoad(reset: false)
        state.received(page([], next: nil))

        #expect(state.content() == .empty)
    }

    // MARK: - 重置

    @Test("`reset()` 回到初始态（登出 / 切换账号时用）")
    func resetReturnsToInitial() {
        var state = PagedListState<Row>()
        state.received(page(["a"], next: "https://api.github.com/x?page=2"))

        state.reset()

        #expect(state.items.isEmpty)
        #expect(!state.canLoadMore)
        #expect(state.content() == .skeleton)
    }

    // MARK: - 过滤后的渲染形态

    @Test("⚠️ 判断「有没有内容」必须看**过滤后**的结果：原始条目非空、但当前过滤命中零条时不是 `.items`")
    func contentRespectsFilter() {
        var state = PagedListState<Row>()
        state.beginLoad(reset: false)
        state.received(page(["a", "b"], next: nil))

        #expect(state.content(matching: { _ in true }) == .items)
        #expect(
            state.content(matching: { _ in false }) == .empty,
            "过滤命中零条时若仍返回 .items，界面会渲染一个「有内容但一条都不显示」的空列表"
        )
    }

    @Test("过滤命中零条、但还有下一页 ⇒ `.needsMore`（不能断言「还没有」）")
    func filteredEmptyWithMoreNeedsMore() {
        var state = PagedListState<Row>()
        state.beginLoad(reset: false)
        state.received(page(["a", "b"], next: "https://api.github.com/x?page=2"))

        #expect(state.content(matching: { _ in false }) == .needsMore)
    }
}
