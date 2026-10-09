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

    /// 可切换的年份（当前年在第一位）—— 2026-10-09 加，用户走查第 2 条。
    ///
    /// ⚠️ 由**取数那一侧**给出（`LoadProfileOverview.years`），视图不自己算年份：
    /// 窗口怎么算是本片唯一的日期算法，摆两处就会有一天出现"菜单写着 2025、取的是 2024"。
    var years: [ContributionYear] { loader.years }

    /// 进页：**只在还没取到过时**取一次（取的是**当前年**）。
    ///
    /// 与 `HomeViewModel.loadPinnedIfNeeded` 同一处置：从仓库详情返回时
    /// `.task` 未必会重跑（根视图并没有离开视图树），所以这一层不能靠"每次出现都重取"
    /// 来保证新鲜 —— 那既会白扣 GraphQL 的点，也会让返回首页时闪一下骨架。
    func loadIfNeeded() async {
        guard overview == nil else { return }
        await load(year: loader.currentYear)
    }

    /// 重取（首屏重试 / 下拉刷新共用）—— 取的是**当前屏幕上那一年**。
    ///
    /// ⚠️ 不是"当前年"：看完 2024 之后下拉，用户要的是"2024 再取一次"。
    /// 用当前年会让下拉**把年份改掉**，而那是一次没人要求的跳转。
    func refresh() async {
        await load(year: overview?.year ?? loader.currentYear)
    }

    /// 切换到某一年（年份切换器）。
    ///
    /// ⚠️ 点了同一年**不发请求**：`Menu` 里那一项就在手边，误触很常见，
    /// 而"点了一下自己"发一次 GraphQL 是白扣 1 点。
    func select(year: ContributionYear) async {
        guard year != overview?.year else { return }
        await load(year: year)
    }

    /// 重取某一年的两路（**唯一**改 `overview` 的地方）。
    ///
    /// ⚠️ 已有内容时**不切回骨架**：`overview` 只在拿到新结果时才被替换 ——
    /// 与 `PagedListState` 那条"下拉刷新不遮挡已有内容"（§8.5）同一条纪律。
    /// 这一页的失败是**分块**的（热力图卡片内一行灰字），所以也不需要"失败后清空"。
    ///
    /// ⚠️ 在途时再点一次（换年份 / 下拉）会被这里挡掉 —— **不排队**：
    /// 排队意味着"快速点三下会发三次请求、且最后停在第三次"，而每次都是 1 点；
    /// 挡住则最多浪费一次点击。切年份是低频动作，这个取舍偏"少花配额"。
    private func load(year: ContributionYear) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        overview = await loader.load(year: year)
    }
}
