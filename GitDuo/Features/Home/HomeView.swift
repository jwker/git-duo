import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 首页 —— Tab 根页（PRD §4.1、TECH_SPEC §9.1）。
///
/// 结构：大标题「首页」+ 右上角搜索 · 「置顶仓库」**行列表**（最多 6 条，
/// ⚠️ 2026-10-15 走查第 75 条起不再是 2 列网格）·「最近访问」列表。
///
/// ## ⚠️ 2026-10-16 起主干是 **`List`**（NATIVE-MIGRATION P3）
///
/// 从前是 `ScrollView + VStack` + 每组分装一张 `CardBox` + 行自己画内嵌 hairline。
/// 换成 `List` 之后白拿回来的东西：
///
/// | 白拿的 | 从前怎么来的 |
/// |---|---|
/// | 行间分隔线（**首行不画、末行不画**） | 靠调用方手数 index 传 `showsSeparator`（走查第 76/77 条那一族口径） |
/// | 整行点击范围与按下高亮 | `Button` + `.plain`，没有高亮 |
/// | 行内边距 / 卡片底 / 圆角 | 行自己 `padding(14)` + `CardBox` + 页面左右留白 |
/// | 列表的可达性 / 动态类型 / 性能 | 自绘 |
///
/// ⇒ 那一整族"顶线还是底线、缩进 66/56/57"的问题**随自绘件一起消失**。
/// 分隔线由系统画，它对"谁是首行"有确定的答案。
///
/// ⚠️ 两条**有意保留**的自定观感（属于 P5 令牌收尾，不在本期）：
/// 页面底仍是 `Theme.Palette.background`（浅灰），行底仍是 `Theme.Palette.surface`
/// —— 不让 `List` 自带的系统底色盖掉主题（`.scrollContentBackground(.hidden)`）。
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
        List {
            pinnedSection
            recentSection
        }
        .listStyle(.insetGrouped)
        // 主题的页面底 / 行底不交给系统（P5 才动令牌）—— 只把 `List` 自带的底色让开。
        .scrollContentBackground(.hidden)
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
        // ⚠️ **2026-10-16 起这里是系统 `.alert`**（NATIVE-MIGRATION P1）。
        //    此前它是自绘的 `ClearRecentSheet`（2026-10-07 从 `.confirmationDialog`
        //    改回去的，理由是"原型画的是一张底部卡片"）—— 而原型现在只是**功能清单**
        //    （`AGENTS.md §0`），视觉正本是 HIG。**清除浏览记录是破坏性且不可撤销的动作**，
        //    HIG 给这种动作的正是 alert（居中的"标题 + 说明 + 两个按钮"），
        //    不是动作表、也不是一张自绘卡。
        //
        //    `role:` 是这次白拿回来的东西：`.destructive` 让系统把那颗按钮画成红色，
        //    `.cancel` 让它自动成为"取消"那一档（含点遮罩 / 手势取消的等价语义），
        //    **不用自己配颜色、也不用自己排顺序**。
        .alert(HomeCopy.clearConfirmTitle, isPresented: $isConfirmingClear) {
            Button(HomeCopy.clearConfirmAction, role: .destructive) {
                Task { await model.clearVisits() }
            }
            Button(HomeCopy.clearConfirmCancel, role: .cancel) {}
        } message: {
            Text(HomeCopy.clearConfirmHint)
        }
    }

    // MARK: - 置顶仓库

    @ViewBuilder
    private var pinnedSection: some View {
        Section {
            switch model.pinned.presentation {
            case .skeleton:
                PinRowsSkeleton()

            case .content:
                pinnedRows

            case let .failure(error):
                SectionFailure(error: error) {
                    Task { await model.refresh() }
                }
                // 空态 / 失败态**不是列表内容** ⇒ 不坐白卡、不画分隔线
                //（官方件自带上下留白，坐白卡里会像"一条空记录"）。
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } header: {
            // ⚠️ `margins: .none` —— 组间距现在由 `List` 的 section 机制给，
            //    标题再自带 22 的上边距就叠了一层。
            SectionHeader(
                title: HomeCopy.pinnedSection,
                actionTitle: HomeCopy.pinnedManage,
                action: managePins,
                margins: .none
            )
        }
    }

    /// 内容态。**空数组是正常结果**（还没置顶任何仓库），不是错误（TECH_SPEC §9.1）。
    @ViewBuilder
    private var pinnedRows: some View {
        let items = model.pinned.value ?? []
        if items.isEmpty {
            EmptyBox(title: HomeCopy.pinnedEmptyTitle, hint: HomeCopy.pinnedEmptyHint,
                    systemImage: "pin.slash")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
                ForEach(items) { summary in
                    // ⚠️ 用 `Button` + `router.push` 而不是 `NavigationLink(value:)`：
                    //    `NavigationLink` 行在 `.insetGrouped` 里的分隔线会被系统默认
                    //    缩短到 disclosure indicator 左侧（"只在右侧小箭头下方一点点"），
                    //    这是 iOS 的默认行为，`.listRowInsets` 改不了。
                    //    `Button` + `.buttonStyle(.plain)` 同样整行可点、有按下高亮，
                    //    且分隔线保持全宽（与 P3 前旧版一致）。
                    Button {
                        env.router.push(pinnedRoute(summary))
                    } label: {
                        PinRow(summary: summary)
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Theme.Palette.surface)
        }
    }

    // MARK: - 最近访问

    @ViewBuilder
    private var recentSection: some View {
        // 「清除」只在**有记录时**出现（PRD §4.1 结构第 3 条）。
        // 没有记录还摆一个"清除"是个必然失败的动作 —— 而且它会让人以为"本来有东西"。
        let visits = model.visits
        let hasVisits = !visits.isEmpty
        Section {
            if hasVisits {
                // ⚠️ 不做本地去重 / 裁剪：上限 6 与"同一仓库只留一条"都在存储那一侧保证
                //    （`RecentVisitStore`），这里重做一遍就等于有了两份规则。
                ForEach(visits) { visit in
                    // ⚠️ 同置顶行：用 `Button` + `router.push` 保持分隔线全宽。
                    Button {
                        env.router.push(visitRoute(visit))
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
                            ownerAvatarURL: visit.ownerAvatarURL
                        )
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Theme.Palette.surface)
            } else {
                EmptyBox(title: HomeCopy.recentEmptyTitle, hint: HomeCopy.recentEmptyHint,
                        systemImage: "clock")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        } header: {
            SectionHeader(
                title: HomeCopy.recentSection,
                actionTitle: hasVisits ? HomeCopy.recentClear : nil,
                action: hasVisits ? { isConfirmingClear = true } : nil,
                margins: .none
            )
        }
    }

    // MARK: - 路由
    //
    // 两处分流的依据**不同**（一个来自 GraphQL 字段、一个来自本机记录），
    // 但两个判据都收在领域层（`canOpenWritableDetail` / `RecentVisit.canWrite`），
    // 所以这里只做一件事：把布尔值翻成路由。**不要**在这里再写一次权限判断。

    /// 置顶卡 → 自己的仓库详情（§4.4）或他人只读页（§4.13）。
    private func pinnedRoute(_ summary: RepoSummary) -> Route {
        summary.canOpenWritableDetail
            ? .repoDetail(fullName: summary.fullName)
            : .exploreRepoDetail(fullName: summary.fullName)
    }

    /// 最近访问行 → 依据**写入时记下的归属**分流（PRD §3.13）。
    private func visitRoute(_ visit: RecentVisit) -> Route {
        visit.canWrite
            ? .repoDetail(fullName: visit.fullName)
            : .exploreRepoDetail(fullName: visit.fullName)
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
