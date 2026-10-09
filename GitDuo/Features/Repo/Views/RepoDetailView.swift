import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 「我的仓库」详情页（PRD §4.4、TECH_SPEC §9.4）。
///
/// 结构：头部大卡（`RepoDetailHero`）+ 四分区切换条（`SectionTabs`）+ 分区内容。
///
/// ## 四个分区
///
/// | 分区 | 落在哪 |
/// |---|---|
/// | ① 代码（默认） | ✅ 面包屑 + 文件树 + README（`RepoTreeSection`，与 §4.13 共用） |
/// | ② Issues | ✅ 切片 7 —— `RepoIssuesSection`（两档 + 标签筛选 + 新建入口） |
/// | ③ Pull Requests | ✅ 切片 7 —— `RepoPullsSection`（两档） |
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

    /// §5.8 两个上传出口的取件与预处理（切片 8.7 / 决策 #71）—— 交给 `AddFileSheet`。
    ///
    /// ⚠️ 本页自己**不用它**，只是**过一手**：弹层是这一页呈现的，而依赖一律由
    /// `RouteView` 从组合根带下来（页面不 new 用例 —— `AGENTS.md §3` 的铁律）。
    let intake: UploadIntake

    @Environment(AppEnvironment.self) private var env

    @State private var model: RepoDetailViewModel

    /// 「现在」只在**进页与刷新时**取一次（同 `ExploreRepoDetailView`）——
    /// 在 `body` 里取 `Date()` 会让"相对时间"变成渲染时机的一部分。
    @State private var now = Date()

    @State private var sheet: RepoSheet?

    /// 本页的弹层路由。
    ///
    /// ⚠️ 用 `Identifiable` 枚举驱动 `.sheet(item:)`，**不用 `isPresented` 布尔量**
    /// （同 `ExploreView`）：本页有四张弹层，两个布尔量同时为真时"哪一张盖在上面"
    /// 就变成了呈现顺序问题，而那种 bug 只在特定点击序列下出现。一个枚举天然只有一张。
    ///
    /// ⚠️ 从 8.4 起它**带上了关联值**（`.upload` 要拿着选中的字节）⇒ 不再能靠
    /// `String` 原始值当 `id`，改成手写（与 `BranchesViewModel.SheetRoute` 同形）。
    private enum RepoSheet: Identifiable {
        case branch
        /// §4.4 分区二「筛选」—— 与 §4.10 新建 Issue 页**同一个**弹层（决策 #56）。
        case labelPicker
        /// §5.8 添加文件（三行出口）。
        case addFile
        /// §5.8 后两个出口选中之后：§5.9 的提交弹层，落点是**仓库根 + 那个文件名**。
        case upload(UploadDraft)

        var id: String {
            switch self {
            case .branch: "branch"
            case .labelPicker: "labelPicker"
            case .addFile: "addFile"
            case let .upload(draft): "upload-\(draft.fileName)-\(draft.data.count)"
            }
        }
    }

    init(
        fullName: String,
        section: RepoSection,
        path: RepoPath,
        detail: LoadRepoDetail,
        treeLoader: LoadRepoTree,
        commits: LoadRepoCommits,
        branches: LoadBranches,
        issues: LoadRepoIssues,
        pulls: LoadRepoPulls,
        starToggle: ToggleStar,
        // ⚠️ 决策 #80 那一档判定的来源（"这个仓库写不写得动"）。与 `intake` 一样是**过一手**：
        //    传的必须是组合根里那**同一个**缓存 —— 另 new 一个的代价是每次进页白问一次
        //    `GET /user/installations`，而且它拿不到组合根预热过的那份结果。
        starScope: StarWriteScopeCache,
        saver: SaveFile,
        intake: UploadIntake,
        memory: any BranchMemoryStore,
        visits: any RecentVisitStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.intake = intake
        _model = State(initialValue: RepoDetailViewModel(
            fullName: fullName,
            section: section,
            path: path,
            detail: detail,
            treeLoader: treeLoader,
            commits: commits,
            branches: branches,
            issues: issues,
            pulls: pulls,
            starToggle: starToggle,
            starScope: starScope,
            saver: saver,
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

            case .labelPicker:
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

            case .addFile:
                // §5.8。⚠️ 三个出口**都是"换成另一张"**（编辑器 / 提交弹层），
                //    所以这里每一处都先把 `sheet` 置成下一个值 ——
                //    直接 `dismiss()` 会先关掉这张、再开下一张，中间那一帧是空屏。
                AddFileSheet(
                    branch: model.tree.branch ?? "",
                    intake: intake,
                    onNewFile: {
                        sheet = nil
                        // 新建模式的路径由**编辑器里的输入框**定（§4.6），
                        // 所以这里不带路径、不带文件名。
                        env.router.push(.editor(
                            fullName: fullName, path: nil, mode: .create
                        ))
                    },
                    onPicked: { draft in
                        // 选中那一刻字节已经在手上（`UploadDraft` 的说明）——
                        // 这里只把它交给下一张弹层。
                        sheet = .upload(draft)
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)

            case let .upload(draft):
                // §5.8 的后两个出口 → §5.9 的提交弹层（**同一个** `CommitSheet`，
                // 与编辑器那条路共用；差别只在标题来源与多一行只读的落点）。
                uploadCommitSheet(draft)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var name: String {
        (try? RepositoryMapper.splitFullName(fullName))?.name ?? fullName
    }

    // MARK: - §5.8 两个上传出口的提交弹层

    /// 上传出口的「提交更改」（§5.8 → §5.9）。
    ///
    /// ⚠️ 用的是**与编辑器同一个** `CommitSheet`。差别只有三处：
    /// 标题来源（`draft.source`）、多一行只读的「将写入 `{路径}`」、
    /// 以及这一条路**恒为新建**（`sha` 由 `model.upload` 写死 `nil`）。
    /// 另做一张弹层会让 §5.9 那两行输入 / 409 两个出口 / 两档结果屏各抄一份。
    ///
    /// ⚠️ `defaultBranchName` 在**呈现这一刻**算：`FileWriteTarget.defaultNewBranchName(now:)`
    /// 的 `now` 必传（同 `EditorView`），在这里取 `Date()` 与在那里取是同一件事 ——
    /// 关键是它只在弹层出现时算一次，而不是每次重绘都变。
    private func uploadCommitSheet(_ draft: UploadDraft) -> some View {
        CommitSheet(
            source: draft.source,
            fullName: fullName,
            branch: model.tree.branch ?? "",
            // ⚠️ 上传出口**必须露出落点**：路径是 App 定的（§5.8 / 决策 #70②），
            //    不露出来用户就只能靠猜 —— 而"东西存到哪"是这一步唯一可能搞错的事。
            destinationPath: RepoPath(path: draft.fileName),
            // ⚠️ 动过才非 nil（切片 8.7 / 8.8）—— 那一句 caption 就是"App 改了你选中的
            //    字节 / 甚至文件名"这件事的唯一出口（决策 #71⑤ · #72⑤）。
            adjustment: draft.adjustment,
            defaultBranchName: FileWriteTarget.defaultNewBranchName(now: Date()),
            onSubmit: { commit, _ in
                // ⚠️ 那个 `sha` 参数在这里**有意丢掉**：上传恒为新建
                //    （`RepoDetailViewModel.upload` 里写死 `nil`），不存在"基准过期"这一档。
                await model.upload(draft, commit: commit)
            },
            onSettled: { outcome, commit in
                env.toast.show(CommitSheetCopy.toast(
                    for: outcome,
                    currentBranch: model.tree.branch ?? "",
                    message: commit.effectiveMessage
                ))
                // ⚠️ **这里不 pop**：用户是从**这一页**点「＋ 添加」进来的，
                //    提交完该留在这儿看那个新文件（列表已经由 `model.upload` 刷过）。
                //    「提交完返回上一页」是**编辑器**那条路的规定（§4.6），不是这一条。
            }
        )
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
                        // 决策 #80：确定写不了时头部那颗星标变灰 + 下方一行说明。
                        // ⚠️ 本页多半恒为 `true`（自己的仓库必然在安装范围内），
                        //    唯一的例外是"组织仓库且那个组织没装 GitDuo"。
                        canStar: model.starWritable,
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
                onTapFilter: { sheet = .labelPicker },
                onRemoveLabel: { label in
                    Task { await model.removeIssueLabel(label) }
                },
                onOpen: { number in
                    // ⚠️ `readOnly: false` **显式传**（铁律 #7）—— 与下面 PR 那一处同一条：
                    //    本页是"自己的仓库"（本页的可写性在别处也是这么写的）。
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

    /// 「＋ 添加」—— **切片 8.4 起可点**，打开 §5.8 的添加文件弹层。
    ///
    /// ⚠️ 它此前那套"画出但不可点"（`allowsHitTesting(false)` + 读屏 hint +
    /// 一个真的什么都不做的闭包）连同 `RepoCopy.addFileUnavailableHint` 一起删掉了。
    /// 留着那句 hint，"这三个出口还不能用"在代码里就仍然看起来成立 ——
    /// 而它们现在**都能用**。
    ///
    /// ⚠️ 形态一个像素都没动：这一片改的是**行为**，不是版式。
    private var addFileButton: some View {
        Button {
            sheet = .addFile
        } label: {
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
            // 切片 7 起这块是**共享件**（Issues / PR 两段也用同一个失败块）——
            // 抄三份的下场是那句「这一块加载失败」只会在其中一处被改。
            SectionFailure(error: error) { Task { await model.loadMoreCommits() } }
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

            // ⚠️ 代码分区那一块**复用共享件的骨架**（`RepoTreeSkeleton`）——
            //    本文件此前自己抄了一份逐字相同的（`codeSkeleton`），随切片 10 收口删除。
            //    理由同 6.4 建 `RepoTreeSection` 时那条：**同一个 UI 元素有两处定义 ⇒ 必然分叉**。
            RepoTreeSkeleton()
        }
        .accessibilityHidden(true)
    }

    /// 提交段的骨架。
    ///
    /// ⚠️ **容器参数与行内边距必须与上面那个真实的 `commitsList` 对齐**
    /// （`CardBox(vertical: Theme.Spacing.xs)` + `RepoCommitRow` 的 `padding:11px 4px`）。
    /// 2026-10-09 切片 10 修：此前写的是 `Theme.Spacing.m`（12）且没有行内边距 ⇒
    /// 数据到达时**整块上移 8pt**，随后每一行再各挪一次。
    private var commitsSkeleton: some View {
        CardBox(vertical: Theme.Spacing.xs, horizontal: 14) {
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

    /// 首屏失败 —— 必须留一个出口（PRD §1 设计原则 4）。
    ///
    /// ⚠️ 走共用件 `PageFailure`（切片 7.4 收口）：本页、`CommitDetailView`、
    /// `BranchesView` 三处原本各有一份**逐字相同**的实现。
    private func failureState(_ error: GitHubError) -> some View {
        PageFailure(error: error) { Task { await model.refresh() } }
    }
}
