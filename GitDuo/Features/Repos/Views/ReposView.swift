import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 仓库 Tab 根页（PRD §4.3）。
///
/// 结构：大标题「仓库」· 四个分段（全部 / 公开 / 私有 / Starred）· 卡片列表。
/// 状态：骨架屏 →「继续加载」/ 内容 / 逐段空态 / 失败重试（§8.5 的三档统一）。
///
/// ⚠️ **2026-10-16：右上角那颗放大镜已移除**（走查第 85 条）。
/// 搜索搬去了底部第 4 格 Tab（`AppTab.search`）—— 从前它在首页 / 本页 / 探索页
/// 右上角各挂一颗，三处重复且都不是"任何地方都按得到"的位置；底部一格才是。
///
/// ## ⚠️ 2026-10-16 起主干是 **`List`**（NATIVE-MIGRATION P3）
///
/// 三处结构性改动：
///
/// 1. **内容主干** `ScrollView + LazyVStack` → `List`（行件只画内容，
///    行底 / 分隔线 / 行内边距由系统给）。
/// 2. **分段条回到 `List` 内部** —— 作为 `Section` 的 header。
///    P3 首批曾用 `.safeAreaInset(edge: .top)` 让它吸顶，但那会让导航栏**大标题消失**，
///    属于回归。在 SwiftUI 当前 API 下，「大标题 + 分组形状 + 吸顶」三者不可兼得：
///    `.plain` 风格能吸顶但行变通栏；`.safeAreaInset` 能吸顶但吞大标题。
///    这里选择保留大标题 + 分组形状，让分段条随内容滚动。
/// 3. **空态 / 失败态换成官方件**（`EmptyBox` / `PageFailure`）。
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
        .background(Theme.Palette.background)
        .navigationTitle("仓库")
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
            Section {
                switch model.content {
                case .skeleton:
                    RepoCardSkeleton()
                        .listRowBackground(Theme.Palette.surface)

                case .items:
                    listRows

                default:
                    EmptyView()
                }
            } header: {
                segmentBar
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
            // ⚠️ 不用 `NavigationLink(value:)`：它在 `.insetGrouped` 里的分隔线
            //    会被系统默认缩短到 disclosure indicator 左侧。
            //    `Button` + `.buttonStyle(.plain)` 同样整行可点 + 有按下高亮，
            //    并保留全宽分隔线。
            Button {
                env.router.push(route(for: repository))
            } label: {
                RepoCard(repository: repository)
            }
            .buttonStyle(.plain)
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
        VStack(spacing: 0) {
            segmentBar

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
