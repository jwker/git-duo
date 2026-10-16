import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 探索页要呈现的弹层（TECH_SPEC §8.4 的路由枚举形态）。
///
/// ⚠️ **用枚举驱动 `.sheet(item:)`，不用 `isPresented` 布尔量**：本页将来还会有别的弹层
/// （分支…），两个布尔量同时为真时"哪一张盖在上面"就变成了呈现顺序问题，
/// 而那种 bug 只在特定点击序列下出现。一个 `Identifiable` 的枚举天然只有一张。
///
/// 目前只有筛选一张 —— §5 的其余 13 类弹层属于各自的功能切片，届时在各自的 Feature 里
/// 定义、或提升成一个共用的 `SheetRoute`（TECH_SPEC §8.4 的原意就是后者）。
enum ExploreSheet: Identifiable {
    case filter(ExploreFilterKind)

    var id: String {
        switch self {
        case let .filter(kind): "filter.\(kind.rawValue)"
        }
    }
}

/// 探索 Tab 根页（PRD §4.12、TECH_SPEC §9.10）。
///
/// 结构：大标题「探索」+ 右上角搜索 · 榜单分段（新星榜 / 活跃榜）· 两个筛选 chip ·
/// （可选）结果不完整说明行 · 趋势卡片列表。
///
/// ⚠️ **列表标题那一行已删**（2026-10-16 用户要求，走查第 **78** 条）：原本是
/// 「新星榜 · 30 个仓库」这样一句 —— 榜单名分段条上已经有了，条数又随翻页变，
/// 用户认为这两块字是重复的噪音。原型 `09-explore.js` 的 `.section-label#trendTitle`
/// 与 `ExploreViewModel.listTitle` 一并删除。
///
/// ## ⚠️ 这一屏最贵的是配额
///
/// Search 是**独立且只有 30 次/分钟**的桶（§13.2）。所以"切榜 / 切筛选"这条路径上
/// 有三道闸门，缺一道用户连点几下就会吃 403：
/// ① **缓存优先**（同一组合来回切直接命中，不出网）；② **防抖 300ms**；③ **取消在途**。
/// 三道都在 `ExploreViewModel` 里（它是唯一知道"有没有新的点击到来"的地方）。
struct ExploreView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var model: ExploreViewModel
    @State private var sheet: ExploreSheet?

    /// 依赖由**组合根**经父视图传下来（`MainTabView` 读 `env.trending`）。
    init(loader: LoadTrendingBoard) {
        _model = State(initialValue: ExploreViewModel(loader: loader))
    }

    var body: some View {
        // ⚠️ 2026-10-11：滚动容器**提到了根上**，分段条改成**吸顶的分区头** ——
        //    与「首页」「我的」同一形状，大标题才会在上滑时收成顶部一行小字。
        //    此前本页与 `ReposView` 一样把 `ScrollView` 塞在 `VStack` 里（分段条在外），
        //    导航栏盯不住那个滚动视图 ⇒ **大标题不收**。用户报回「与首页不一样」。
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    mainArea
                } header: {
                    boardBar
                        // ⚠️ 吸顶时它是**压在**滚过去的内容上的 ⇒ 这一层必须不透明，
                        //    否则趋势卡会从分段之间的缝隙里透出来。
                        .background(Theme.Palette.background)
                }
            }
        }
        .refreshable { await model.refresh() }
        .background(Theme.Palette.background)
        .navigationTitle("探索")
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
        .sheet(item: $sheet) { route in
            switch route {
            case let .filter(kind):
                ExploreFilterSheet(
                    kind: kind,
                    selected: model.filters.selectedValue(kind)
                ) { picked in
                    apply(kind: kind, picked: picked)
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .task { await model.loadIfNeeded() }
    }

    // MARK: - 顶部

    private var boardBar: some View {
        SegmentedBar(
            segments: TrendingBoard.allCases.map { SegmentedBar.Segment(id: $0.id, title: $0.title) },
            selectedID: model.board.id
        ) { picked in
            guard let board = TrendingBoard(rawValue: picked.id) else { return }
            model.select(board: board)
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    private var chips: some View {
        HStack(spacing: Theme.Spacing.s) {
            FilterChip(
                title: model.filters.rangeChipLabel,
                isHighlighted: model.filters.isHighlighted(.range)
            ) {
                sheet = .filter(.range)
            }
            FilterChip(
                title: model.filters.languageChipLabel,
                isHighlighted: model.filters.isHighlighted(.language)
            ) {
                sheet = .filter(.language)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
    }

    // MARK: - 主区域

    /// 滚动内容。⚠️ **这里自己不再是滚动容器** —— 它在 `body` 那一层那个
    /// `ScrollView` 里（2026-10-11 起），左右页边距加在它身上，
    /// 而吸顶的 `boardBar` 在它**外面**（`SegmentedBar` 自带页边距，
    /// 再套一层会变成双份）。
    private var mainArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            chips

            // ⚠️ `incomplete_results` 的说明行**不是错误态**（PRD §4.12）：
            //    已拿到的条目照常显示，只是这一页少了些本该在里面的仓库。
            //    不静默忽略的理由见 `ExploreBoardNotice`。
            if let notice = model.notice {
                Text(notice)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.bottom, Theme.Spacing.s)
            }

            content

            footer
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.bottom, Theme.Spacing.xl)
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .skeleton:
            ExploreBoardSkeleton()
                .padding(.top, Theme.Spacing.xs)

        case .items:
            rows

        case .needsMore, .empty:
            // 探索榜没有"本地过滤"这回事（筛选是**服务端**限定符），所以 `needsMore`
            // 在这里只可能出现在"第一页恰好为空、但还有下一页"这种极窄的情形。
            // 两者都落进空态框 —— 但文案不同：结果不完整时**不能说"没有符合条件的仓库"**
            // （那正是 `LoadTrendingBoard.Result.emptyText` 存在的理由）。
            EmptyBox(title: model.emptyText, systemImage: "magnifyingglass")
                .padding(.top, Theme.Spacing.s)

        case let .failure(error):
            failureState(error)
        }
    }

    private var rows: some View {
        // 过滤 / 计算只算一次：`onAppear` 里逐行判断"是不是最后一行"是 O(n²)。
        let items = model.rows
        let lastID = items.last?.id

        return VStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, row in
                Button {
                    open(row)
                } label: {
                    TrendCard(summary: row.summary, badges: badges(row))
                }
                .buttonStyle(.plain)
                .onAppear {
                    // 只有最后一行触发，否则每出现一行就打一次请求（§4.4：普通列表滚到底自动加载）。
                    if row.id == lastID {
                        Task { await model.loadMore() }
                    }
                }
            }
        }
    }

    /// 角标映射：领域层的 `Role` → 组件的 `BadgeTone`。
    ///
    /// 两者名字不同是有意的：领域层说的是"它扮演什么角色"，组件说的是"用哪一种语气画"。
    /// 这里是一次显式翻译，而不是给两者取同一个名字 —— 那样将来任一侧增减取值都会悄悄串味。
    private func badges(_ row: TrendingRow) -> [TrendCard.Badge] {
        row.indicators.map { indicator in
            TrendCard.Badge(
                indicator.text,
                tone: indicator.role == .metric ? .metric : .plain
            )
        }
    }

    /// 列表底部：加载中 → 转圈；失败 → 重试行（**不遮挡已有内容**，§8.5）。
    @ViewBuilder
    private var footer: some View {
        if model.isLoading, !model.rows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.m)
        } else if model.error != nil, !model.rows.isEmpty {
            Button("加载失败 · 重试") {
                Task { await model.loadMore() }
            }
            .font(Theme.Font.footnote)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.m)
        }
    }

    /// 首屏失败 —— 必须留一个出口（PRD §1 设计原则 4）。
    private func failureState(_ error: GitHubError) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
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
        .padding(.vertical, Theme.Spacing.xxl)
        .accessibilityElement(children: .combine)
        // 失败原因**只说确定的那一件事**（与 `ReposView.failureHint` 同一口径）。
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

    // MARK: - 动作

    /// 筛选弹层里点了某一项 → 交给 ViewModel（"再点当前项 = 取消"的规则在领域层）→ 给提示。
    private func apply(kind: ExploreFilterKind, picked: String) {
        let change: ExploreFilterChange = switch kind {
        case .range:
            ExploreDateRange.allCases.first { $0.title == picked }
                .map { model.select(range: $0) } ?? ExploreFilterChange.cancelled(.range)
        case .language:
            model.select(language: picked)
        }
        env.toast.show(change.toastText)
    }

    /// 趋势卡 → 他人仓库只读页（§4.13）。
    ///
    /// ⚠️ 搜索路径**给不出可写性**（`GET /search/repositories` 不返回 `permissions`），
    /// 所以这里**只有一条路**：进只读页。不要试图用"全名是不是以我的登录名开头"补一个判断
    /// —— 见 `RepoSummary.canWrite` 的说明（PRD §3.13 明确禁止）。
    ///
    /// ⚠️ 反过来说：**用户自己的公开仓库出现在榜单里时也会进只读页**。这是有意接受的误差 ——
    /// 榜单是"发现"语境，进的是浏览页；真要看自己的仓库，走首页或仓库 Tab。
    private func open(_ row: TrendingRow) {
        env.router.push(.exploreRepoDetail(fullName: row.fullName))
    }
}

#Preview {
    @Previewable @State var environment = AppEnvironment()
    NavigationStack {
        ExploreView(loader: environment.trending)
    }
    .environment(environment)
}
