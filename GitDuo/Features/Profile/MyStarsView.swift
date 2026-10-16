import GitHubAPI
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 「我的 Star」推入页（PRD §4.18、TECH_SPEC §9.14）。
///
/// 结构：`inline` 标题「我的 Star」· 非私有仓库列表（每行见 `StarRow`）。
/// 状态：骨架 → 内容 / 继续加载 / 空态 / 失败（§8.5 的三档统一）。
///
/// ## ⚠️ 2026-10-16 起主干是 **`List`**（NATIVE-MIGRATION P3）
///
/// 与 `ReposView` 同一处置：`ScrollView + LazyVStack` → `List`；行件只画内容；
/// 空态 / 失败态从手摆的 `VStack` 换成官方件（`EmptyBox` / `PageFailure`）。
/// 没有分段条，所以这里不需要 `safeAreaInset`。
///
/// ## 三处与「搜索页」**有意不同**（PRD §4.18 逐条给过理由）
///
/// | | 本页 | 搜索页 / 我的 PR·Issue |
/// |---|---|---|
/// | 分页 | **滚到底自动加载** | 「加载更多」按钮 |
/// | 理由 | 主桶 5,000/小时，充裕 | 搜索桶 30/分钟，滚动手势会打满它（决策 #44） |
/// | 空态 | 两行（"你还没有 Star 过" + 怎么做才会有） | 同 |
///
/// ## 空态那一句说的是"**你**还没有"，不是"**这里**没有"
///
/// `ProfileCopy.starsEmptyHint` 是**操作引导**（"在仓库页点一下 Star，它就会出现在这里"）。
/// 与探索页那两处（"这个仓库当前没有开放中的 Issue"）用词相近、意思不同 ——
/// 那两处说的是**这个仓库**的状态，这里说的是**你**的归属。别顺手统一。
struct MyStarsView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var model: MyStarsViewModel

    /// 依赖由**组合根**经 `RouteView` 传下来（同其余推入页），本视图不构造客户端。
    ///
    /// ⚠️ `starToggle` 传的是组合根里那**同一个** `ToggleStar` ——
    /// Star 的「先确认基准、再幂等切换」只有一处实现（决策 #41）。
    init(loader: LoadRepositoriesPage, starToggle: ToggleStar, toast: ToastCenter) {
        _model = State(initialValue: MyStarsViewModel(
            loader: loader,
            starToggle: starToggle,
            toast: toast
        ))
    }

    var body: some View {
        Group {
            switch model.content {
            case .items, .skeleton:
                listBody

            case .needsMore, .empty, .failure:
                // 这三档没有可滚内容 ⇒ 保持"内容居中"（官方件自带完整留白）。
                centeredBody
            }
        }
        .background(Theme.Palette.background)
        .navigationTitle(ProfileCopy.starsTitle)
        .task { await model.loadIfNeeded() }
    }

    // MARK: - 主区域

    private var listBody: some View {
        List {
            switch model.content {
            case .skeleton:
                StarRowSkeleton()
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
        // 骨架期不给滚（`.refreshable` 仍可用）—— 同 `ReposView` 的口径。
        .scrollDisabled(model.content == .skeleton)
    }

    @ViewBuilder
    private var listRows: some View {
        // 过滤只算一次：`onAppear` 里逐行现算就是 O(n²)（同 `ReposView`）。
        let items = model.items
        let lastID = items.last?.id

        ForEach(items) { repository in
            // 分流依据是 `Repository.entry`（= `permissions.push`），与仓库页 / 首页置顶卡
            // 用的是同一个判据（铁律 #7：不得在本页自己推断仓库归属）。
            //
            // 与搜索页的区别值得记一句：那一页**给不出可写性**（`GET /search/repositories`
            // 不返回 `permissions`）⇒ 一律进只读页；而 `GET /user/starred` 返回的是**完整仓库
            // 对象**（`RepositoryDTO.permissions` 是有值的）⇒ 这里可以按真实权限分流，
            // 自己的仓库仍进可写详情页。
            NavigationLink(value: route(for: repository)) {
                StarRow(
                    repository: repository,
                    state: model.starState(of: repository)
                )
            }
            .onAppear {
                // 滚到底自动加载（PRD §4.18 明文：与仓库页同规矩）。
                // 只对最后一行触发，否则每出现一行都会打一次请求。
                if repository.id == lastID {
                    Task { await model.loadMore() }
                }
            }
        }
        .listRowBackground(Theme.Palette.surface)

        footer
    }

    /// 列表底部：加载中 → 转圈；失败 → 重试行（**不遮挡已有内容**，§8.5）。
    /// ⚠️ 它不是"内容" ⇒ 不坐白卡、不画分隔线。
    @ViewBuilder
    private var footer: some View {
        if model.isLoading, !model.items.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if model.error != nil, !model.items.isEmpty {
            Button("加载失败 · 重试") {
                Task { await model.loadMore() }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var centeredBody: some View {
        Group {
            switch model.content {
            case .needsMore:
                continueLoading

            case .empty:
                EmptyBox(title: ProfileCopy.starsEmptyTitle, hint: ProfileCopy.starsEmptyHint,
                        systemImage: "star.slash")

            case let .failure(error):
                PageFailure(error: error) { Task { await model.refresh() } }

            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 空、但服务端还有下一页 —— 这时**不能说「还没有 Star 过任何仓库」**。
    ///
    /// 为什么需要一个显式按钮：空列表没有可滚内容，`.onAppear` 的自动加载永远触发不到。
    /// 而"这一页正好全是私有仓库"（本页按 PRD §4.18 滤掉了它们）是一个真实可达的情形。
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
        MyStarsView(
            loader: environment.repositories,
            starToggle: environment.starToggle,
            toast: environment.toast
        )
    }
    .environment(environment)
}
