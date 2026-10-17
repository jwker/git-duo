import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 搜索页 —— **底部第 4 格 Tab 的根页**（2026-10-16 起；PRD §4.2、TECH_SPEC §9.2）。
///
/// 结构（PRD §4.2）：
/// 0. **顶栏大字标题「搜索」**（居左、放大；`TopBarTitleItem`）；
/// 1. 搜索输入框（系统 `.searchable`）；
/// 2. 范围分段：仓库 / 用户 / 代码 / Issue · PR；
/// 3. 内容区（随输入与范围变化）：空闲态 / 骨架屏 / 结果 / 空态 / 失败。
///
/// ## ⚠️ 2026-10-16：它从推入页变成了 Tab 根页（走查第 85 条）
///
/// 用户要求把底部「我的」那一格让给「搜索」，「我的」改从首页右上角头像进
/// （见 `AppTab` 的说明）。连带的两件事：
///
/// 1. **`Route.search` 已删除** —— 从前首页 / 仓库 / 探索三处右上角的放大镜
///    都推到那一条路由，那三颗放大镜随本次改动一并移除 ⇒ 那条路由没有调用方了。
/// 2. **结果行的跳转不受影响**：本页仍然坐在一条 `NavigationStack(path: $router.search)`
///    里（`MainTabView` 给每个 Tab 各配一条），行里的 `NavigationLink(value:)`
///    照旧由那一条 `navigationDestination(for: Route.self)` 接住。
///
/// ## ⚠️ 顶部两块**固定在滚动区之外**
///
/// 原型把输入框与分段条都放在 `.content`（`overflow-y:auto`）里，整页一起滚。
/// 这里**有意不同**：只有内容区滚动，输入框与分段条钉在顶部。理由是 PRD §4.2 那条
/// "**刷新结果区时保持输入焦点与光标**" —— 结果区每敲一个字就整块重绘，
/// 而输入框若跟着一起滚 / 一起重建，键盘与光标就保不住。
/// 原型是静态演示（它验不出焦点丢失），所以这一处按 PRD 的行为要求做。
///
/// ## ⚠️ 2026-10-16 起内容主干是 **`List`**（NATIVE-MIGRATION P3）
///
/// - 分段条从"`VStack` 里的第一条"改成 `safeAreaInset(edge: .top)`（同 `ReposView`：
///   内容从它下面滚过去，它自己不消失）；
/// - 结果行 / 历史行成为 `List` 的行 ⇒ 行内边距、分隔线、按下高亮、
///   **右侧箭头**全部由系统给（自绘的 `SearchRowBox` 内边距与 hairline、
///   以及那个 `RowChevron` 件随之删除）；
/// - 空态 / 失败态换成官方件。
///
/// ⚠️ 三处**有意保留**的自定观感（属 P5 令牌收尾）：页面底 `Theme.Palette.background`、
///    行底 `Theme.Palette.surface`（`.scrollContentBackground(.hidden)` 让开系统底色）。
///
/// ## ⚠️ 标题是**顶栏大字居左**（走查第 86 条，2026-10-16）
///
/// 与首页 / 仓库 / 探索三页同一档：`TopBarTitleItem`（居左、26pt、与顶栏同高）。
/// ⚠️ 它**不额外占高度** —— 系统搜索框（`.searchable`）画在顶栏**下面**的 drawer 里，
/// 顶栏标题与它不在同一层，所以不会像"内容区大标题"那样吃掉约 50pt。
/// 这也是本页能用同一档标题而其他页必须牺牲吸顶分段条的原因。
struct SearchView: View {

    /// 顶栏那颗自绘大字标题与 `navigationTitle`，两处必须永远同一个字符串
    /// （同 `ReposView` / `ExploreView` 的 `pageTitle`）。
    private static let pageTitle = "搜索"

    @Environment(AppEnvironment.self) private var env

    @State private var model: SearchViewModel

    /// 触发用户资料弹层的那一条（§5.10）。用 `Identifiable` 的行模型驱动
    /// `.sheet(item:)`，不用 `isPresented` 布尔量（同 `ExploreView` 的说明）。
    @State private var sheetUser: UserHit?

    /// 取数与历史存储由**组合根**经 `RouteView` 传下来（5.5 装配）。
    init(loader: LoadSearch, history: any SearchHistoryStore) {
        _model = State(initialValue: SearchViewModel(loader: loader, store: history))
    }

    var body: some View {
        List {
            content
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.background)
        // ⚠️ 2026-10-16 起**输入框不在这里**（NATIVE-MIGRATION P1）：它归
        // `.searchable`（下面那一条），由系统画在导航栏下方 ——
        // 系统给的是那一整套：放大镜、占位文案、清除按钮、取消按钮、
        // 键盘的 `search` 键、以及"搜索框常驻、内容区滚动"这个布局。
        .safeAreaInset(edge: .top, spacing: 0) {
            segmentBar
                // 内容从它下面滚过去 ⇒ 这一层必须不透明。
                .background(Theme.Palette.background)
        }
        .navigationTitle(Self.pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // ⚠️ 顶栏大字标题（居左、放大）—— 见 `TopBarTitleItem`。
            //    `.navigationTitle` 仍保留（返回按钮文案 / 无障碍标题）。
            TopBarTitleItem(text: Self.pageTitle)
        }
        // ⚠️ **系统搜索框**（NATIVE-MIGRATION P1）—— 取代自绘 `SearchField`。
        //    `prompt` 是占位文案；`displayMode: .always` 让它常驻（PRD §4.2 那条
        //    "刷新结果区时保持输入焦点与光标" ⇒ 输入框不能随内容区一起滚/重建，
        //    而系统搜索框本来就在滚动区之外，这条要求由系统满足，不用自己钉）。
        //
        // ⚠️ 2026-10-16 起**不再自动展开搜索框**（走查第 86 条）：进 Tab 直接弹键盘
        //    太吵，用户只想先进来看一眼。因此用不带 `isPresented` 的重载，系统默认不聚焦。
        .searchable(
            text: keywordBinding,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: SearchCopy.fieldPlaceholder
        )
        // 回车 —— 系统那颗键盘上的 `search` 键。
        .onSubmit(of: .search, submit)
        // 搜索词里出现大写与自动纠错都是碍事的（`SearchField` 里的同一条理由：
        // 用户输入 `is:issue` 这种限定符时被纠错成 `is issue` 就白打了）。
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .sheet(item: $sheetUser) { user in
            UserProfileSheet(fallback: user, loader: env.userProfile)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .task {
            await model.loadHistory()
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

    /// 回车：记一笔「最近搜索」并给提示；关键词为空时说「先输入关键词」（PRD §4.2）。
    ///
    /// ## ⚠️ 为什么回车要**主动收键盘**（2026-10-07 目视修正）
    ///
    /// `.submitLabel(.search)` 只改回车键的**字样**，系统不会因此关掉键盘 ——
    /// 第一响应者仍是输入框，于是"搜完了"之后键盘还占着半屏，结果区只剩一条缝。
    /// 用户按下回车是一个**明确的完成动作**，此刻的期望是"让我看结果"。
    ///
    /// ⚠️ 与 PRD §4.2「刷新结果区时保持输入焦点与光标」**不冲突**，两者说的是两件事：
    /// 那条管的是**边打边搜**（每敲一个字结果区整块重绘，输入框的身份必须稳住，
    /// 否则键盘与光标会跳）；而这里是用户**主动提交**，收键盘是他的意图。
    private func submit() {
        // ⚠️ 2026-10-16：这里**不再手工收键盘**（原 `isFieldFocused = false`）。
        //    输入框现在是系统的 `.searchable`，键盘由系统管：点键盘上那颗 `search`
        //    之后系统会自己收起它。手工再收一次没有能绑的对象（也没有 `@FocusState`
        //    指向那个系统输入框）—— 强行做只能走 UIKit 那一层，不值得为它破例。
        //    ⚠️ 真机上若回车后键盘不落，再回来补这一处（属"系统行为待目视"那一类）。
        Task { env.toast.show(await model.submit()) }
    }

    // MARK: - 分段

    private var segmentBar: some View {
        SegmentedBar(
            segments: SearchScope.allCases.map { SegmentedBar.Segment(id: $0.id, title: $0.title) },
            selectedID: model.scope.id
        ) { picked in
            guard let scope = SearchScope(rawValue: picked.id) else { return }
            model.select(scope: scope)
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .idle:
            // ⚠️ 它自己吐两个 `Section`（标题在 header 位）—— 自定义 `View` 的 `body`
            //    是 `Section` 时会被 `List` 正常摊开（宿主机探针实证，见该件说明）。
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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

        case .skeleton:
            SearchResultsSkeleton()
                .listRowBackground(Theme.Palette.surface)

        case .rows:
            results

        case .empty:
            EmptyBox(title: model.emptyTitle, hint: SearchCopy.noResultsHint)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

        case let .failure(error):
            // 首屏失败 —— 必须留一个出口（PRD §1 设计原则 4）。
            PageFailure(error: error) { model.retry() }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    // MARK: - 结果

    @ViewBuilder
    private var results: some View {
        // ⚠️ 「结果不完整」的说明行**不是错误态**：已拿到的条目照常显示，
        //    只是这一页少了些本该在里面的仓库（与探索页同一取向）。
        if let notice = model.notice {
            Text(notice)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }

        resultRows
        footer
    }

    @ViewBuilder
    private var resultRows: some View {
        let items = model.rows

        // ⚠️ `listTitle` 有的话就是这一组的组标题（`{范围名} · {N} 个结果`）——
        //    挂 `Section` 的 header 位（`margins: .none`：组间距由 `List` 给）。
        if let title = model.listTitle {
            Section {
                resultRowList(items)
            } header: {
                SectionHeader(title: title, margins: .none)
            }
        } else {
            resultRowList(items)
        }
    }

    @ViewBuilder
    private func resultRowList(_ items: [SearchRow]) -> some View {
        ForEach(items) { row in
            resultRow(row)
        }
        .listRowBackground(Theme.Palette.surface)
    }

    /// 一行结果 —— **跳转与开弹层都用 `Button` + `.buttonStyle(.plain)`**。
    ///
    /// ⚠️ 不用 `NavigationLink(value:)`：它在 `.insetGrouped` 的 `List` 里
    ///    - 分隔线会被系统默认缩短到 disclosure 左侧（见 `ReposView` 的同款注释）；
    ///    - 再叠加一枚 `simultaneousGesture(TapGesture())` 来"点开先记一笔"时，
    ///      那枚手势会**吞掉跳转**（iOS 上给 `NavigationLink` 加 `TapGesture`
    ///      常让整行点不动）—— 这正是搜索结果"点不开"的根因。
    /// `Button` + `.buttonStyle(.plain)` 同样整行可点、有按下高亮、分隔线全宽，
    /// 且点击闭包里能先 `recordCurrentTerm()` 再 `router.push`（PRD §4.2：
    /// 点开才是"这条搜索有用"的真实信号）。
    @ViewBuilder
    private func resultRow(_ row: SearchRow) -> some View {
        if let route = route(for: row) {
            Button {
                model.recordCurrentTerm()
                env.router.push(route)
            } label: {
                SearchRowView(row: row, now: model.loadedAt)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            // 用户行打开资料弹层 —— 是**动作**不是跳转 ⇒ 同样 `Button` + `.plain`
            //（整行可点 + 按下高亮；不画系统箭头，因为不是推入页）。
            Button {
                model.recordCurrentTerm()
                if case let .user(hit) = row { sheetUser = hit }
            } label: {
                SearchRowView(row: row, now: model.loadedAt)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }

    /// 结果行的去向（PRD §4.2 的「结果行去向」表）；`nil` = 这一种行不跳转（开弹层）。
    ///
    /// ⚠️ **搜索路径给不出可写性**（`GET /search/repositories` 与 `/search/issues`
    ///    都不返回 `permissions`），所以仓库、Issue、PR 三条一律取保守侧（只读页）。
    ///    决策 #43 与 `RepoSummary.canOpenWritableDetail` 把"不知道"的保守侧收在一处，
    ///    **不要**在这里用"全名是不是以我的登录名开头"补判断（PRD §3.13 明确禁止）。
    ///
    /// ⚠️ 决策 #79 之后 `readOnly` **不等于整页只读**：万一搜到的这条 Issue 恰好是我提的，
    ///    详情页仍然给得出「关闭 Issue」。
    private func route(for row: SearchRow) -> Route? {
        switch row {
        case let .repository(hit):
            .exploreRepoDetail(fullName: hit.fullName)

        case .user:
            nil

        case let .code(hit):
            // 原型 `openCodeFile` 推的是**只读**文件页（`ro:1`）。
            .fileView(fullName: hit.repoFullName, path: hit.path, readOnly: true)

        case let .conversation(hit):
            switch hit.kind {
            case .issue:
                .issueDetail(fullName: hit.repoFullName, number: hit.number, readOnly: true)
            case .pullRequest:
                .prDetail(fullName: hit.repoFullName, number: hit.number, readOnly: true)
            }
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
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if model.pageFailed {
            Button("加载失败 · 重试") {
                Task { await model.loadMore() }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if model.hasMore {
            Button(SearchCopy.loadMoreAction) {
                Task { await model.loadMore() }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: - 动作

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
