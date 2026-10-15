import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 首页 —— Tab 根页（PRD §4.1、TECH_SPEC §9.1）。
///
/// 结构：大标题「首页」+ 右上角搜索 · 「置顶仓库」**行列表**（最多 6 条，
/// ⚠️ 2026-10-15 走查第 75 条起不再是 2 列网格）·「最近访问」列表。
///
/// ## ⚠️ 这一屏唯一容易写错的，是"点什么进哪里"
///
/// 置顶卡与最近访问行都可能是**他人仓库**（原型 `PINNED` 里就混着 `rust-lang/rust`），
/// 而只读态必须在**进入之前**定下（铁律 #7）。所以分流依据**不能现猜**：
///
/// | 入口 | 依据 | 来自 |
/// |---|---|---|
/// | 置顶卡 | `summary.canOpenWritableDetail` | GraphQL `viewerPermission`（随置顶一起取回） |
/// | 最近访问行 | `visit.canWrite` | 写入这条记录时记下的（`RecentVisitStore`） |
///
/// ⚠️ **绝不用"全名是不是以我的登录名开头"来判定**（PRD §3.13）：它在 Fork / 组织仓库 /
/// 协作者仓库上都会判错，而判错的表现是"点进自己的仓库却没有编辑入口"，
/// 或者反过来"给他人仓库长出编辑入口、改完才吃 403"。
/// 原型的 `openRepo()` 里那句 `n.indexOf('my-git/')===0` 是**无后端时的演示简化**，不得照搬。
struct HomeView: View {

    let login: String

    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL

    @State private var model: HomeViewModel
    @State private var isConfirmingClear = false

    /// 依赖由**组合根**经父视图传下来（`MainTabView` 读 `env.*`），
    /// 本视图与 ViewModel 都不自行构造客户端（AGENTS.md §3）。
    init(
        login: String,
        pinned: LoadPinnedRepositories,
        visits: any RecentVisitStore,
        toast: ToastCenter
    ) {
        self.login = login
        // `State(initialValue:)` 只在首次构造时生效 —— 视图重建不会把状态冲掉。
        _model = State(initialValue: HomeViewModel(
            pinnedLoader: pinned,
            visitStore: visits,
            toast: toast
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pinnedSection
                recentSection
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        .navigationTitle(HomeCopy.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    env.router.push(.search)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("搜索")
            }
        }
        .refreshable { await model.refresh() }
        .task {
            await model.loadPinnedIfNeeded()
            await model.reloadVisits()
        }
        // ⚠️ 这段不是多余的：`RecentVisitStore` **刻意不含观察入口**（否则"进入详情页写入 →
        //    首页重绘 → 再写入"会成环），所以首页只能主动读。而"从详情页返回"时
        //    SwiftUI 不保证根视图的 `.task` 会重跑（根视图并没有离开视图树），
        //    于是这里盯住**本 Tab 导航栈回到根**这件事 —— 它是确定的。
        .onChange(of: env.router.home.count) { _, depth in
            guard depth == 0 else { return }
            Task { await model.reloadVisits() }
        }
        // ⚠️ 这里**是弹层，不是 `.confirmationDialog`**（2026-10-07 目视修正）：
        //    动作表在本项目唯一的平台上贴着屏幕底、标题压成一行小字，
        //    而 PRD §5.1 与原型 `openClearRecent()` 给的都是"标题 + 说明 + 两个整宽按钮"
        //    那张卡片 —— 与 `DeleteBranchSheet` 同一套版式。详见 `ClearRecentSheet`。
        //
        //    仍然是**一个布尔量**就够：本页只有这一张弹层（`RepoDetailView` 那边用枚举
        //    是因为它有第二张，"哪一张盖在上面"会变成呈现顺序问题）。
        .sheet(isPresented: $isConfirmingClear) {
            ClearRecentSheet {
                await model.clearVisits()
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 置顶仓库

    @ViewBuilder
    private var pinnedSection: some View {
        SectionHeader(
            title: HomeCopy.pinnedSection,
            actionTitle: HomeCopy.pinnedManage,
            action: managePins
        )

        switch model.pinned.presentation {
        case .skeleton:
            PinRowsSkeleton()

        case .content:
            pinnedGrid

        case let .failure(error):
            failureBox(error)
        }
    }

    /// 内容态。**空数组是正常结果**（还没置顶任何仓库），不是错误（TECH_SPEC §9.1）。
    @ViewBuilder
    private var pinnedGrid: some View {
        let items = model.pinned.value ?? []
        if items.isEmpty {
            EmptyBox(title: HomeCopy.pinnedEmptyTitle, hint: HomeCopy.pinnedEmptyHint)
        } else {
            // ⚠️ 2026-10-15 走查第 75 条：置顶从 **2 列灰块网格**改成**单列平铺行**
            //    （页面转白后它是唯一一组还带灰底的块，且与同页的最近访问不像一家人）
            //    ⇒ 行间 hairline 由行自己画在顶上，首行不画（同 `StarRow` / `RecentRow`）。
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, summary in
                    Button {
                        openPinned(summary)
                    } label: {
                        PinRow(summary: summary, showsSeparator: index > 0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 最近访问

    @ViewBuilder
    private var recentSection: some View {
        // 「清除」只在**有记录时**出现（PRD §4.1 结构第 3 条）。
        // 没有记录还摆一个"清除"是个必然失败的动作 —— 而且它会让人以为"本来有东西"。
        let visits = model.visits
        let hasVisits = !visits.isEmpty
        SectionHeader(
            title: HomeCopy.recentSection,
            actionTitle: hasVisits ? HomeCopy.recentClear : nil,
            action: hasVisits ? { isConfirmingClear = true } : nil
        )

        if hasVisits {
            // ⚠️ 不做本地去重 / 裁剪：上限 6 与"同一仓库只留一条"都在存储那一侧保证
            //    （`RecentVisitStore`），这里重做一遍就等于有了两份规则。
            VStack(spacing: 0) {
                ForEach(visits.indices, id: \.self) { index in
                    let visit = visits[index]
                    Button {
                        openVisit(visit)
                    } label: {
                        RecentRow(
                            fullName: visit.fullName,
                            // ⚠️ 描述与私有性**本机确实没有** —— `RecentVisit` 只存
                            //    全名 / 时刻 / 当时是否可写（PRD §3.13）。传 `nil`
                            //    是"陈述事实"，不是"忘了填"：`RecentRow` 的说明里写了
                            //    这两格表达的就是"调用方手上有没有"。
                            description: nil,
                            isPrivate: nil,
                            timeLabel: visit.timeLabel(now: .now),
                            // 记录访问时落盘的 owner 头像地址（走查第 72 条）；
                            // 旧记录没有这个字段 ⇒ `nil` ⇒ 行内首字母兜底圆。
                            ownerAvatarURL: visit.ownerAvatarURL,
                            // 方案 D：分隔线是顶上那条内嵌 hairline —— 首行不画。
                            showsSeparator: index > 0
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            EmptyBox(title: HomeCopy.recentEmptyTitle, hint: HomeCopy.recentEmptyHint)
        }
    }

    // MARK: - 失败态

    /// 首屏失败 —— 必须留一个出口（PRD §1 设计原则 4：任何失败都有出口）。
    private func failureBox(_ error: GitHubError) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("加载失败 · 点击重试")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            Button("重试") {
                Task { await model.refresh() }
            }
            .font(Theme.Font.bodyStrong)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .strokeBorder(Theme.Palette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
        // 失败原因**只说确定的那一件事**：404 与无权限被 GitHub 混同，
        // 不得替用户断定是"没有"还是"没权限"（与 `ReposView.failureHint` 同一口径）。
        .accessibilityElement(children: .combine)
        .accessibilityHint(Self.failureHint(error))
    }

    private static func failureHint(_ error: GitHubError) -> String {
        switch error {
        case .transport: "网络不可用"
        case .rateLimited: "请求过于频繁"
        case .unauthorized: "登录状态已失效"
        default: "服务暂时不可用"
        }
    }

    // MARK: - 路由
    //
    // 两处分流的依据**不同**（一个来自 GraphQL 字段、一个来自本机记录），
    // 但两个判据都收在领域层（`canOpenWritableDetail` / `RecentVisit.canWrite`），
    // 所以这里只做一件事：把布尔值翻成路由。**不要**在这里再写一次权限判断。

    /// 置顶卡 → 自己的仓库详情（§4.4）或他人只读页（§4.13）。
    private func openPinned(_ summary: RepoSummary) {
        env.router.push(
            summary.canOpenWritableDetail
                ? .repoDetail(fullName: summary.fullName)
                : .exploreRepoDetail(fullName: summary.fullName)
        )
    }

    /// 最近访问行 → 依据**写入时记下的归属**分流（PRD §3.13）。
    private func openVisit(_ visit: RecentVisit) {
        env.router.push(
            visit.canWrite
                ? .repoDetail(fullName: visit.fullName)
                : .exploreRepoDetail(fullName: visit.fullName)
        )
    }

    /// 「管理」→ 打开网页端个人主页。
    ///
    /// ⚠️ **App 内不提供置顶增删**：GraphQL 变更集里不存在任何置顶相关 mutation，
    /// REST 侧也没有置顶端点（TECH_SPEC §9.1 有完整依据）⇒ 只能跳网页端。
    /// 提示必须先给再跳 —— 否则用户会以为"App 把我踢到浏览器了"。
    private func managePins() {
        env.toast.show(HomeCopy.managePinsToast)
        guard let url = URL(string: "https://github.com/\(login)") else { return }
        openURL(url)
    }
}

#Preview {
    @Previewable @State var environment = AppEnvironment()
    NavigationStack {
        HomeView(
            login: "jiangjiang",
            pinned: environment.pinnedRepositories,
            visits: environment.recentVisits,
            toast: environment.toast
        )
    }
    .environment(environment)
}
