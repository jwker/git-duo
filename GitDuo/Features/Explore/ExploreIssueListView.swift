import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 探索 Issues 列表（推入页）（PRD §4.14、决策 #38、TECH_SPEC §4.6.3）。
///
/// 结构：说明行 `{仓库} · 开放 {N} 个` → Issue 卡片列表 → 页脚。
///
/// ⚠️ 卡片本体**切片 7 起在 `Features/Repo/Components/IssueCard.swift`**（决策 #61）：
/// §4.4 分区二也要画同一张卡片，两处各留一份必然分叉 ⇒ 搬到接收方目录、两处共用。
/// 本页传默认参数（`showsLabels: false`，不画标签行）—— 这一页的卡片只有两行。
///
/// ## 三处与"看起来更顺手"的做法相反的地方
///
/// 1. **只列开放式**（决策 #38）。说明行写的就是"开放 {N} 个"、页脚写的是
///    "关闭 Issue 需维护者权限" —— 混入已关闭的会让标题与内容对不上。
///    ⚠️ 且 `GET /issues` 的返回里**混着 PR**，过滤在 `LoadRepoIssues` 里
///    （不是在这里，也不是在数据层 —— 理由见那个类型的说明）。
/// 2. **`{N}` 是已加载的非 PR 条目数**，不是接口里那个"开放 Issue 数"字段
///    （它把 PR 也算进去，会比屏幕上实际看到的条数多，而"数字对不上"
///    会被读成"这个 App 数不准"）。
/// 3. **空态时说明行留着、页脚去掉**（2026-10-07 拍板，PRD §4.14）：
///    说明行交代的是"确实一个开放的都没有"（写作 `开放 0 个`），
///    页脚讲的是"能对列表做什么"、空列表时无所指。
struct ExploreIssueListView: View {

    let fullName: String

    @Environment(AppEnvironment.self) private var env

    @State private var model: RepoSubListViewModel<IssueRow>

    /// 「现在」在**进页与取完数之后**各取一次，不在 `body` 里取 ——
    /// 否则每次重绘都会拿到略微不同的值，相对时间就成了渲染时机的一部分。
    @State private var now = Date()

    /// 取数依赖由**组合根**经 `RouteView` 传下来（`env.repoIssues`）。
    init(fullName: String, issues: LoadRepoIssues) {
        self.fullName = fullName
        // ⚠️ 闭包形参刻意叫 `name` 而不是 `fullName`：叫 `fullName` 会**遮蔽**
        //    外面的 `self.fullName`，而两者恰好同值时，遮蔽出的错会一直潜伏到
        //    某天有人改了其中一个（这个坑今天在两个包里各踩过一次）。
        _model = State(initialValue: RepoSubListViewModel { name, cursor in
            // 探索页固定取「开放」那一档（决策 #38）—— 现在 `state` 是显式的，
            // 因为同一个用例也服务仓库详情 Issues 段（那一页两档都要，决策 #61）。
            try await issues.load(fullName: name, state: .open, cursor: cursor)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showsSummaryLine {
                    summaryLine
                }

                content

                footer
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        .navigationTitle(ExploreRepoCopy.issuesRowTitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
        .task {
            now = Date()
            await model.start(fullName: fullName)
            now = Date()
        }
    }

    // MARK: - 说明行

    /// ⚠️ **只在真的拿到过数据之后**才出现。
    ///
    /// 骨架态与失败态下 `loadedCount` 都是 0，而 `开放 0 个` 会被读成
    /// "这个仓库没有开放的 Issue" —— 与"还没加载出来"是两件完全不同的事
    /// （§8.5 末条：**加载中 ≠ 无数据**）。空态与「还有下一页」都**要**显示：
    /// 前者正是"确实没有"，后者的 `0+` 是下界（不是一个确数）。
    private var showsSummaryLine: Bool {
        switch model.content {
        case .items, .empty, .needsMore: true
        case .skeleton, .failure: false
        }
    }

    private var summaryLine: some View {
        Text(
            OpenIssueIndicator.summaryLine(
                fullName: fullName,
                loadedCount: model.loadedCount,
                hasMore: model.hasMore
            )
        )
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.Palette.textTertiary)
        .padding(.bottom, Theme.Spacing.m)
    }

    // MARK: - 主区域

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .skeleton:
            ExploreSubListSkeleton()

        case .items:
            rows

        case .needsMore, .empty:
            // 「还有下一页但这一页被滤空了」与「确实一条都没有」共用同一个空态框，
            // 但此时**说明行会写成 `开放 0+ 个`**（下界），所以两者在屏幕上仍可分辨。
            EmptyBox(
                title: OpenIssueIndicator.emptyTitle,
                hint: OpenIssueIndicator.emptyHint
            )

        case let .failure(error):
            failureState(error)
        }
    }

    private var rows: some View {
        // 过滤 / 查找只算一次：在 `onAppear` 里逐行判断"是不是最后一行"是 O(n²)。
        let items = model.rows
        let lastID = items.last?.id

        return VStack(spacing: Theme.Spacing.s) {
            ForEach(items) { row in
                Button {
                    env.router.push(.issueDetail(fullName: fullName, number: row.number))
                } label: {
                    IssueCard(row: row, now: now)
                }
                .buttonStyle(.plain)
                .onAppear {
                    // 只有最后一行触发，否则每出现一行就打一次请求。
                    if row.id == lastID {
                        Task { await model.loadMore() }
                    }
                }
            }
        }
    }

    /// 列表底部：分页在途 → 转圈；分页失败 → 重试行；最后是页脚。
    ///
    /// ⚠️ 整块**只在有内容时**渲染（`rows` 非空）：
    /// - 分页的转圈 / 重试行在没有内容时无处可依附（首屏失败走 `failureState`）；
    /// - 页脚讲的是"能对这个列表做什么"，空列表时是废话（PRD §4.14）。
    @ViewBuilder
    private var footer: some View {
        if !model.rows.isEmpty {
            if model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.m)
            } else if model.error != nil {
                Button("加载失败 · 重试") {
                    Task { await model.loadMore() }
                }
                .font(Theme.Font.footnote)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.m)
            }

            footerNote
        }
    }

    /// 页脚本身 —— 与分页状态**无关**，所以拆开：上面那个 `footer` 管"加载到哪了"，
    /// 这一句管"在这个列表里能做什么"。合成一块会让"失败了就不显示页脚"这种
    /// 副作用悄悄出现。
    private var footerNote: some View {
        Text(OpenIssueIndicator.footer)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.l)
    }

    /// 首屏失败 —— 必须留一个出口（PRD §1 设计原则 4）。
    private func failureState(_ error: GitHubError) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(ExploreRepoCopy.failureTitle)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            Button(ExploreRepoCopy.retry) {
                Task { await model.refresh() }
            }
            .font(Theme.Font.bodyStrong)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .accessibilityElement(children: .combine)
        // 失败原因**只说确定的那一件事**：404 与无权限被 GitHub 混同（§4.3），
        // 不得替用户断定是"仓库不存在"还是"你没权限"。
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
}

#Preview {
    @Previewable @State var environment = AppEnvironment()
    NavigationStack {
        ExploreIssueListView(fullName: "kuda/ui-craft", issues: environment.repoIssues)
    }
    .environment(environment)
}
