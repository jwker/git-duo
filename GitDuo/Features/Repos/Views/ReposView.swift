import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 仓库 Tab 根页（PRD §4.3）。
///
/// 结构：大标题「仓库」+ 右上角搜索图标 · 四个分段（全部 / 公开 / 私有 / Starred）· 卡片列表。
/// 状态：骨架屏 →「继续加载」/ 内容 / 逐段空态 / 失败重试（§8.5 的三档统一）。
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
        // ⚠️ 2026-10-11：这里改成了**两种骨架**，只为修一件事 ——
        //    「首页」与「我的」两页是 `ScrollView` **直接当根**，上滑时大标题会收成
        //    顶部一行小字；本页此前把 `ScrollView` 塞进 `VStack` 里（分段条在外），
        //    导航栏就盯不住那个滚动视图了，大标题**不收**。用户报回「与首页不一样」。
        //
        //    修法就是按首页那样把滚动容器提到根上；分段条仍旧**吸顶**
        //    （用 `pinnedViews` 的 section header，不是把它挪进滚动内容里 ——
        //     那样它会跟着滚走，切分段的入口就没了）。
        Group {
            switch model.content {
            case .items, .skeleton:
                scrollableBody

            case .needsMore, .empty, .failure:
                // 这三档**本来就没有可滚的内容**，保持原样（分段条在外、内容居中）。
                // ⚠️ 别顺手把它们也塞进 `ScrollView`：滚动视图给内容的建议高度是 `nil`，
                //    那几颗用来居中的 `Spacer` 会塌成 0，空态 / 失败态会掉到顶上 ——
                //    而它们挂着「重试」出口，位置一变就像换了个页面。
                VStack(spacing: 0) {
                    segmentBar
                    mainArea
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
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

    /// 有内容时的骨架：滚动容器在根上，分段条是**吸顶的分区头**。
    private var scrollableBody: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    mainArea
                } header: {
                    segmentBar
                        // ⚠️ 吸顶时它是**压在**滚过去的内容上的 ⇒ 这一层必须不透明，
                        //    否则卡片会从分段之间的缝隙里透出来。
                        .background(Theme.Palette.background)
                }
            }
        }
        .refreshable { await model.refresh() }
    }

    // MARK: - 分段
    //
    // ⚠️ 2026-10-06 改回原型：此前这里是自制的"绿色胶囊"（`accentStrong` + `Capsule`），
    //    而原型 `styles/03-components.css` 的 `.seg` 是**深底白字、8pt 圆角**
    //    （`.seg.on{background:var(--text);color:#fff}`）。形状与配色两处都不同。
    //    用户拍板「两处都改回原型」⇒ 收缩进 `GitDuoDesign.SegmentedBar`，
    //    与探索页的榜单分段共用同一份实现。

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

    // MARK: - 主区域

    /// ⚠️ **这里自己不再是滚动容器** —— 滚动与吸顶的分段条都在 `body` 那一层
    /// （2026-10-11 起；此前 `.skeleton` / `.items` 各自带一个 `ScrollView`）。
    @ViewBuilder
    private var mainArea: some View {
        switch model.content {
        case .skeleton:
            RepoCardSkeleton().padding(pageInsets)

        case .items:
            list

        case .needsMore:
            continueLoading

        case .empty:
            emptyState

        case let .failure(error):
            failureState(error)
        }
    }

    private var list: some View {
        // 过滤只算一次：每次渲染现算（§9.3 的本地过滤），但不要在一行里算 N 遍 ——
        // 尤其是 `onAppear` 里那句判断，逐行各过滤一次就是 O(n²)。
        let items = model.visibleItems
        let lastID = items.last?.id

        return LazyVStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, repository in
                Button {
                    open(repository)
                } label: {
                    // 方案 D：条目去形，行间靠顶上那条内嵌 hairline 分隔 —— 首行不画。
                    RepoCard(repository: repository, showsTopSeparator: index > 0)
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

            footer
        }
        .padding(pageInsets)
    }

    /// 列表底部：加载中 → 转圈；失败 → 重试行（**不遮挡已有内容**，§8.5）。
    @ViewBuilder
    private var footer: some View {
        if model.isLoading, !model.visibleItems.isEmpty {
            ProgressView()
                .padding(.vertical, Theme.Spacing.m)
        } else if model.error != nil, !model.visibleItems.isEmpty {
            Button("加载失败 · 重试") {
                Task { await model.loadMore() }
            }
            .font(Theme.Font.footnote)
            .padding(.vertical, Theme.Spacing.m)
        }
    }

    /// 空、但服务端还有下一页 —— 这时**不能说「还没有…」**。
    ///
    /// 为什么需要一个显式按钮：空列表没有可滚内容，`.onAppear` 的自动加载永远触发不到。
    /// 而这一页为空只是"这一页没有该段的条目"（三段共用一份数据本地过滤的必然产物）。
    private var continueLoading: some View {
        VStack(spacing: Theme.Spacing.m) {
            Spacer(minLength: 0)
            if model.isLoading {
                ProgressView()
            } else {
                Button("继续加载") {
                    Task { await model.loadMore() }
                }
                .font(Theme.Font.body)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.s) {
            Spacer(minLength: 0)
            Image(systemName: "folder")
                .font(.system(size: 34))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(model.segment.emptyTitle)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 首屏失败 —— 必须留一个出口（PRD §1 设计原则 4：任何失败都有出口）。
    private func failureState(_ error: GitHubError) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Spacer(minLength: 0)
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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityHint(failureHint(error))
    }

    /// 失败原因**只说确定的那一件事**：404 与无权限被 GitHub 混同（§4.3），不得替用户断定。
    private func failureHint(_ error: GitHubError) -> String {
        switch error {
        case .transport: "网络不可用"
        case .rateLimited: "请求过于频繁"
        case .unauthorized: "登录状态已失效"
        default: "服务暂时不可用"
        }
    }

    // MARK: - 工具

    private var pageInsets: EdgeInsets {
        EdgeInsets(
            top: Theme.Spacing.s,
            leading: Theme.Spacing.page,
            bottom: Theme.Spacing.xl,
            trailing: Theme.Spacing.page
        )
    }

    /// 路由选择：可写 ⇒ 可写详情页；只读 ⇒ 探索（只读）详情页。
    private func open(_ repository: Repository) {
        switch repository.entry {
        case .writable:
            env.router.push(.repoDetail(fullName: repository.fullName))
        case .readOnly:
            env.router.push(.exploreRepoDetail(fullName: repository.fullName))
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
