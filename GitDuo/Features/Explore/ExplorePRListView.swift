import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 探索 PR 列表（推入页）（PRD §4.15、决策 #39、TECH_SPEC §4.6.3）。
///
/// 结构：说明行 `{仓库}` → PR 卡片列表 → 页脚。
///
/// ⚠️ 卡片本体**切片 7 起在 `Features/Repo/Components/PullCard.swift`**（决策 #61）：
/// §4.4 分区三也要画同一张卡片，理由同上。本页**不给 `now`** ⇒
/// 第三行（`{作者} 更新于 {时间}`）不渲染 —— 这一页的卡片只有两行。
///
/// ## 与 `ExploreIssueListView` 的两处有意不同
///
/// 1. **列开放 + 已合并**（决策 #39）。与"Issues 只列开放式"**有意不对称**：
///    PR 的「已合并」是一个有价值的**结局**，而 Issue 的「已关闭」只说明没人做了；
///    且本页的入口副标题就是「查看他人贡献」，已合入的 PR 正是贡献最直接的证据。
///    ⚠️ 已关闭但未合并的**不列** —— 过滤在 `LoadRepoPulls` 里。
/// 2. **说明行没有计数**，只有仓库全名（原型亦然）。本列表按 `state=all` 取，
///    没有一个"一句话说得清的"数：说"共 N 个 PR"会把用户看不到的那些也算进去。
///    所以这一行的显示**不依赖任何计数** ⇒ 它常驻，不像 Issues 那边要等数据到手
///    （那边 `开放 0 个` 在骨架态会误导）。
struct ExplorePRListView: View {

    let fullName: String

    @Environment(AppEnvironment.self) private var env

    @State private var model: RepoSubListViewModel<PullRow>

    /// 取数依赖由**组合根**经 `RouteView` 传下来（`env.repoPulls`）。
    init(fullName: String, pulls: LoadRepoPulls) {
        self.fullName = fullName
        // ⚠️ 闭包形参叫 `name` 而不是 `fullName` —— 避免遮蔽 `self.fullName`（同 Issues 页）。
        _model = State(initialValue: RepoSubListViewModel { name, cursor in
            // 探索页取 `.all` 再滤掉「关闭但未合并」（§4.15、决策 #39）——
            // 它要的是"开放 + 已合并"，而服务端**没有**这一个筛选项。
            // `state` 现在必须显式给：仓库详情 PR 段两档分别是 `.open` / `.closed`（决策 #61）。
            try await pulls.load(fullName: name, state: .all, cursor: cursor)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summaryLine

                content

                footer
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        .navigationTitle(ExploreRepoCopy.pullsRowTitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
        .task { await model.start(fullName: fullName) }
    }

    // MARK: - 说明行

    /// 常驻（原型亦然）—— 它只有仓库全名，任何状态下都不会误导。
    private var summaryLine: some View {
        Text(PullListIndicator.summaryLine(fullName: fullName))
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
            EmptyBox(
                title: PullListIndicator.emptyTitle,
                hint: PullListIndicator.emptyHint,
                systemImage: StateIcon.pullRequestOpen
            )

        case let .failure(error):
            failureState(error)
        }
    }

    private var rows: some View {
        let items = model.rows
        let lastID = items.last?.id

        return VStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, row in
                Button {
                    // ⚠️ `readOnly: true` **显式传**（铁律 #7）：本页只可能来自探索入口，
                    //    而"只读还是可写"由路由在进入前定下，不让下层页自己推断仓库归属。
                    env.router.push(
                        .prDetail(fullName: fullName, number: row.number, readOnly: true)
                    )
                } label: {
                    // 方案 D：行间靠顶上那条内嵌 hairline 分隔 —— 首行不画。
                    PullCard(row: row)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if row.id == lastID {
                        Task { await model.loadMore() }
                    }
                }
            }
        }
    }

    /// 列表底部：分页在途 → 转圈；分页失败 → 重试行；最后是页脚。
    /// 整块只在有内容时渲染 —— 理由同 `ExploreIssueListView`（PRD §4.15）。
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

    private var footerNote: some View {
        Text(PullListIndicator.footer)
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
        ExplorePRListView(fullName: "kuda/ui-craft", pulls: environment.repoPulls)
    }
    .environment(environment)
}
