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
/// ## ⚠️ 2026-10-14：目录 + README 那一半**搬走了**（走查第 63 条）
///
/// 第 ⑤ / ⑥ 两分区原先在本页**内嵌**着一整块目录浏览（`RepoTreeSession`
/// + `RepoTreeSection`，与 §4.4 的「代码」分区共用），于是子目录要"推入一层新页面"。
/// 现在它改成**一条入口行**，点进去是 `RepoCodeView`（那一页自己承载目录层级）
/// ⇒ 本类型不再需要目录会话、分支列表，也不再需要 `path`。
///
/// ⚠️ 连带消失的还有"这一页能切分支"这件事（原型那一处——`exploreTree`——已随同步删除）：
/// 分支切换跟着目录一起去了代码页，那里是唯一有面包屑的地方。
///
/// ## ⚠️ 一路失败 ⇒ 整页失败（有意如此）
///
/// 看起来"分别降级"更友好，但 §8.5 把加载 / 失败态**三档统一**了、
/// 并明写"各页面不得自行发挥"。分区块各自失败要再定义一套"块级失败态"，
/// 那是新的产品口径，不该由实现顺手定。`LoadRepoInsights` 里有完整理由。
///
/// ## ⚠️ 2026-10-14 晚些：README 是**块级**取数，不走上面那条
///
/// | | 数据 | 何时取 | 失败时 |
/// |---|---|---|---|
/// | 页面四路（`insights`）| 头部 + 语言 + Release + 贡献者 | 进页（并发四路）| **整页失败** |
/// | Star 基准 | `GET /user/starred` | 详情回来之后 | 静默降级（`star` 留 `nil`）|
/// | README | `GET /repos/{o}/{r}/readme` | **详情回来之后** | **块级失败**：那一块给「重试」 |
///
/// ⚠️ 上面那条"整页失败"说的是 `insights` 自己那四路 —— 它们是**一屏**（少一路那一屏
/// 就不成立）。README 不是：它是"再往下看"的一段内容，取不到不该让用户连头部、
/// 语言构成、文件浏览入口都看不成。而"块级失败态"也**不是新产品口径** ——
/// `SectionFailure` 早就存在（§4.4 分段时代四个分区共用它），这里只是又一个调用方。
@MainActor
@Observable
final class ExploreRepoViewModel {

    private(set) var insights: LoadState<RepoInsights> = .idle

    /// 仓库 README（§4.13 的 ⑥ 分区）。
    ///
    /// ⚠️ 2026-10-14 起它**住在本页**：此前它跟着目录一起在代码页里（README 与"根目录"
    /// 那个位置绑在一起），现在由 `LoadRepoReadme` 单独取 —— 本页已经有头部在手
    /// （`RepoInsights.detail.defaultBranch`），不需要分支列表、不需要分支记忆。
    ///
    /// ⚠️ `nil`（内层）= 这个仓库没有 README（**正常结果**，不是错误）；
    ///    `nil`（外层）= 还没取到。两者在 `RepoReadmeSection` 里各有各的画法。
    private(set) var readme: LoadState<MarkdownDocument?> = .idle

    /// Star 的当前状态。`nil` = 基准还没确认（详情没好，或那次查询失败了）。
    ///
    /// ⚠️ 基准失败**不抛错、不让整页失败**（`ToggleStar.initialState` 的降级）：
    /// 页面的头部、语言构成、贡献者与它无关。用户点下去时会先补一次基准查询。
    private(set) var star: StarState?

    /// Star 请求在途 ⇒ 按钮内联 loading + 禁用（§8.5「操作类」）。
    private(set) var isTogglingStar = false

    /// **这个仓库的 Star 点得动吗**（TECH_SPEC §3.5.5、决策 #80）。
    ///
    /// ⚠️ **本页是这条限制影响最大的屏** —— 它出现的每一条数据（趋势榜 / 搜索）
    /// 都是**别人的仓库**，而别人的仓库**写不了**。所以这里大量条目会是灰的，
    /// 那不是坏了，是如实。
    ///
    /// ⚠️ 初值 `true` 与 `RepoDetailViewModel` 同一个理由：`StarWriteScope` 的规则是
    /// "**还没查到就不拦**"。差别在于本页**真的会用到 `false`**（那一页基本用不到）。
    private(set) var starWritable = true

    /// 相对时间现算用的"现在"。由视图在渲染那刻传进来（见 `open` 处的说明）。
    var now: Date { .now }

    private let loader: LoadRepoInsights
    private let readmeLoader: LoadRepoReadme
    private let starToggle: ToggleStar
    private let starScope: StarWriteScopeCache
    private let visits: any RecentVisitStore
    private let toast: ToastCenter

    let fullName: String

    init(
        fullName: String,
        loader: LoadRepoInsights,
        readme: LoadRepoReadme,
        starToggle: ToggleStar,
        starScope: StarWriteScopeCache,
        visits: any RecentVisitStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.loader = loader
        self.readmeLoader = readme
        self.starToggle = starToggle
        self.starScope = starScope
        self.visits = visits
        self.toast = toast
    }

    // MARK: - 生命周期

    /// 进页：**先记访问，再取数**。
    ///
    /// 顺序不能反：万一取数失败，这次访问也确实发生了 —— 而"最近访问"记的是
    /// "用户打开过它"，不是"它成功显示了"。
    func start() async {
        // ⚠️ `canWrite: false` **是事实、不是猜测**：能走到本页，只可能是因为路由
        //    在进入前就把它判成了他人仓库（`HomeView` / `ReposView` / `ExploreView` 三处入口）。
        //    这正是 `RecentVisitStore.record(fullName:canWrite:ownerAvatarURL:at:)` 要调用方
        //    显式传参的原因 —— 零额外请求、零猜测（TECH_SPEC §7.2）。
        //    ⚠️ 头像地址此刻还不知道 ⇒ 传 `nil`，`load()` 成功后**补记**。
        await visits.record(fullName: fullName, canWrite: false, ownerAvatarURL: nil, at: Date())

        // ⚠️ 「Star 写不写得动」排在这里（稳态下是缓存命中，组合根冷启动就预热过）。
        //    本页这一问**基本上每次都是有意义的** —— 它进来的多半是别人的仓库。
        await resolveStarWritable()

        guard !insights.hasFinished else { return }
        await load()
    }

    func refresh() async {
        // 可写范围重问一次：稳态下白做不了什么，但**第一次没问到**时（断网进的页）
        // 这里是唯一的重试出口 —— `StarWriteScopeCache` 有意不缓存失败。
        await resolveStarWritable()
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
            //    ⚠️ 提示按**成因**分流（决策 #80）：本页的失败**绝大多数就是**
            //       "越出安装范围" —— 这一页里基本全是别人的仓库。
            //       而通用句 `操作失败 · 请重试` 会把用户送向一条永远不会成功的重试。
            toast.show(StarCopy.failureMessage(for: error))
        }
    }

    /// 问一次「这个仓库写不写得动」（口径同 `RepoDetailViewModel.resolveStarWritable`）。
    private func resolveStarWritable() async {
        starWritable = await starScope.current().canWrite(fullName: fullName)
    }

    // MARK: - 内部

    private func load() async {
        // 已有内容时**不切到 loading**（§8.5：下拉刷新不遮挡已有内容）。
        let hadContent = insights.value != nil
        if !hadContent { insights.begin() }

        do {
            let value = try await loader.load(fullName: fullName, now: Date())
            insights.succeed(value)
            // 头像补记（走查第 72 条）：进页那一次 `record` 传的是 `nil`（那时还没取数），
            // 现在地址到手了。仍走同一条 `record` —— 去重逻辑保证"最近访问"里这条还是一条。
            await visits.record(
                fullName: fullName,
                canWrite: false,
                ownerAvatarURL: value.detail.ownerAvatarURL,
                at: Date()
            )
            // 详情到手才知道星数 ⇒ Star 基准必须在这之后问。
            star = await starToggle.initialState(fullName: fullName, starCount: value.detail.starCount)
            // ⚠️ README 也在这之后（它要 `defaultBranch` 才知道用哪条分支读）——
            //    与 `RepoDetailViewModel` 是同一个顺序、同一个理由。
            await loadReadme(ref: value.detail.defaultBranch)
        } catch {
            if hadContent {
                // ⚠️ 正本在 `GitDuoKit.RefreshCopy`（切片 7.4 收口）。
                toast.show(RefreshCopy.failed)
            } else {
                insights.fail(Self.failure(from: error))
            }
        }
    }

    /// 取 README —— **块级**取数（失败只让那一块给出口，见类型说明那张表）。
    ///
    /// ⚠️ 这里**不给 toast**：块级失败自有一块可见的失败态（那颗「重试」），
    ///    再弹一句提示等于同一件事说两遍（同 `RepoTreeSection` 的处置）。
    private func loadReadme(ref: String) async {
        readme.begin()
        do {
            readme.succeed(try await readmeLoader.load(fullName: fullName, ref: ref))
        } catch {
            readme.fail(Self.failure(from: error))
        }
    }

    /// README 那一块自己的重试出口（`LoadState` 里没有"重试"这个概念，它是视图的事）。
    ///
    /// ⚠️ 用**手上那份详情**的分支，**不重取整页**：失败的是这一块、`insights` 没失败，
    ///    重取整页会把头部与其余分区一起切回骨架（§8.5：刷新不遮挡已有内容）。
    func retryReadme() async {
        guard let branch = insights.value?.detail.defaultBranch else { return }
        await loadReadme(ref: branch)
    }

    /// 把任意错误收敛成 `GitHubError`（同其余 ViewModel 的口径：
    /// 映射失败归 `.decoding`，**不是** `.transport`）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }

    /// ⚠️ **决策缺口**：PRD §7 的「提示 / 校验」一节给了 Star 成功与取消的两句，
    /// **没有给失败那一句**。那一句 (「操作失败 · 请重试」) 仍然按"陈述事实 + 可重试"措辞，
    /// 但它**从这里搬走了** —— 切片 7.4 收口到 `GitDuoKit.ActionCopy.failed`
    /// （正本；本文件原有一份同值副本 `starFailedToast`）。
    /// 已登记到 `REVIEW-CHECKLIST.md §5`，等拍板后与 PRD 一起改（改一处即可）。
}

/// 探索仓库详情的可见文案（PRD §4.13 / §7）。
enum ExploreRepoCopy {

    /// 三个「数据拿到了但是空的」状态 —— 文案收在**领域层**
    /// （`RepoInsightNotice`，与 `ExploreBoardNotice` 同一做法），这里只做转发，
    /// 避免视图里出现字面量。
    static var noLanguages: String { RepoInsightNotice.noLanguages }
    static var noRelease: String { RepoInsightNotice.noRelease }
    static var noContributors: String { RepoInsightNotice.noContributors }

    static let languageSection = "语言构成"
    static let releaseSection = "Latest Release"

    /// 第 ⑤ 分区的小节标题（原型逐字）。
    ///
    /// ⚠️ **2026-10-14 去掉了 ` · {path}` 那一半**：这一分区原先内嵌着目录树，
    /// 子目录里要带出"现在是哪一层"；现在它是一条**入口行**，点进去才是目录页
    /// ⇒ 这一页没有"当前层"可言，那个函数（`fileSection(path:)`）随之删除。
    static let fileSection = "文件浏览"

    /// 那条入口行的标题。
    ///
    /// ⚠️ **2026-10-14 晚些去掉了 `与 README`**：README 现在**就在本页**（在这条入口
    /// 行下面），不再跟着它进代码页 —— 留着那三个字，等于标题承诺一个点进去
    /// 根本看不到的东西。原值 `浏览目录与 README`。
    /// （同 `RepoCopy.breadcrumbMenuAccessibilityLabel` → `operationsMenuAccessibilityLabel`
    ///  那次一样：名字不该继续描述一个已经不成立的处境。）
    static let fileBrowseRowTitle = "浏览目录"

    // ⚠️ 第 ⑥ 分区的小节标题（`README.md`）**不在这里** —— 它原先在这里有一个
    //    `readmeSection`，值与 `RepoCopy.readmeSectionTitle` **完全相同**。
    //    两处各存一份时，"把标题改成 `README`"只会改到其中一页。
    //    现在两页共用 `RepoCopy.readmeSectionTitle`（由 `RepoReadmeSection` 渲染
    //    —— 2026-10-14 起那一块画在本页与 §4.4 首页上，不在代码页了）。

    static let collaborationSection = "参与协作"
    static let releaseAssetsHint = "资产与源码下载依赖仓库的 Release 页面"

    static let issuesRowTitle = "Issues"
    static let issuesRowSubtitle = "浏览与参与讨论 · 无关闭权限"
    static let pullsRowTitle = "Pull Requests"
    static let pullsRowSubtitle = "查看他人贡献 · 可评论不可合并"

    static let skeletonNote = "加载中…"
    static let failureTitle = "加载失败 · 点击重试"
    static let retry = "重试"

    /// ⚠️ 「刷新失败」那一句**不在这里** —— 切片 7.4 收口到
    /// `GitDuoKit.RefreshCopy.failed`（正本，PRD §7 没有这条，是 §8.5 推出来的）。

    static let sourceCodeButton = LatestRelease.sourceCodeButtonTitle
}
