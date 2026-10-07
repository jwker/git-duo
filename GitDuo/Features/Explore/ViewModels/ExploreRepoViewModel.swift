import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 他人仓库详情的状态（PRD §4.13、TECH_SPEC §9.11）。
///
/// ## 它管两件不同节奏的事
///
/// | | 数据 | 何时取 |
/// |---|---|---|
/// | 页面四路数据 | `GET /repos` + `languages` + `releases/latest` + `contributors` | 进页一次（并发四路） |
/// | Star 基准 | `GET /user/starred/{o}/{r}` | 详情回来之后 —— 它需要详情里的星数 |
///
/// ## ⚠️ 一路失败 ⇒ 整页失败（有意如此）
///
/// 看起来"分别降级"更友好，但 §8.5 把加载 / 失败态**三档统一**了、
/// 并明写"各页面不得自行发挥"。分区块各自失败要再定义一套"块级失败态"，
/// 那是新的产品口径，不该由实现顺手定。`LoadRepoInsights` 里有完整理由。
@MainActor
@Observable
final class ExploreRepoViewModel {

    private(set) var insights: LoadState<RepoInsights> = .idle

    /// Star 的当前状态。`nil` = 基准还没确认（详情没好，或那次查询失败了）。
    ///
    /// ⚠️ 基准失败**不抛错、不让整页失败**（`ToggleStar.initialState` 的降级）：
    /// 页面的头部、语言构成、贡献者与它无关。用户点下去时会先补一次基准查询。
    private(set) var star: StarState?

    /// Star 请求在途 ⇒ 按钮内联 loading + 禁用（§8.5「操作类」）。
    private(set) var isTogglingStar = false

    /// 相对时间现算用的"现在"。由视图在渲染那刻传进来（见 `open` 处的说明）。
    var now: Date { .now }

    private let loader: LoadRepoInsights
    private let starToggle: ToggleStar
    private let visits: any RecentVisitStore
    private let toast: ToastCenter

    private var fullName = ""

    init(
        loader: LoadRepoInsights,
        starToggle: ToggleStar,
        visits: any RecentVisitStore,
        toast: ToastCenter
    ) {
        self.loader = loader
        self.starToggle = starToggle
        self.visits = visits
        self.toast = toast
    }

    // MARK: - 生命周期

    /// 进页：**先记访问，再取数**。
    ///
    /// 顺序不能反：万一取数失败，这次访问也确实发生了 —— 而"最近访问"记的是
    /// "用户打开过它"，不是"它成功显示了"。
    func start(fullName: String) async {
        self.fullName = fullName

        // ⚠️ `canWrite: false` **是事实、不是猜测**：能走到本页，只可能是因为路由
        //    在进入前就把它判成了他人仓库（`HomeView` / `ReposView` / `ExploreView` 三处入口）。
        //    这正是 `RecentVisitStore.record(fullName:canWrite:at:)` 要调用方显式传参的原因 ——
        //    零额外请求、零猜测（TECH_SPEC §7.2）。
        await visits.record(fullName: fullName, canWrite: false, at: Date())

        guard !insights.hasFinished else { return }
        await load()
    }

    func refresh() async {
        await load()
    }

    // MARK: - Star

    func toggleStar() async {
        guard let current = star, !isTogglingStar else { return }

        isTogglingStar = true
        defer { isTogglingStar = false }

        do {
            let (next, action) = try await starToggle.toggle(current)
            star = next
            toast.show(StarCopy.toast(for: action))
        } catch {
            // ⚠️ 失败**不改动任何计数**（`ToggleStar.toggle` 保证这一点），
            //    按钮恢复可点（`defer` 收起 loading），并给一条提示。
            toast.show(Self.starFailedToast)
        }
    }

    // MARK: - 内部

    private func load() async {
        // 已有内容时**不切到 loading**（§8.5：下拉刷新不遮挡已有内容）。
        let hadContent = insights.value != nil
        if !hadContent { insights.begin() }

        do {
            let value = try await loader.load(fullName: fullName, now: Date())
            insights.succeed(value)
            // 详情到手才知道星数 ⇒ Star 基准必须在这之后问。
            star = await starToggle.initialState(fullName: fullName, starCount: value.detail.starCount)
        } catch {
            if hadContent {
                toast.show(ExploreRepoCopy.refreshFailed)
            } else {
                insights.fail(Self.failure(from: error))
            }
        }
    }

    /// 把任意错误收敛成 `GitHubError`（同其余 ViewModel 的口径：
    /// 映射失败归 `.decoding`，**不是** `.transport`）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }

    /// ⚠️ **决策缺口**：PRD §7 的「提示 / 校验」一节给了 Star 成功与取消的两句，
    /// **没有给失败那一句**。这里先按"陈述事实 + 可重试"措辞。
    /// 已登记到 `REVIEW-CHECKLIST.md §5`，等拍板后与 PRD 一起改。
    static let starFailedToast = "操作失败 · 请重试"
}

/// 探索仓库详情的可见文案（PRD §4.13 / §7）。
enum ExploreRepoCopy {

    /// 三个「数据拿到了但是空的」状态 —— 文案收在**领域层**
    /// （`RepoInsightNotice`，与 `ExploreBoardNotice` 同一做法），这里只做转发，
    /// 避免视图里出现字面量。
    static var noLanguages: String { RepoInsightNotice.noLanguages }
    static var noRelease: String { RepoInsightNotice.noRelease }
    static var noContributors: String { RepoInsightNotice.noContributors }

    static let myFoldersSection = "我的收藏（私人整理 · 仅自己可见）"
    static let languageSection = "语言构成"
    static let releaseSection = "Latest Release"
    static let fileSection = "文件浏览"
    static let readmeSection = "README.md"
    static let collaborationSection = "参与协作"
    static let releaseAssetsHint = "资产与源码下载依赖仓库的 Release 页面"

    static let issuesRowTitle = "Issues"
    static let issuesRowSubtitle = "浏览与参与讨论 · 无关闭权限"
    static let pullsRowTitle = "Pull Requests"
    static let pullsRowSubtitle = "查看他人贡献 · 可评论不可合并"

    static let skeletonNote = "加载中…"
    static let failureTitle = "加载失败 · 点击重试"
    static let retry = "重试"

    /// 同 `HomeCopy.refreshFailed`：PRD §7 没有这条，因为 PRD 假定刷新失败时整屏变失败态。
    /// 而**已有内容时**不能那样做（§8.5），失败必须另找一处说出口。
    static let refreshFailed = "刷新失败 · 下拉可重试"

    static let sourceCodeButton = LatestRelease.sourceCodeButtonTitle
}
