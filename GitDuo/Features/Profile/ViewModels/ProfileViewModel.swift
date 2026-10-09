import Foundation
import GitHubAPI
import GitDuoKit

/// 「我的」页的状态（PRD §4.17、TECH_SPEC §9.14）。
///
/// ## 它只持有一份 `ProfileOverview`，没有 `LoadState`
///
/// 因为这一页**不存在"整页失败"**：`LoadProfileOverview.load()` 自己就把两路取数
/// 折进了返回值（`identity` / `grid` 各自是 `ProfileSection`，`stats` 逐项可空），
/// 而且它**不 throw**。所以这里没有 `.failed` 这一档可放 ——
/// 硬塞一个 `LoadState` 会造出一个永远不会出现的分支。
///
/// 于是"还没取到"由 `overview == nil` 表示（首帧渲染骨架），
/// 而"某一块没取到"由 `overview` **里面**那几个 `ProfileSection` 表示。
///
/// ## ⚠️ 头像与 `@登录名` 不在这里
///
/// 它们由视图从 `authState` 的登录名现画（`ProfileHeader(login:)`）——
/// 那两样东西**不可能失败**，也不该跟着任何一路取数一起变灰（决策 #76 末句）。
@MainActor
@Observable
final class ProfileViewModel {

    /// 最近一次取数的结果；`nil` = 还没取到（首帧）。
    private(set) var overview: ProfileOverview?

    /// 请求在途（含下拉刷新那一档）。
    private(set) var isLoading = false

    private let loader: LoadProfileOverview

    init(loader: LoadProfileOverview) {
        self.loader = loader
    }

    /// 进页：**只在还没取到过时**取一次。
    ///
    /// 与 `HomeViewModel.loadPinnedIfNeeded` 同一处置：从仓库详情返回时
    /// `.task` 未必会重跑（根视图并没有离开视图树），所以这一层不能靠"每次出现都重取"
    /// 来保证新鲜 —— 那既会白扣 GraphQL 的点，也会让返回首页时闪一下骨架。
    func loadIfNeeded() async {
        guard overview == nil else { return }
        await load()
    }

    /// 重取两路（首屏重试 / 下拉刷新共用）。
    ///
    /// ⚠️ 已有内容时**不切回骨架**：`overview` 只在拿到新结果时才被替换 ——
    /// 与 `PagedListState` 那条"下拉刷新不遮挡已有内容"（§8.5）同一条纪律。
    /// 这一页的失败是**分块**的（热力图卡片内一行灰字），所以也不需要"失败后清空"。
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        overview = await loader.load()
    }
}
