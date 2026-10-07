import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 首页的状态（PRD §4.1 / TECH_SPEC §9.1）。
///
/// ## 它管两块，而这两块的加载节奏**不同**
///
/// | | 数据来源 | 是否出网 | 失败时 |
/// |---|---|---|---|
/// | 置顶仓库 | GraphQL `viewer.pinnedItems` | 是（一次查询） | 整块失败 + 重试出口 |
/// | 最近访问 | 本机（`UserDefaults`） | **否** | 不可能失败（读坏数据退化成空列表） |
///
/// 所以它们**各有各的状态**，不能合成一个 `LoadState` —— 那样"置顶还在转圈"会顺带让
/// 最近访问也显示骨架屏，而它其实早就读出来了。
///
/// ## 它不认识 SwiftUI，也不认识路由
///
/// 视图拿 `pinned` / `visits` 渲染，点哪一行、进哪个页面由视图决定（那里的决定
/// 依据写在 `HomeView.openRepo` 的注释里）。
@MainActor
@Observable
final class HomeViewModel {

    /// 置顶仓库。`idle` / `loading` 都渲染骨架屏（见 `LoadState.presentation`）。
    private(set) var pinned: LoadState<[RepoSummary]> = .idle

    /// 最近访问，最新在前。**最多 6 条**（上限由 `RecentVisitStore` 那一侧保证）。
    private(set) var visits: [RecentVisit] = []

    private let pinnedLoader: LoadPinnedRepositories
    private let visitStore: any RecentVisitStore

    /// 轻提示通道。**只用来报告"下拉刷新失败了"** —— 其余情况界面上都已有位置
    /// （失败态整块、空态框），不必再叠一条提示。
    ///
    /// 注入它而不是让视图去接 AsyncStream：失败发生在方法内部，
    /// 让视图"猜哪一次 await 失败了"是行不通的。
    private let toast: ToastCenter

    init(
        pinnedLoader: LoadPinnedRepositories,
        visitStore: any RecentVisitStore,
        toast: ToastCenter
    ) {
        self.pinnedLoader = pinnedLoader
        self.visitStore = visitStore
        self.toast = toast
    }

    // MARK: - 读

    /// 首屏：只在**没取过**的时候取。
    func loadPinnedIfNeeded() async {
        guard !pinned.hasFinished else { return }
        await loadPinned()
    }

    /// 从本机读最近访问。
    ///
    /// ⚠️ **写入方不会通知首页**（`RecentVisitStore` 刻意不含观察入口，见其类型说明）——
    /// 否则"进入详情页写入 → 首页重绘 → 再写入"会成环。
    /// 所以首页在**每次重新出现时**主动读一次，这也是唯一能读到新记录的方式。
    func reloadVisits() async {
        visits = await visitStore.visits()
    }

    // MARK: - 用户动作

    /// 下拉刷新（PRD §4.1 空态引导里的"回到首页下拉即可看到"）。
    func refresh() async {
        await loadPinned()
        await reloadVisits()
    }

    /// 「清除」确认后的动作（§5.1）。
    func clearVisits() async {
        await visitStore.clear()
        await reloadVisits()
        toast.show(HomeCopy.recentCleared)
    }

    // MARK: - 内部

    private func loadPinned() async {
        // ⚠️ 已有内容时**不切到 loading**：那会让下拉刷新把网格整块换回骨架屏，
        //    而 §8.5 明写"分页 / 下拉刷新不遮挡已有内容"。
        let hadContent = pinned.value != nil
        if !hadContent { pinned.begin() }

        do {
            pinned.succeed(try await pinnedLoader.load())
        } catch {
            let failure = Self.failure(from: error)
            if hadContent {
                // 有内容 ⇒ 留着，不把它换成失败屏；但**不静默吞掉**，给一条提示。
                toast.show(HomeCopy.refreshFailed)
            } else {
                pinned.fail(failure)
            }
        }
    }

    /// 把任意错误收敛成 `GitHubError`。
    ///
    /// ⚠️ 映射失败归 `.decoding`（响应形状不对），**不是** `.transport` ——
    /// 报成网络问题会让界面提示"检查网络"，而网络其实是好的。
    /// 这与 `RepoListViewModel.failure(from:)` 是同一口径（两处都写，因为两处都无法共享
    /// —— `GitHubError` 的收敛属 App 层的错误呈现策略，不在领域包）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}

/// 首页的可见文案（PRD §4.1 / §7）。
///
/// ## 为什么单开一个枚举，而不是写进视图
///
/// 与 `RecentVisitStore` 的取向一致：**App target 没有测试 target**。
/// 收在一处至少能让"同一句话散落好几处、改了一处漏了三处"变得不可能 ——
/// 本项目已经因为这件事返工过一次（`AGENTS.md §5.3`）。
enum HomeCopy {

    static let title = "首页"

    static let pinnedSection = "置顶仓库"
    static let pinnedManage = "管理"
    static let pinnedEmptyTitle = "GitHub 个人主页还没有置顶仓库"
    static let pinnedEmptyHint = "去个人主页「Customize your pins」挑几个，回到首页下拉即可看到"

    static let recentSection = "最近访问"
    static let recentClear = "清除"
    static let recentEmptyTitle = "暂无访问记录"
    static let recentEmptyHint = "打开任意仓库后会自动出现在这里"

    /// 清除二次确认（PRD §5.1）。
    static let clearConfirmTitle = "清除最近访问记录？"
    static let clearConfirmHint = "只清空本机的浏览历史，不影响仓库本身，也不会影响首页的置顶仓库。"
    static let clearConfirmAction = "清除全部记录"
    static let clearConfirmCancel = "取消"

    /// 清除后的提示（PRD §7）。
    static let recentCleared = "已清除最近访问记录"

    /// ⚠️ 它**不是** PRD §7 里的句子 —— 那一节没有这条。
    /// 原因：PRD 假定刷新失败时整屏会变成失败态；而**已有内容时**不能那样做（§8.5），
    /// 于是"失败"必须另找一处说出口。宁可多一句，也不要把一次失败的刷新显示成"已是最新"。
    static let refreshFailed = "刷新失败 · 下拉可重试"

    /// 「管理」跳网页端时的提示（PRD §7 原文）。
    static let managePinsToast = "置顶仓库在 GitHub 个人主页管理 · 已为你打开"
}
