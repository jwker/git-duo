import GitHubAPI
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 「我的 Pull Request / 我的 Issue」页（PRD §4.21、决策 #73 / #44）。
///
/// 结构：`inline` 标题（与「我的」页那两条菜单逐字相同）· 说明行 `{N} 个结果` ·
/// 结果列表 · 底部「加载更多」。
///
/// ## ⚠️ 这一屏原型里没有
///
/// 原型 `12-me.js` 的两个菜单项是**直接跳详情**的
/// （`push('prDetail',{n:57,…})` —— 一个硬编码的演示值）。真实数据下必须先有一张列表
/// （决策 #73），所以这一页**只能拿 PRD §4.21 逐条对**（`REVIEW-CHECKLIST` 第 145–148 条）。
///
/// ## ⚠️ 结果行**复用搜索页那一行**，不另做一版
///
/// PRD §4.21 第 3 条逐字：「与搜索页的 Issue / PR 结果行是同一行，不另做一版
/// （同一个 UI 两处定义必然分叉）」。所以这里直接用 `ConversationResultRow`
/// + 领域模型 `ConversationHit`，本件一个字都不重画。
///
/// ## 两屏同构，只有三处不同
///
/// 标题 · 空态两行 · 查询口径 —— 三者都由 `kind` 决定，全部取自领域层
/// （`MyConversationsCopy` / `MyConversationsQuery`）。本件不认识任何一个字。
struct MyConversationsView: View {

    @Environment(AppEnvironment.self) private var env

    @State private var model: MyConversationsViewModel

    /// 取数由**组合根**经 `RouteView` 传下来（本视图不构造客户端）。
    init(kind: ConversationKind, loader: LoadMyConversations) {
        _model = State(initialValue: MyConversationsViewModel(kind: kind, loader: loader))
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
        .task { await model.loadIfNeeded() }
    }

    // MARK: - 主区域

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .skeleton:
            // 形状与结果行同族（都是 `.sr-item`）⇒ 直接用搜索页那一份骨架，
            // 不另写一版（同"结果行复用"的理由）。
            SearchResultsSkeleton()

        case .rows:
            results

        case .empty:
            EmptyBox(title: model.emptyTitle, hint: model.emptyHint)
                .padding(.top, Theme.Spacing.s)

        case let .failure(error):
            PageFailure(error: error) {
                Task { await model.retry() }
            }
        }
    }

    private var results: some View {
        let rows = model.rows

        return VStack(alignment: .leading, spacing: 0) {
            if let title = model.listTitle {
                SectionHeader(title: title)
            }

            // ⚠️ `incomplete_results` 的说明行**不是错误态**：已拿到的条目照常显示，
            //    只是这一页少了些本该在里面的东西（与搜索页、探索页同一取向）。
            if let notice = model.notice {
                Text(notice)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.bottom, Theme.Spacing.s)
            }

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, hit in
                ConversationResultRow(
                    hit: hit,
                    // ⚠️ 「现在」取的是**结果到达那一刻**（`model.loadedAt`），
                    //    不在 `body` 里取 `Date()`（见那个属性的说明）。
                    now: model.loadedAt,
                    // 方案 D：分隔线是顶上那条内嵌 hairline —— 首行不画。
                    showsSeparator: index > 0
                ) {
                    open(hit)
                }
            }

            footer
        }
    }

    /// 列表底部。四种样子互斥，顺序即优先级：
    /// 续页在途 → 转圈；失败 → 一行重试；还有下一页 → 「加载更多」；否则什么都没有。
    ///
    /// ⚠️ **不自动加载**（决策 #44）：Search 是独立且只有 30 次/分钟的桶，
    /// "滚到底"一次能连发好几发 —— 一旦 403，四个范围共用的整个搜索页都会瘫掉。
    @ViewBuilder
    private var footer: some View {
        if model.isPaging {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.m)
        } else if model.showsRetryRow {
            Button("加载失败 · 重试") {
                Task { await model.retryFromFooter() }
            }
            .font(Theme.Font.footnote)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.m)
        } else if model.hasMore {
            Button(MyConversationsCopy.loadMoreAction) {
                Task { await model.loadMore() }
            }
            .font(Theme.Font.bodyStrong)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.m)
        }
    }

    // MARK: - 动作

    /// 点开一行（PRD §4.21：PR 进 PR 详情、Issue 进 Issue 详情）。
    ///
    /// ⚠️ PR 那一支传 `readOnly: true` —— 与搜索页同一条理由：
    /// `GET /search/issues` **给不出可写性**（它不返回 `permissions`），
    /// 而这一页的 PR 可能落在任何一个仓库里（自己的、协作的、别人的）⇒
    /// 取保守侧。代价如实说：自己的 PR 点进去也是只读的（没有合并 / 关闭那几颗按钮）。
    /// 铁律 #7：不在这里用"仓库全名是不是以我的登录名开头"补判断。
    ///
    /// ⚠️ **Issue 那一边现在也走同一条**（2026-10-09，决策 **#79**）：`Route.issueDetail`
    /// 同样带 `readOnly`、同样取保守侧。它此前说的是"本页不做关闭 / 重开"（决策 #62）——
    /// 那条已被用户的走查报回推翻。
    ///
    /// ## ⚠️⚠️ 但 Issue 这一边有一处**关键的不同**：保守侧在这里几乎不起作用
    ///
    /// 本页 Issue 列表的口径是 `author:@me` ⇒ **每一条都是我提的**，而 GitHub 的规则是
    /// *"Anyone can close an issue they opened"* ⇒ 详情页会把 `readOnly: true` 这个
    /// 保守假设**抵消掉**，于是这里几乎每一条**都能操作**（哪怕它落在别人的仓库里）。
    /// ⚠️ 这正是用户报回那条的修法：若照 PR 那样把 `readOnly` 理解成"整页只读"，
    /// 这一页就会**继续改不了状态**。
    private func open(_ hit: ConversationHit) {
        switch model.kind {
        case .issue:
            env.router.push(.issueDetail(fullName: hit.repoFullName, number: hit.number, readOnly: true))
        case .pullRequest:
            env.router.push(.prDetail(
                fullName: hit.repoFullName,
                number: hit.number,
                readOnly: true
            ))
        }
    }
}

#Preview {
    @Previewable @State var environment = AppEnvironment()

    NavigationStack {
        MyConversationsView(kind: .pullRequest, loader: environment.conversations)
    }
    .environment(environment)
}
