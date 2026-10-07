import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 「我的仓库」详情页（PRD §4.4、TECH_SPEC §9.4）。
///
/// 结构：头部大卡（`RepoDetailHero`）+ 四分区切换条（`SectionTabs`）+ 分区内容。
///
/// ## 四个分区里本片只交两段（决策 #50）
///
/// | 分区 | 本片 |
/// |---|---|
/// | ① 代码（默认） | ✅ 面包屑 + 文件树 + README |
/// | ② Issues | ⬜ 切片 7 —— `PendingSection` 占位 |
/// | ③ Pull Requests | ⬜ 切片 7 —— `PendingSection` 占位 |
/// | ④ Commits | ✅ 提交列表（懒加载） |
///
/// 分段条**照原型画满四项**（顺序走 `RepoSection.allCases`，不自己写数组 ——
/// 那样两处顺序会在某次调整里分叉）。
///
/// ## 四条取数各有各的节奏
///
/// 见 `RepoDetailViewModel` 的表格。本视图只做一件事：**给每一条各自画它自己的
/// 骨架 / 内容 / 失败**，不把四条揉成一个 `isLoading`。
///
/// ## ⚠️ 本页是「自己的仓库」，写入口的有无由**路由**决定
///
/// `ReposView.open()` / 首页置顶 / 最近访问按可写性二选一推入本页或 §4.13。
/// 所以这里**不读** `detail.canWrite` 去长出入口 —— 那会让"两种入口能做的事不一致"
/// （铁律 #7：只读态显式传参，不让下层页自行推断）。`RepoDetailViewModel` 也因此
/// 直接按 `canWrite: true` 记一次最近访问。
struct RepoDetailView: View {

    let fullName: String

    @Environment(AppEnvironment.self) private var env

    @State private var model: RepoDetailViewModel

    /// 「现在」只在**进页与刷新时**取一次（同 `ExploreRepoDetailView`）——
    /// 在 `body` 里取 `Date()` 会让"相对时间"变成渲染时机的一部分。
    @State private var now = Date()

    @State private var sheet: RepoSheet?

    /// 本页的弹层路由。
    ///
    /// ⚠️ 用 `Identifiable` 枚举驱动 `.sheet(item:)`，**不用 `isPresented` 布尔量**
    /// （同 `ExploreView`）：切片 8 的「＋ 添加」落地后会多出第二张弹层，
    /// 两个布尔量同时为真时"哪一张盖在上面"就变成了呈现顺序问题，
    /// 而那种 bug 只在特定点击序列下出现。一个枚举天然只有一张。
    private enum RepoSheet: String, Identifiable {
        case branch
        var id: String { rawValue }
    }

    init(
        fullName: String,
        section: RepoSection,
        path: RepoPath,
        detail: LoadRepoDetail,
        treeLoader: LoadRepoTree,
        commits: LoadRepoCommits,
        branches: LoadBranches,
        starToggle: ToggleStar,
        memory: any BranchMemoryStore,
        visits: any RecentVisitStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        _model = State(initialValue: RepoDetailViewModel(
            fullName: fullName,
            section: section,
            path: path,
            detail: detail,
            treeLoader: treeLoader,
            commits: commits,
            branches: branches,
            starToggle: starToggle,
            memory: memory,
            visits: visits,
            toast: toast
        ))
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            now = Date()
            await model.refresh()
            now = Date()
        }
        .task {
            now = Date()
            await model.start()
            // 取完之后再对一次表：网速慢时"2 天前"可能已经跨过了一个整点。
            now = Date()
        }
        .sheet(item: $sheet) { route in
            switch route {
            case .branch:
                BranchSheet(
                    state: model.tree.branchList,
                    currentBranch: model.tree.branch ?? "",
                    isReadOnly: false,
                    onSelect: { picked in
                        sheet = nil
                        Task { await model.switchBranch(to: picked) }
                    },
                    onManage: {
                        sheet = nil
                        env.router.push(.branches(fullName: fullName))
                    },
                    onRetry: { Task { await model.tree.loadBranches() } }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .task { await model.tree.loadBranches() }
            }
        }
    }

    private var name: String {
        (try? RepositoryMapper.splitFullName(fullName))?.name ?? fullName
    }

    // MARK: - 主区域

    @ViewBuilder
    private var content: some View {
        switch model.snapshot.presentation {
        case .skeleton:
            skeleton

        case .content:
            if let snapshot = model.snapshot.value {
                VStack(alignment: .leading, spacing: 0) {
                    RepoDetailHero(
                        detail: snapshot.detail,
                        star: snapshot.star,
                        isTogglingStar: model.isTogglingStar
                    ) {
                        Task { await model.toggleStar() }
                    }

                    sectionTabs
                        .padding(.top, Theme.Spacing.m)

                    sectionBody
                }
            }

        case let .failure(error):
            // 头部拿不到 ⇒ **整页失败**：连分段条都不画。
            // 画着一个能切但每一段都空的分段条，比一句"加载失败"更难懂。
            failureState(error)
        }
    }

    private var sectionTabs: some View {
        SectionTabs(
            // ⚠️ 顺序走 `allCases`，不写数组（`RepoSection` 的说明）。
            items: RepoSection.allCases.map {
                SectionTabs.Item(id: $0.rawValue, title: $0.title)
            },
            selectedID: model.section.rawValue
        ) { picked in
            guard let section = RepoSection(rawValue: picked.id) else { return }
            Task { await model.select(section: section) }
        }
        // 原型 `.prtabs{margin-bottom:12px}`。
        .padding(.bottom, Theme.Spacing.m)
    }

    // MARK: - 分区内容

    @ViewBuilder
    private var sectionBody: some View {
        switch model.section {
        case .code:
            codeSection

        case .issues:
            PendingSection(
                title: RepoSection.issues.title,
                note: "切片 7 落地 · 开放 / 已关闭筛选与新建 Issue（PRD §4.4 分区二）"
            )

        case .pullRequests:
            PendingSection(
                title: RepoSection.pullRequests.title,
                note: "切片 7 落地 · 开放 / 已合并分段与 PR 详情（PRD §4.4 分区三）"
            )

        case .commits:
            commitsSection
        }
    }

    // MARK: - ① 代码

    /// 面包屑 + 文件行 + README。
    ///
    /// ⚠️ 三块本体在 **`RepoTreeSection`（共享件）**里 —— §4.13 第 ⑤ / ⑥ 分区
    /// 渲染的是同一件事（原型这两处的 HTML 结构逐行对应）。
    /// 本页与它只有两处不同，都在下面这两个参数里：
    /// 面包屑右侧多一个「＋ 添加」、点一行的落点是**可写**的那两条路由。
    ///
    /// ⚠️ `title: nil` —— §4.4 的这一块没有小节标题（身份由顶部的分段条表明），
    /// 而 §4.13 有 `文件浏览 · {path}`。
    private var codeSection: some View {
        RepoTreeSection(
            session: model.tree,
            onOpenDirectory: { path in
                env.router.push(.repoDetail(
                    fullName: fullName, section: .code, path: path.raw
                ))
            },
            onOpenFile: { path in
                env.router.push(.fileView(
                    fullName: fullName, path: path.raw, readOnly: false
                ))
            },
            onTapBranch: { sheet = .branch },
            onSelectSegment: { index in navigate(toCrumb: index) }
        ) {
            addFileButton
        }
    }

    /// 「＋ 添加」—— **画出但不可点**（决策 #51：三个出口全属切片 8）。
    ///
    /// 用 `allowsHitTesting(false)` + 一句 hint，**不是** `.disabled`：
    /// 后者会把它变灰、看起来像"暂时不可用"，而这一处是"这一版就不做"。
    /// 形态与原型一致，且不冒充成品。
    ///
    /// ⚠️ 闭包必须是**真的什么都不做** —— `allowsHitTesting(false)` 挡的是触摸，
    /// 读屏的激活动作绕过命中测试（`UserProfileSheet` 的同一处置）。
    private var addFileButton: some View {
        Button(action: {}) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: GitHubIcon.plus)
                    .font(.system(size: 13, weight: .semibold))
                Text(RepoCopy.addFileAction)
            }
            // 原型 `.btn{font-size:13.5px;font-weight:650}` ⇒ `footnote` + semibold。
            .font(Theme.Font.footnote.weight(.semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
            // 原型这一处覆写 `padding:5px 12px`。
            .padding(.vertical, 5)
            .padding(.horizontal, Theme.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.Palette.surfaceSunken)
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(false)
        .accessibilityRemoveTraits(.isButton)
        .accessibilityHint(RepoCopy.addFileUnavailableHint)
    }

    /// 点面包屑的某一层 —— 原型是**推入一层新页面**（`navToSub`），不是原地替换。
    ///
    /// - Parameter index: 面包屑上的下标，**第 0 段是仓库全名**。
    private func navigate(toCrumb index: Int) {
        // index 0 ⇒ 仓库根目录；index k ⇒ 仓库内的第 k-1 层（`RepoPath` 里根是空路径）。
        let target = index == 0 ? RepoPath.root : model.tree.path(upTo: index - 1)
        guard let target, target != model.tree.path else { return }
        env.router.push(.repoDetail(
            fullName: fullName, section: .code, path: target.isRoot ? nil : target.raw
        ))
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
            inlineFailure(error) { Task { await model.loadMoreCommits() } }
        }
    }

    private var commitsList: some View {
        let items = model.commits.items
        let lastID = items.last?.id

        return CardBox(vertical: Theme.Spacing.xs, horizontal: 14) {
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

    // MARK: - 骨架 / 失败

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.m) {
                    SkeletonBar(
                        height: RepoAvatar.standard.diameter,
                        width: RepoAvatar.standard.diameter,
                        cornerRadius: RepoAvatar.standard.cornerRadius
                    )
                    SkeletonBar(height: 17, width: 160)
                    Spacer(minLength: 0)
                }
                SkeletonBar(height: 13)
                SkeletonBar(height: 13, width: 200)
                HStack(spacing: Theme.Spacing.s) {
                    SkeletonBar(height: 44)
                    SkeletonBar(height: 44)
                    SkeletonBar(height: 44)
                }
                .padding(.top, Theme.Spacing.s)
            }
            .padding(Theme.Spacing.l)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))

            SkeletonBar(height: 34)
                .padding(.top, Theme.Spacing.m)

            codeSkeleton
        }
        .accessibilityHidden(true)
    }

    /// 文件树的骨架：一条面包屑 + 若干行。
    private var codeSkeleton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SkeletonBar(height: 32)
            CardBox(vertical: Theme.Spacing.m, horizontal: 14) {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonBar(height: 15, width: 190)
                }
            }
        }
    }

    private var commitsSkeleton: some View {
        CardBox(vertical: Theme.Spacing.m, horizontal: 14) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 10) {
                    SkeletonBar(height: 28, width: 28, cornerRadius: 14)
                    SkeletonBar(height: 13, width: 200)
                }
            }
        }
    }

    /// 首屏失败 —— 必须留一个出口（PRD §1 设计原则 4）。
    private func failureState(_ error: GitHubError) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("加载失败")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            Button("重试") {
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

    /// 分区内的失败（目录 / 提交列表）—— 内容区里的一小块，**不掀翻整页**。
    private func inlineFailure(_ error: GitHubError, retry: @escaping () -> Void) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("这一块加载失败")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
            Button("重试", action: retry)
                .font(Theme.Font.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
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
