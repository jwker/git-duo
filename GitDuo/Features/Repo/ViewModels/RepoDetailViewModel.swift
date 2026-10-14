import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit
import UIKit

/// 仓库**首页**（**自己的仓库**，PRD §4.4）的状态。
///
/// ## ⚠️ 2026-10-14：它从"四分区一页里全做"瘦成**只做首页**（走查第 63 条）
///
/// 用户要求把这一页改成枢纽（头部大卡 + 四行入口），代码浏览搬进独立页面。
/// 于是原来住在这里的东西各自**搬走**，一处都没删：
///
/// | 原来在这里 | 现在在哪 |
/// |---|---|
/// | 目录（`tree`）| **代码页** `RepoCodeView`（它自己按层持有多份会话）|
/// | 目录里**顺带取的那份 README** | ⚠️ 同日晚些**回到本页**（`readme`）—— 见下面那一段 |
/// | 提交列表（`commits`）| **分区页** `RepoSectionViewModel`（`section == .commits`）|
/// | Issues / PR 两档（四个状态机）| **分区页** `RepoSectionViewModel` |
/// | Star / 头部 / 最近访问 | **还在本类型**（首页自己的数据）|
///
/// ⇒ 本类型现在只有**一条**"决定整页"的取数（头部，连带 Star 基准），失败即整页失败。
/// 原来那张"六条数据各有各的节奏"的表格随这次拆分删掉了 —— 那种表格在一个
/// 只取一份数据的类型上只会误导人（`RepoSectionViewModel` 里另有一张，那是它的实情）。
///
/// ## ⚠️ 2026-10-14 同日晚些：README 又加了一条取数（用户要求它进首页）
///
/// 表 = **"整页取数"**（头部）与 **"块级取数"**（README）两类，
/// 而不是"七条各自为政"。README 与头部的关系是**依赖**而非并列：
/// 它要头部那份 `defaultBranch` 才知道用哪条分支去读（`LoadRepoReadme` 的类型说明）。
///
/// | | 数据 | 何时取 | 失败时 |
/// |---|---|---|---|
/// | 头部（+ Star 基准）| `GET /repos/{o}/{r}` | 进页 | **整页失败**（连四行入口都不画）|
/// | README | `GET /repos/{o}/{r}/readme` | **头部到手之后** | **块级失败**：那一块给「重试」，头部与四行入口照常 |
///
/// ⚠️ 上面的分档与 `RepoTreeSection` 里那处"这一块加载失败"同一条口径
/// （§8.5：内容区里的一小块失败，不掀翻整页）—— 一处 README 取不到，
/// 不该让用户连"去代码页 / Issues"那四行都点不了。
///
/// ## ⚠️ 它**不再**拿 `defaultBranch` 去做任何事
///
/// 以前"头部到手 ⇒ 交给 `tree.load(defaultBranch:)`"是这一页的第二跳。
/// 现在需要默认分支的是代码页与提交列表，它们**各自去问一次头部**
/// （`LoadRepoDetail.repository(fullName:)`，与首页走同一条路由 ⇒ 命中 304、不计配额
/// —— 见那个方法的说明）。本类型因此不必把自己那份传出去。
@MainActor
@Observable
final class RepoDetailViewModel {

    // MARK: - 状态

    private(set) var snapshot: LoadState<RepoDetailSnapshot> = .idle

    /// 仓库 README —— 画在四行入口**之下**（用户裁定，2026-10-14）。
    ///
    /// ⚠️ `LoadState<MarkdownDocument?>`：里面那个 `nil` 是**"这个仓库没有 README"**
    /// （`.loaded(nil)`），与"还没取到"（`.skeleton`）是两件事 ——
    /// 前者在页面上**什么都不画**，后者画一小块骨架。
    ///
    /// ⚠️ 它**独立于 `snapshot`**：一条失败不牵连另一条（见类型说明那张表）。
    private(set) var readme: LoadState<MarkdownDocument?> = .idle

    private(set) var isTogglingStar = false

    /// **这个仓库的 Star 点得动吗**（TECH_SPEC §3.5.5、决策 #80）。
    ///
    /// ⚠️ 初值 `true` 是**有意**的，不是偷懒：`StarWriteScope` 的规则是
    /// "**还没查到就不拦**"（不确定时误灰一个能点的按钮，比漏灰一个不能点的糟得多）。
    /// 所以"范围还没回来"这段时间里界面该表现成"可点"，而这个初值就是那件事。
    ///
    /// ⚠️ 本页**大概率永远看不到 `false`** —— §4.4 的入口判据是"自己有写权限"，
    /// 而自己的仓库必然在安装范围内。**唯一的例外是组织仓库**：你对它有 push、
    /// 但那个组织没装 GitDuo ⇒ 那时它会变成灰的，而那正是这一档存在的理由。
    private(set) var starWritable = true

    // MARK: - 依赖

    private let detailLoader: LoadRepoDetail
    private let readmeLoader: LoadRepoReadme
    private let starToggle: ToggleStar
    private let starScope: StarWriteScopeCache
    private let visits: any RecentVisitStore
    private let toast: ToastCenter

    let fullName: String

    init(
        fullName: String,
        detail: LoadRepoDetail,
        readme: LoadRepoReadme,
        starToggle: ToggleStar,
        starScope: StarWriteScopeCache,
        visits: any RecentVisitStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.detailLoader = detail
        self.readmeLoader = readme
        self.starToggle = starToggle
        self.starScope = starScope
        self.visits = visits
        self.toast = toast
    }

    // MARK: - 生命周期

    /// 进页：**先记访问，再取数**（理由同 `ExploreRepoViewModel.start`）。
    ///
    /// ⚠️ `canWrite: true` 是事实而不是猜测：能走到本页，只可能是因为路由在进入前
    /// 就把它判成了自己的仓库（`HomeView` / `ReposView` 二选一推入）
    /// —— 这正是 `RecentVisitStore.record(fullName:canWrite:at:)` 要调用方显式传参的原因。
    func start() async {
        await visits.record(fullName: fullName, canWrite: true, at: Date())

        // ⚠️ 排在取详情**之前**：它决定头部那颗星标灰不灰，而它在稳态下是一次
        //    **缓存命中**（组合根在冷启动就预热了它，§3.5.5）⇒ 代价可以忽略；
        //    不这么排的话，头部会先按"可点"画出来、再当场变灰。
        await resolveStarWritable()

        guard !snapshot.hasFinished else { return }
        await loadDetail()
    }

    /// 下拉刷新：重拉头部（连带 Star 基准与 README）。
    ///
    /// ⚠️ README 不单独刷新 —— 它挂在 `loadDetail` 成功那一支上（它要头部里的
    /// `defaultBranch`）。所以"下拉刷一次"= 头部 + README 各一次请求。
    ///
    /// ⚠️ 原来这一句后面还跟着"不刷新已加载的提交列表"那三段说明 —— 那件事
    /// 随提交列表一起搬去了 `RepoSectionViewModel`（它有自己的下拉刷新）。
    func refresh() async {
        // 顺带重问一次可写范围：稳态下是缓存命中（白做不了什么），
        // 而**第一次没问到**时（断网进的页）这里是唯一的重试出口
        // —— `StarWriteScopeCache` 有意不缓存失败。
        await resolveStarWritable()
        await loadDetail(keepContent: true)
    }

    // MARK: - Star

    func toggleStar() async {
        guard let current = snapshot.value?.star, !isTogglingStar else { return }

        isTogglingStar = true
        defer { isTogglingStar = false }

        do {
            let (next, action) = try await starToggle.toggle(current)
            // ⚠️ 只换 `star`，头部那份详情**原样保留** —— 它是上一句 `guard` 已经
            //    确认过存在的那一份。重新取一次头部是白花一个请求。
            if let currentDetail = snapshot.value?.detail {
                snapshot.succeed(RepoDetailSnapshot(detail: currentDetail, star: next))
            }
            toast.show(StarCopy.toast(for: action))
        } catch {
            // 失败**不改动任何计数**（`ToggleStar.toggle` 保证），按钮恢复可点。
            // ⚠️ 提示按**成因**分流（决策 #80）：越出安装范围那一种要说那一句，
            //    因为通用句 `操作失败 · 请重试` 会把用户送向一条**永远不会成功**的重试。
            toast.show(StarCopy.failureMessage(for: error))
        }
    }

    /// 问一次「这个仓库写不写得动」。
    ///
    /// ⚠️ 它**不抛错也不表态**：查不到就是查不到，界面按"可点"处理
    /// （`StarWriteScope.unknown` 那一档）—— 不拦，让写请求自己去失败，
    /// 那时再给一句准确的话。这是"失败不要静默吞掉"的正确落法：
    /// **不是**把错误藏起来，而是把它推迟到"真正需要它的那一步"。
    private func resolveStarWritable() async {
        starWritable = await starScope.current().canWrite(fullName: fullName)
    }

    // MARK: - 内部：取数

    private func loadDetail(keepContent: Bool = false) async {
        if !keepContent { snapshot.begin() }
        do {
            let value = try await detailLoader.load(fullName: fullName)
            snapshot.succeed(value)
            // ⚠️ README **排在这里**，不在 `start()` 里另起一条并发：它要头部里的
            //    `defaultBranch` 才知道用哪条分支读 —— 而这里正是"头部到手"那一刻。
            //    代价是它比头部晚一拍开始（页面上先出头部、后出 README）——
            //    那是对的：没有分支就无从发起这一问。
            await loadReadme(ref: value.detail.defaultBranch)
        } catch {
            if keepContent, snapshot.value != nil {
                // ⚠️ 正本在 `GitDuoKit.RefreshCopy`（切片 7.4 收口）。
                toast.show(RefreshCopy.failed)
            } else {
                snapshot.fail(Self.failure(from: error))
            }
        }
    }

    // MARK: - 内部：README（**块级**取数）

    /// 取 README。失败**只让那一块失败** —— 头部与四行入口照常（见类型说明）。
    ///
    /// ⚠️ 这里**不给 toast**：块级失败自有一块可见的失败态（那颗「重试」），
    ///    再弹一句提示等于同一件事说两遍（同 `RepoTreeSection.failure` 的处置）。
    private func loadReadme(ref: String) async {
        // ⚠️ 下拉刷新时这一块也会切骨架（不像头部那样保留旧内容）——
        //    与 `RepoTreeSession.load` 的处置一致（它也是 `page.begin()`）。
        readme.begin()
        do {
            readme.succeed(try await readmeLoader.load(fullName: fullName, ref: ref))
        } catch {
            readme.fail(Self.failure(from: error))
        }
    }

    /// README 那一块自己的重试出口（`LoadState` 里没有"重试"这个概念，它是视图的事）。
    ///
    /// ⚠️ 用**手上那份头部**的分支，**不重取头部**：失败的是这一块、头部没失败，
    ///    重取头部会把整页切回骨架（§8.5：刷新不遮挡已有内容）。
    func retryReadme() async {
        guard let branch = snapshot.value?.detail.defaultBranch else { return }
        await loadReadme(ref: branch)
    }

    // MARK: - 错误归一化

    /// 把任意错误收敛成 `GitHubError`（同其余 ViewModel：映射失败归 `.decoding`，
    /// **不是** `.transport` —— 后者会让界面给出"检查网络"的错误引导）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }

    /// PRD §7 没有给"Star 操作失败"那一句（同 `ExploreRepoViewModel`）。
    /// 那一句现在在 `GitDuoKit.ActionCopy.failed`（切片 7.4 收口 —— 本文件原有一份
    /// 同值副本 `actionFailedToast`，标签弹层的新建失败当时也借用了它）。
    /// 决策缺口本身**没有关闭**：仍登记在 `REVIEW-CHECKLIST §5`。
}
