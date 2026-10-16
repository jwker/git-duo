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
/// 结构：大标题「探索」· 榜单分段（新星榜 / 活跃榜）· 两个筛选 chip ·
/// （可选）结果不完整说明行 · 趋势卡片列表。
///
/// ⚠️ **2026-10-16：右上角那颗放大镜已移除**（走查第 85 条）——
/// 搜索搬去了底部第 4 格 Tab（`AppTab.search`）。理由同 `ReposView`。
///
/// ⚠️ **列表标题那一行已删**（2026-10-16 用户要求，走查第 **78** 条）：原本是
/// 「新星榜 · 30 个仓库」这样一句 —— 榜单名分段条上已经有了，条数又随翻页变，
/// 用户认为这两块字是重复的噪音。原型 `09-explore.js` 的 `.section-label#trendTitle`
/// 与 `ExploreViewModel.listTitle` 一并删除。
///
/// ## ⚠️ 2026-10-16 起主干是 **`List`**（NATIVE-MIGRATION P3）
///
/// 与 `ReposView` 同一处置：`ScrollView + LazyVStack` → `List`；
/// 榜单分段条从吸顶的 `.safeAreaInset(edge: .top)` 改回 `List` 的 `Section` header。
/// P3 首批用 `.safeAreaInset` 实现了吸顶，但它会**吞掉导航栏大标题**，属于回归；
/// 在 SwiftUI 当前 API 下「大标题 + 分组形状 + 吸顶」三者不可兼得，
/// 这里保留大标题 + 分组形状，让榜单条随内容滚动。
///
/// chip / 说明行 / 空态 / 失败态都是**行**（不坐白卡、不画分隔线 —— 它们不是列表内容）。
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
        List {
            Section {
                chips
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                // ⚠️ `incomplete_results` 的说明行**不是错误态**（PRD §4.12）：
                //    已拿到的条目照常显示，只是这一页少了些本该在里面的仓库。
                //    不静默忽略的理由见 `ExploreBoardNotice`。
                if let notice = model.notice {
                    Text(notice)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                content
            } header: {
                // ⚠️ 榜单分段条作为 Section header 回到 `List` 内部。
                //    它不再吸顶（理由见文件头说明）。
                boardBar
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.background)
        .refreshable { await model.refresh() }
        .navigationTitle("探索")
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

    /// 两个筛选 chip。⚠️ 它现在是**一行** ⇒ 上下留白由 `List` 的行内边距给
    /// （从前这里手写 `padding(.top, s).padding(.bottom, m)`）。
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
    }

    // MARK: - 主区域

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .skeleton:
            ExploreBoardSkeleton()
                .listRowBackground(Theme.Palette.surface)

        case .items:
            rows

        case .needsMore, .empty:
            // 探索榜没有"本地过滤"这回事（筛选是**服务端**限定符），所以 `needsMore`
            // 在这里只可能出现在"第一页恰好为空、但还有下一页"这种极窄的情形。
            // 两者都落进空态框 —— 但文案不同：结果不完整时**不能说"没有符合条件的仓库"**
            // （那正是 `LoadTrendingBoard.Result.emptyText` 存在的理由）。
            EmptyBox(title: model.emptyText, systemImage: "magnifyingglass")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

        case let .failure(error):
            // 首屏失败 —— 必须留一个出口（PRD §1 设计原则 4）。
            PageFailure(error: error) {
                Task { await model.refresh() }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var rows: some View {
        // 过滤 / 计算只算一次：`onAppear` 里逐行判断"是不是最后一行"是 O(n²)。
        let items = model.rows
        let lastID = items.last?.id

        ForEach(items) { row in
            // ⚠️ 同 `ReposView`：不用 `NavigationLink(value:)`，
            //    避免 `.insetGrouped` 里分隔线被缩短到 disclosure indicator 左侧。
            //    榜单行**只有一条路**：进只读页（`GET /search/repositories` 不返回
            //    `permissions`）。不要试图用"全名是不是以我的登录名开头"补判断 ——
            //    见 `RepoSummary.canWrite` 的说明（PRD §3.13 明确禁止）。
            Button {
                env.router.push(.exploreRepoDetail(fullName: row.fullName))
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
        .listRowBackground(Theme.Palette.surface)

        footer
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
    /// ⚠️ 它不是"内容" ⇒ 不坐白卡、不画分隔线。
    @ViewBuilder
    private var footer: some View {
        if model.isLoading, !model.rows.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if model.error != nil, !model.rows.isEmpty {
            Button("加载失败 · 重试") {
                Task { await model.loadMore() }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
}

#Preview {
    @Previewable @State var environment = AppEnvironment()
    NavigationStack {
        ExploreView(loader: environment.trending)
    }
    .environment(environment)
}
