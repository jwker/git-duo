import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 搜索页（推入页）（PRD §4.2、TECH_SPEC §9.2；切片 5 之 5.4）。
///
/// 结构（PRD §4.2）：
/// 1. 搜索输入框（放大镜 + 输入 + 清除），进入时自动聚焦；
/// 2. 范围分段：仓库 / 用户 / 代码 / Issue · PR；
/// 3. 内容区（随输入与范围变化）：空闲态 / 骨架屏 / 结果 / 空态 / 失败。
///
/// ## ⚠️ 顶部两块**固定在滚动区之外**
///
/// 原型把输入框与分段条都放在 `.content`（`overflow-y:auto`）里，整页一起滚。
/// 这里**有意不同**：只有内容区滚动，输入框与分段条钉在顶部。理由是 PRD §4.2 那条
/// "**刷新结果区时保持输入焦点与光标**" —— 结果区每敲一个字就整块重绘，
/// 而输入框若跟着一起滚 / 一起重建，键盘与光标就保不住。
/// 原型是静态演示（它验不出焦点丢失），所以这一处按 PRD 的行为要求做。
/// （与 `ExploreView` / `ReposView` 把分段条钉在顶部同一安排。）
///
/// ## 三个入口共用本页
///
/// 首页 / 仓库 / 探索三处右上角的放大镜都推到 `.search`（PRD §4.2、§6.3）。
/// 本视图**不认识**它们中的任何一个 —— 路由由 `RouteView` 决定。
struct SearchView: View {

    @Environment(AppEnvironment.self) private var env

    @State private var model: SearchViewModel

    /// 触发用户资料弹层的那一条（§5.10）。用 `Identifiable` 的行模型驱动
    /// `.sheet(item:)`，不用 `isPresented` 布尔量（同 `ExploreView` 的说明）。
    @State private var sheetUser: UserHit?

    @FocusState private var isFieldFocused: Bool

    /// 取数与历史存储由**组合根**经 `RouteView` 传下来（5.5 装配）。
    init(loader: LoadSearch, history: any SearchHistoryStore) {
        _model = State(initialValue: SearchViewModel(loader: loader, store: history))
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: keywordBinding, isFocused: $isFieldFocused, onSubmit: submit)
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.s)

            SegmentedBar(
                segments: SearchScope.allCases.map { SegmentedBar.Segment(id: $0.id, title: $0.title) },
                selectedID: model.scope.id
            ) { picked in
                guard let scope = SearchScope(rawValue: picked.id) else { return }
                model.select(scope: scope)
            }
            .padding(.vertical, Theme.Spacing.s)

            mainArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.background)
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheetUser) { user in
            UserProfileSheet(user: user)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .task {
            // 进入时自动聚焦（PRD §4.2）。⚠️ 放在 `await` **之后**：
            // 与视图出现同一轮里设焦点会被系统丢掉（键盘不弹，而代码看起来没错）。
            await model.loadHistory()
            isFieldFocused = true
        }
    }

    // MARK: - 输入框

    /// ⚠️ 走一个**显式 `Binding`** 而不是 `@Bindable` + `.onChange`：
    /// 后者会让"赋值"与"调度"分成两步（改值触发 `onChange`，`onChange` 再调度），
    /// 而任何一次"只赋值没调度"的新路径都会表现为"输入框里字变了、结果一动不动"。
    /// 这里 `set` 里只有一条路：改值 + 调度。
    private var keywordBinding: Binding<String> {
        Binding(
            get: { model.keyword },
            set: { model.updateKeyword($0) }
        )
    }

    /// 回车：收起键盘 → 记一笔「最近搜索」并给提示；关键词为空时说「先输入关键词」（PRD §4.2）。
    ///
    /// ## ⚠️ 为什么回车要**主动收键盘**（2026-10-07 目视修正）
    ///
    /// `.submitLabel(.search)` 只改回车键的**字样**，系统不会因此关掉键盘 ——
    /// 第一响应者仍是输入框，于是"搜完了"之后键盘还占着半屏，结果区只剩一条缝。
    /// 用户按下回车是一个**明确的完成动作**，此刻的期望是"让我看结果"。
    ///
    /// ⚠️ 与 PRD §4.2「刷新结果区时保持输入焦点与光标」**不冲突**，两者说的是两件事：
    /// 那条管的是**边打边搜**（每敲一个字结果区整块重绘，输入框的身份必须稳住，
    /// 否则键盘与光标会跳）—— 本视图把输入框抽成 `SearchField` 且钉在滚动区之外，
    /// 正是为它；而这里是用户**主动提交**，收键盘是他的意图，不是把焦点弄丢。
    private func submit() {
        // 先收再查：让键盘在请求发出前就开始落下，而不是等结果回来才动。
        isFieldFocused = false
        Task { env.toast.show(await model.submit()) }
    }

    // MARK: - 内容区

    private var mainArea: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .idle:
            SearchIdleSection(
                history: model.history,
                hotKeywords: model.hotKeywords,
                onUse: { model.use(term: $0) },
                onClear: clearHistory
            )

        case .needsKeyword:
            // 代码范围的本地门槛（决策 #48：复用原型已有的这一句，零新增文案）。
            // 它**不是错误**：用户只是还没输入关键词，所以是普通说明行而不是空态框。
            Text(SearchCopy.needsKeyword)
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.top, Theme.Spacing.l)

        case .skeleton:
            SearchResultsSkeleton()
                .padding(.top, Theme.Spacing.s)

        case .rows:
            results

        case .empty:
            EmptyBox(title: model.emptyTitle, hint: SearchCopy.noResultsHint)
                .padding(.top, Theme.Spacing.s)

        case let .failure(error):
            failureState(error)
        }
    }

    // MARK: - 结果

    private var results: some View {
        let rows = model.rows
        let lastIndex = rows.count - 1

        return VStack(alignment: .leading, spacing: 0) {
            if let title = model.listTitle {
                SectionHeader(title: title)
            }

            // ⚠️ `incomplete_results` 的说明行**不是错误态**：已拿到的条目照常显示，
            //    只是这一页少了些本该在里面的仓库（与探索页同一取向）。
            if let notice = model.notice {
                Text(notice)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.bottom, Theme.Spacing.s)
            }

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                SearchRowView(
                    row: row,
                    now: model.loadedAt,
                    showsSeparator: index < lastIndex
                ) {
                    open(row)
                }
            }

            footer
        }
    }

    /// 列表底部：续页在途 → 转圈；续页失败 → 一行错误 + 重试；还有下一页 → 「加载更多」。
    ///
    /// ⚠️ **不自动加载**（决策 #44）：Search 是独立且只有 30 次/分钟的桶
    /// （代码范围 10），而"滚到底"一次能连发好几发 —— 一旦 403，
    /// 四个范围共用的整个搜索页都会瘫掉。
    @ViewBuilder
    private var footer: some View {
        if model.isPaging {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.m)
        } else if model.pageFailed {
            Button("加载失败 · 重试") {
                Task { await model.loadMore() }
            }
            .font(Theme.Font.footnote)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.m)
        } else if model.hasMore {
            Button(SearchCopy.loadMoreAction) {
                Task { await model.loadMore() }
            }
            .font(Theme.Font.bodyStrong)
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
                model.retry()
            }
            .font(Theme.Font.bodyStrong)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .accessibilityElement(children: .combine)
        // 失败原因**只说确定的那一件事**（与 `ReposView` / `ExploreView` 同一口径）。
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

    /// 点开一条结果（PRD §4.2 的「结果行去向」表）。
    ///
    /// ⚠️ **先记一笔再跳** —— 点开才是"这条搜索有用"的真实信号（PRD §4.2）。
    /// `recordCurrentTerm()` 是同步的，在这一刻就把关键词取下来（见它的说明）。
    private func open(_ row: SearchRow) {
        model.recordCurrentTerm()

        switch row {
        case let .repository(hit):
            // ⚠️ 搜索路径**给不出可写性**（`GET /search/repositories` 不返回 `permissions`），
            //    所以这里只有一条路：进只读页。决策 #43 与 `RepoSummary.canOpenWritableDetail`
            //    把"不知道"的保守侧收在一处，**不要**在这里用"全名是不是以我的登录名开头"补判断
            //    （PRD §3.13 明确禁止）。代价：自己的仓库出现在结果里时也进只读页 ——
            //    这是与探索榜同一条有意接受的误差。
            env.router.push(.exploreRepoDetail(fullName: hit.fullName, path: nil))

        case let .user(hit):
            sheetUser = hit

        case let .code(hit):
            // 原型 `openCodeFile` 推的是**只读**文件页（`ro:1`）。
            env.router.push(.fileView(fullName: hit.repoFullName, path: hit.path, readOnly: true))

        case let .conversation(hit):
            switch hit.kind {
            case .issue:
                env.router.push(.issueDetail(fullName: hit.repoFullName, number: hit.number))
            case .pullRequest:
                // `readOnly: true` —— 同一个理由：搜索给不出可写性，取保守侧。
                // （PR 详情页本身属切片 7，届时它自己会决定要不要按这个旗标收口。）
                env.router.push(.prDetail(
                    fullName: hit.repoFullName,
                    number: hit.number,
                    readOnly: true
                ))
            }
        }
    }

    /// 清空「最近搜索」+ 提示（**不弹确认层** —— PRD §4.2 明写与「最近访问」有意不同）。
    private func clearHistory() {
        Task {
            await model.clearHistory()
            env.toast.show(SearchCopy.historyClearedToast)
        }
    }
}

#Preview {
    @Previewable @State var environment = AppEnvironment()

    NavigationStack {
        SearchView(loader: environment.search, history: environment.searchHistory)
    }
    .environment(environment)
}
