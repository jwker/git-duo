import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 仓库 Tab 根页（PRD §4.3）。
///
/// 结构：大标题「仓库」+ 右上角搜索图标 · 四个分段（全部 / 公开 / 私有 / Starred）· 卡片列表。
/// 状态：骨架屏 →「继续加载」/ 内容 / 逐段空态 / 失败重试（§8.5 的三档统一）。
///
/// ## ⚠️ 2026-10-16 起主干是 **`List`**（NATIVE-MIGRATION P3）
///
/// 三处结构性改动：
///
/// 1. **内容主干** `ScrollView + LazyVStack` → `List`（行件只画内容，
///    行底 / 分隔线 / 行内边距由系统给）。
/// 2. **分段条从"吸顶的 section header"改成 `safeAreaInset(edge: .top)`**。
///    从前那条吸顶效果是 `LazyVStack(pinnedViews: [.sectionHeaders])` 做出来的；
///    `List` 里做同一件事要么换 `.plain` 风格（行会变成通栏、失去分组形状），
///    要么在分区头里塞一个 `Picker`（不是它的用途）。
///    `safeAreaInset` 是官方给"标题栏下面常驻一条工具条"的机制 ——
///    **内容从它下面滚过去，而它自己永远不消失**，比吸顶还稳。
/// 3. **空态 / 失败态换成官方件**（`EmptyBox` / `PageFailure`）——
///    从前这两处是本文件里手摆的 `VStack`（第 8、9 份同形实现）。
///
/// ⚠️ 两条**有意保留**的自定观感（属 P5 令牌收尾）：页面底 `Theme.Palette.background`、
///    行底 `Theme.Palette.surface` —— 用 `.scrollContentBackground(.hidden)` 把
///    `List` 自带的底色让开。
///
/// ⚠️ **可写性判定唯一来源 = `Repository.permissions.push`**（TECH_SPEC §8.1、铁律 #7）。
///    本视图只读 `entry`，不自己判断"这是不是我的仓库" ——
///    原型里用 `fullName.hasPrefix("my-git/")` 是**无后端时的演示简化**，不得照搬。
struct ReposView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var model: RepoListViewModel

    /// 依赖由**组合根**经父视图传下来（`MainTabView` 读 `env.repositories`），
    /// 本视图与 ViewModel 都不自行构造客户端（AGENTS.md §3）。
    init(loader: LoadRepositoriesPage) {
        // `State(initialValue:)` 只在首次构造时生效 —— 视图重建不会把状态冲掉。
        _model = State(initialValue: RepoListViewModel(loader: loader))
    }

    var body: some View {
        Group {
            switch model.content {
            case .items, .skeleton:
                listBody

            case .needsMore, .empty, .failure:
                // 这三档**本来就没有可滚的内容**，保持"分段条在外、内容居中"
                //（`EmptyBox` / `PageFailure` 自带完整留白，不需要外层再撑）。
                centeredBody
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            segmentBar
                // ⚠️ 内容会从它**下面**滚过去 ⇒ 这一层必须不透明，否则卡片会从
                //    分段条与导航栏之间的缝隙里透出来。
                .background(Theme.Palette.background)
        }
        .background(Theme.Palette.background)
        .navigationTitle("仓库")
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
        .task { await model.loadIfNeeded() }
    }

    // MARK: - 分段
    //
    // ⚠️ 形状来自 2026-10-06 的裁定：原型 `styles/03-components.css` 的 `.seg` 是
    //    **深底白字、8pt 圆角**（`.seg.on{background:var(--text);color:#fff}`），
    //    此前这里是自制的"绿色胶囊" ⇒ 收进 `GitDuoDesign.SegmentedBar` 与探索页共用。
    //    P2 起它的内胆是官方 `Picker(.segmented)`（见 `SegmentedBar` 的类型说明）。

    private var segmentBar: some View {
        SegmentedBar(
            segments: RepoListSegment.allCases.map {
                SegmentedBar.Segment(id: $0.id, title: $0.title)
            },
            selectedID: model.segment.id
        ) { picked in
            guard let segment = RepoListSegment(rawValue: picked.id) else { return }
            Task { await model.select(segment) }
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    // MARK: - 有内容时的主干

    private var listBody: some View {
        List {
            switch model.content {
            case .skeleton:
                RepoCardSkeleton()
                    .listRowBackground(Theme.Palette.surface)

            case .items:
                listRows

            default:
                EmptyView()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await model.refresh() }
    }

    @ViewBuilder
    private var listRows: some View {
        // 过滤只算一次：每次渲染现算（§9.3 的本地过滤），但不要在一行里算 N 遍 ——
        // 尤其是 `onAppear` 里那句判断，逐行各过滤一次就是 O(n²)。
        let items = model.visibleItems
        let lastID = items.last?.id

        ForEach(items) { repository in
            // 整行可点 = `List` 行的既有语义（系统给按下高亮与右侧箭头），
            // 落点与 `router.push` 完全同一条路径。
            NavigationLink(value: route(for: repository)) {
                RepoCard(repository: repository)
            }
            .onAppear {
                // 滚到底自动加载（§4.4：普通列表用自动加载，搜索才用手动按钮）。
                // 只对最后一行触发，否则每次出现一行都会打一次请求。
                if repository.id == lastID {
                    Task { await model.loadMore() }
                }
            }
        }
        .listRowBackground(Theme.Palette.surface)

        footer
    }

    /// 列表底部：加载中 → 转圈；失败 → 重试行（**不遮挡已有内容**，§8.5）。
    ///
    /// ⚠️ 它不是"内容" ⇒ 不坐白卡、不画分隔线。
    @ViewBuilder
    private var footer: some View {
        if model.isLoading, !model.visibleItems.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if model.error != nil, !model.visibleItems.isEmpty {
            Button("加载失败 · 重试") {
                Task { await model.loadMore() }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: - 没有可滚内容时的三档

    @ViewBuilder
    private var centeredBody: some View {
        Group {
            switch model.content {
            case .needsMore:
                continueLoading

            case .empty:
                EmptyBox(title: model.segment.emptyTitle, systemImage: "folder")

            case let .failure(error):
                // 首屏失败 —— 必须留一个出口（PRD §1 设计原则 4：任何失败都有出口）。
                PageFailure(error: error) {
                    Task { await model.refresh() }
                }

            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 空、但服务端还有下一页 —— 这时**不能说「还没有…」**。
    ///
    /// 为什么需要一个显式按钮：空列表没有可滚内容，`.onAppear` 的自动加载永远触发不到。
    /// 而这一页为空只是"这一页没有该段的条目"（三段共用一份数据本地过滤的必然产物）。
    @ViewBuilder
    private var continueLoading: some View {
        if model.isLoading {
            ProgressView()
        } else {
            Button("继续加载") {
                Task { await model.loadMore() }
            }
        }
    }

    // MARK: - 路由

    /// 可写 ⇒ 可写详情页；只读 ⇒ 探索（只读）详情页。
    private func route(for repository: Repository) -> Route {
        switch repository.entry {
        case .writable:
            .repoDetail(fullName: repository.fullName)
        case .readOnly:
            .exploreRepoDetail(fullName: repository.fullName)
        }
    }
}

#Preview {
    @Previewable @State var environment = AppEnvironment()
    NavigationStack {
        ReposView(loader: environment.repositories)
    }
    .environment(environment)
}
