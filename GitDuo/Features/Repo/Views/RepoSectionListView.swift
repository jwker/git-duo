import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// **列表分区页**（Issues / Pull Requests / Commits，2026-10-14 新增 —— 走查第 63 条）。
///
/// ## 它是从 `RepoDetailView` 的 `sectionBody` 里**搬出来**的
///
/// 用户要求把仓库页改成枢纽（大卡 + 四行入口），于是"一页四个分区"里的三个
/// 各自成一页。这一页就是那三个之一，`section` 决定是哪一个。
///
/// ⚠️ 三页**同构**（导航标题 + 一份列表 + 各自的档位与游标），只有一个 `section` 之差
/// —— 与 `MyConversationsView(kind:)` 同一条处置：做成三个视图就要把这一份写三遍，
/// 而那三遍**必然**在某次改动里分叉。本页里剩下的 `switch` 全是"三种内容各自的画法"，
/// 没有一条是"三种壳子的差异"。
///
/// ⚠️ `sectionBody` 原来还有一个 `.code` 分支（内嵌目录树）—— 那个分支连同它的
/// `codeSection` / CRUMB / 面包屑菜单一起搬去了 `RepoCodeView`，不在这里。
///
/// ## ⚠️ 它**没有下拉刷新**
///
/// 原来整页有 `.refreshable`，而它刷的是**头部**（连带"目录与 Commits 联动"那些事）
/// —— 那两样现在都不在这一页上。列表自己有「加载更多」与失败重试两个出口，
/// 给这一页加一个什么都不刷的下拉动作只会让人以为"刷新没生效"。
/// 若将来要"下拉重取第一页"，那是**新口径**（会重置用户已经翻过的页），得单独定。
struct RepoSectionListView: View {

    let fullName: String

    /// 这一页是哪一个分区 —— 由路由定，进页后不变。
    let section: RepoSection

    let commits: LoadRepoCommits
    let issues: LoadRepoIssues
    let pulls: LoadRepoPulls
    let detail: LoadRepoDetail
    let memory: any BranchMemoryStore

    @Environment(AppEnvironment.self) private var env

    @State private var model: RepoSectionViewModel

    /// 「现在」只在**进页时**取一次（同 `RepoDetailView`）——
    /// 在 `body` 里取 `Date()` 会让"相对时间"变成渲染时机的一部分。
    @State private var now = Date()

    /// 本页唯一的弹层：Issues 段的标签筛选（其余两段没有弹层）。
    @State private var showsLabelPicker = false

    init(
        fullName: String,
        section: RepoSection,
        commits: LoadRepoCommits,
        issues: LoadRepoIssues,
        pulls: LoadRepoPulls,
        detail: LoadRepoDetail,
        memory: any BranchMemoryStore
    ) {
        self.fullName = fullName
        self.section = section
        self.commits = commits
        self.issues = issues
        self.pulls = pulls
        self.detail = detail
        self.memory = memory
        _model = State(initialValue: RepoSectionViewModel(
            fullName: fullName,
            section: section,
            commits: commits,
            issues: issues,
            pulls: pulls,
            detail: detail,
            memory: memory
        ))
    }

    var body: some View {
        ScrollView {
            sectionBody
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        // ⚠️ 标题就是分区名（「Issues」/「Pull Requests」/「Commits」）——
        //    仓库名在返回键上（上一页的标题），不必在这里再写一遍。
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            now = Date()
            await model.start()
            now = Date()
        }
        .sheet(isPresented: $showsLabelPicker) {
            LabelPickerSheet(
                catalog: env.labelCatalog,
                fullName: fullName,
                // 选中集合归本页（`model.issueLabels`）—— 弹层只读它、只通知变化。
                selected: model.issueLabels,
                onToggle: { label in
                    // 点一行是**两向**的：已选则取消、未选则选中。
                    Task {
                        if model.issueLabels.contains(where: { $0.name == label.name }) {
                            await model.removeIssueLabel(label)
                        } else {
                            await model.selectIssueLabel(label)
                        }
                    }
                },
                onCreation: { result in
                    // ⚠️ 走到这里的**只有关弹层的那两条**（重名 / 建成）—— 决策 #77：
                    //    空名那一档弹层不关，话由弹层自己画在按钮上方，**不到这里来**。
                    //    §7 的两句逐字在领域层，这里只负责挑哪一句。
                    switch result {
                    case .emptyName:
                        // 到不了（弹层自己说）。见 `NewIssueView` 那一处的同一条注释。
                        break
                    case let .alreadyExists(label):
                        env.toast.show(IssueCopy.duplicateLabelToast)
                        // 顺手选中已经是筛选项的那颗（"已存在"的语义就是"给你用上它"）。
                        Task { await model.selectIssueLabel(label) }
                    case let .created(label):
                        env.toast.show(IssueCopy.labelCreatedToast(name: label.name))
                        Task { await model.selectIssueLabel(label) }
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 三种内容

    @ViewBuilder
    private var sectionBody: some View {
        switch section {
        case .issues:
            RepoIssuesSection(
                list: model.currentIssues,
                segment: model.issueSegment,
                openTitle: model.openIssuesTitle,
                closedTitle: model.closedIssuesTitle,
                selectedLabels: model.issueLabels,
                now: now,
                onSelectSegment: { segment in
                    Task { await model.selectIssueSegment(segment) }
                },
                onTapFilter: { showsLabelPicker = true },
                onRemoveLabel: { label in
                    Task { await model.removeIssueLabel(label) }
                },
                onOpen: { number in
                    // ⚠️ `readOnly: false` **显式传**（铁律 #7）—— 与下面 PR 那一处同一条：
                    //    本页只从"自己的仓库"首页进得来（本页的可写性在别处也是这么写的）。
                    env.router.push(.issueDetail(fullName: fullName, number: number, readOnly: false))
                },
                onCreate: {
                    env.router.push(.newIssue(fullName: fullName))
                }
            )

        case .pullRequests:
            RepoPullsSection(
                list: model.currentPulls,
                segment: model.pullSegment,
                openTitle: model.openPullsTitle,
                mergedTitle: model.mergedPullsTitle,
                now: now,
                onSelectSegment: { segment in
                    Task { await model.selectPullSegment(segment) }
                },
                onOpen: { number in
                    // ⚠️ `readOnly: false` **显式传**（铁律 #7）：本页是"自己的仓库"，
                    //    那个判定在路由进入本页之前就做完了，本页不推断仓库归属。
                    env.router.push(
                        .prDetail(fullName: fullName, number: number, readOnly: false)
                    )
                }
            )

        case .commits:
            commitsSection
        }
    }

    // MARK: - ④ Commits

    @ViewBuilder
    private var commitsSection: some View {
        switch model.commits.content() {
        case .skeleton:
            commitsSkeleton

        case .items:
            commitsList

        case .needsMore:
            continueLoading

        case .empty:
            EmptyBox(title: CommitCopy.emptyTitle, hint: CommitCopy.emptyHint)

        case let .failure(error):
            // 切片 7 起这块是**共享件**（Issues / PR 两段也用同一个失败块）——
            // 抄三份的下场是那句「这一块加载失败」只会在其中一处被改。
            SectionFailure(error: error) { Task { await model.loadMoreCommits() } }
        }
    }

    private var commitsList: some View {
        let items = model.commits.items
        let lastID = items.last?.id

        return CardBox() {
            // ⚠️ `LazyVStack`（不是 `VStack`）：滚到底自动加载靠的就是
            //    "最后一行真正出现时才触发"，而 `VStack` 会把所有行一次建出来 ⇒
            //    一进这一页就把后面每一页都请求一遍。
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, commit in
                    RepoCommitRow(
                        commit: commit,
                        now: now,
                        showsSeparator: index < items.count - 1 || model.commits.canLoadMore
                    ) {
                        env.router.push(.commitDetail(
                            fullName: fullName, sha: commit.sha, readOnly: false
                        ))
                    }
                    .onAppear {
                        // §4.4：普通列表**滚到底自动加载**（只有搜索用「加载更多」按钮）。
                        // 只对最后一行触发，否则每出现一行都打一次请求。
                        if commit.id == lastID {
                            Task { await model.loadMoreCommits() }
                        }
                    }
                }

                commitsFooter
            }
        }
    }

    /// 列表底部：在途转圈 / 失败重试行。**不遮挡已有内容**（§8.5）。
    @ViewBuilder
    private var commitsFooter: some View {
        if model.commits.isLoading, !model.commits.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.m)
        } else if model.commits.error != nil, !model.commits.items.isEmpty {
            Button("加载失败 · 重试") {
                Task { await model.loadMoreCommits() }
            }
            .font(Theme.Font.footnote)
            .padding(.vertical, Theme.Spacing.m)
            .frame(maxWidth: .infinity)
        }
    }

    /// 空、但服务端还有下一页 —— 此时**不能说「还没有提交」**。
    ///
    /// 为什么需要一个显式按钮：空列表没有可滚内容，`.onAppear` 的自动加载永远触发不到。
    private var continueLoading: some View {
        VStack(spacing: Theme.Spacing.m) {
            if model.commits.isLoading {
                ProgressView()
            } else {
                Button("继续加载") {
                    Task { await model.loadMoreCommits() }
                }
                .font(Theme.Font.body)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }

    /// 提交段的骨架。
    ///
    /// ⚠️ **容器参数与行内边距必须与上面那个真实的 `commitsList` 对齐**
    /// （`CardBox()` + `RepoCommitRow` 的 `padding:11px 4px`）。
    /// 2026-10-09 切片 10 修：此前写的是 `Theme.Spacing.m`（12）且没有行内边距 ⇒
    /// 数据到达时**整块上移 8pt**，随后每一行再各挪一次。
    private var commitsSkeleton: some View {
        CardBox() {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 10) {
                    SkeletonBar(height: 28, width: 28, cornerRadius: 14)
                    SkeletonBar(height: 13, width: 200)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 11)
                .padding(.horizontal, Theme.Spacing.xs)
            }
        }
    }
}
