import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 探索仓库详情 · 他人仓库（推入页）（PRD §4.13、TECH_SPEC §9.11）。
///
/// ## 7 个分区**全部落地**（PRD §4.13 的分片表）
///
/// | 分区 | 落地 |
/// |---|---|
/// | ① 仓库头部 · ③ 语言构成 · ④ Latest Release · ⑤ 文件浏览 · ⑥ README.md · ⑦ 参与协作 · ⑧ 贡献者 | 切片 4 / 6.4 |
///
/// （原 ②「我的收藏」分区已于 2026-10-11 随该功能整体移除。）
///
/// ## ⚠️ ⑤ / ⑥ 两分区是**共享件**渲染的
///
/// 它们与 §4.4 的「代码」分区是同一件事：一条面包屑、一列目录条目、一份 README。
/// 渲染在 `RepoTreeSection`、状态在 `RepoTreeSession`。本页与 §4.4 的两处差别：
/// 面包屑右侧**没有**「＋ 添加」、点一行的落点是**只读**的那两条路由。
///
/// ## ⚠️ 分支可以切（只读的切）
///
/// 原型的 `exploreTree` 面包屑上那个胶囊是可点的（`openBranchSheet(false)`），
/// 切分支会写进**按仓库的记忆** —— 与 §4.4 共用同一份。
/// 而弹层是 `BranchSheet(isReadOnly: true)`：**不给**「管理分支…」入口
/// （在他人仓库上给一个管理入口，点进去每一行都必然失败，而失败原因从那一屏看不出来）。
///
/// ## ⚠️ 本页**不含任何写操作**（Star 除外）
///
/// 没有 添加 / 编辑 / 提交 / Revert —— 那些只在「我的仓库」详情页。
/// 归属由**路由**在进入前定下（铁律 #7），所以这里**不要**读 `detail.canWrite`
/// 去长出编辑入口：那会让"两种入口能做的事不一致"。
struct ExploreRepoDetailView: View {

    let fullName: String

    /// 当前目录 —— 由路由给（`.exploreRepoDetail(fullName:path:)`）。
    /// 进子目录是**推入一层新页面**（原型 `push('exploreRepoDetail',{repo, sub})`）。
    let path: RepoPath

    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL

    @State private var model: ExploreRepoViewModel

    /// 本页的弹层路由。
    ///
    /// ⚠️ 用 `Identifiable` 枚举驱动 `.sheet(item:)`，**不用 `isPresented` 布尔量**：
    /// 本页已有两张弹层（分支 / 版本说明），两个布尔量同时为真会让
    /// "哪一张盖在上面"变成呈现顺序问题，而那种 bug 只在特定点击序列下出现。
    /// 一个枚举天然只有一张。
    @State private var sheet: ExploreSheet?

    private enum ExploreSheet: String, Identifiable {
        case branch
        /// 版本说明全文（`LatestRelease.notesBlocks`）—— 卡片那颗「更多」的落点。
        ///
        /// ⚠️ 2026-10-11 新增（原型里**没有**这张弹层）：正文从卡片挪到这里，
        ///    卡片才不会被一段长说明撑爆。见 `LatestRelease.notesBlocks` 的说明。
        case releaseNotes

        var id: String { rawValue }
    }

    /// 「现在」只在**进页与刷新时**取一次，不在 `body` 里取。
    ///
    /// ⚠️ 在 `body` 里取 `Date()` 会让每次重绘都拿到略微不同的值 —— 那本身无害，
    /// 但它让"相对时间"变成渲染时机的一部分，测试与截图都无从稳定。
    @State private var now = Date()

    init(
        fullName: String,
        path: RepoPath,
        insights: LoadRepoInsights,
        treeLoader: LoadRepoTree,
        branches: LoadBranches,
        starToggle: ToggleStar,
        // ⚠️ 决策 #80：本页**几乎每一条都写不了**（都是别人的仓库），
        //    所以这个缓存比在 §4.4 更要紧 —— 传组合根那**同一个**（预热过的那份）。
        starScope: StarWriteScopeCache,
        memory: any BranchMemoryStore,
        visits: any RecentVisitStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.path = path
        _model = State(initialValue: ExploreRepoViewModel(
            fullName: fullName,
            path: path,
            loader: insights,
            treeLoader: treeLoader,
            branches: branches,
            starToggle: starToggle,
            starScope: starScope,
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
        .refreshable { await model.refresh() }
        .task {
            now = Date()
            await model.start()
            // 四路并发取完之后再对一次表：网速慢时"30 分钟前推送"可能已经变成"31 分钟前"。
            now = Date()
        }
        .sheet(item: $sheet) { route in
            switch route {
            case .branch:
                // ⚠️ `isReadOnly: true` ⇒ 标题换成"浏览他人仓库"那一句、
                //    底部**不给**「管理分支…」入口（见类型说明的"分支可以切"一节）。
                BranchSheet(
                    state: model.tree.branchList,
                    currentBranch: model.tree.branch ?? "",
                    isReadOnly: true,
                    onSelect: { picked in
                        sheet = nil
                        Task { await model.switchBranch(to: picked) }
                    },
                    onManage: nil,
                    onRetry: { Task { await model.loadBranches() } }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .task { await model.loadBranches() }

            case .releaseNotes:
                // ⚠️ 这一档**读的是弹层自己那一份**（`model.insights` 上的 `release`），
                //    不另存一份「要展示的版本说明」到 `@State` —— 那会变成第二个真相源，
                //    而下拉刷新（`model.refresh()`）会把它换成新的、旧的却还挂在弹层里。
                //    取不到就什么都不画（正常到不了：`hasNotes` 为假时按钮就不给）。
                if let release = model.insights.value?.release {
                    ReleaseNotesSheet(release: release)
                        // ⚠️ 这里是**读全文**的弹层 ⇒ 直接给 `.large`，
                        //    别让它先只有半屏、还要用户自己往上拽（分支那张是选择列表，
                        //    半屏反而更顺手，所以两张的档位有意不同）。
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
    }

    private var name: String {
        (try? RepositoryMapper.splitFullName(fullName))?.name ?? fullName
    }

    // MARK: - 主区域

    @ViewBuilder
    private var content: some View {
        switch model.insights.presentation {
        case .skeleton:
            skeleton

        case .content:
            if let insights = model.insights.value {
                sections(insights)
            }

        case let .failure(error):
            failureState(error)
        }
    }

    /// 分区顺序 = PRD §4.13（原 ②「我的收藏」已随功能移除）。
    @ViewBuilder
    private func sections(_ insights: RepoInsights) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RepoHeroCard(
                detail: insights.detail,
                now: now,
                star: model.star,
                // 决策 #80：确定写不了 ⇒ 那颗星变灰、下方多一行说明。
                // ⚠️ 本页是这条限制影响最大的屏 —— 它进来的多半是别人的仓库，
                //    所以"灰的"才是常态、"能点"才少见。
                canStar: model.starWritable,
                isTogglingStar: model.isTogglingStar
            ) {
                Task { await model.toggleStar() }
            }

            languageSection(insights)

            releaseSection(insights)

            fileSection

            collaborationSection

            contributorSection(insights)
        }
    }

    // MARK: - ③ 语言构成

    /// 空仓库 / 只有配置文件 ⇒ **分区保留 + 标题下一行灰字**（PRD §7）。
    ///
    /// ⚠️ 不画一根全灰的条：那看起来像"这个仓库 100% 是某种语言"（§9.11 明写）。
    @ViewBuilder
    private func languageSection(_ insights: RepoInsights) -> some View {
        SectionHeader(title: ExploreRepoCopy.languageSection)

        if insights.languages.isEmpty {
            emptyLine(ExploreRepoCopy.noLanguages)
        } else {
            CardBox {
                LanguageBar(shares: insights.languages)
            }
        }
    }

    // MARK: - ④ Latest Release

    @ViewBuilder
    private func releaseSection(_ insights: RepoInsights) -> some View {
        SectionHeader(title: ExploreRepoCopy.releaseSection)

        if let release = insights.release {
            CardBox {
                releaseCard(release)
            }
        } else {
            // `nil` = 这个仓库从没发过版本（**不是错误** —— `releases/latest` 的 404
            // 在端点里已被翻译成 nil，见 `GitHubRepoInsightsEndpoint`）。
            emptyLine(ExploreRepoCopy.noRelease)
        }
    }

    private func releaseCard(_ release: LatestRelease) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.s) {
                // ⚠️ 图标用 `tag` 而不是原型里那个 fork 字形：原型 `10-explore-repo.js:45`
                //    写的是 `svg(I.fork)`，而版本胶囊配一个"分叉"图标显然是笔误
                //    （图标表里就有现成的 `I.tag`）。PRD 也只写"版本胶囊"，未指定图标。
                //    **已作为候选修订上报**（改回一行即可）。
                Label(release.tagName, systemImage: "tag")
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.Palette.stateReleased)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Theme.Palette.surfaceSunken)
                    )

                // ⚠️ `publishedAt` 为空时**不渲染时间**，而不是拿当前时间顶上
                //    （那会把"发布时间未知"显示成"刚刚发布"）。
                if let published = release.publishedLabel(now: now) {
                    Text(published)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }

                Spacer(minLength: 0)
            }

            // ⚠️ 正文**不在这里画**（2026-10-11 改口径）：原型 `10-explore-repo.js:46`
            //    把整段说明铺在卡片正文里，于是一段几百字的 release note 会把这张卡
            //    撑到占满整屏、把下面的语言构成 / 文件浏览全推走。
            //    现在卡片里一个字都不画，只多一颗「更多」⇒ 点开弹层看全文
            //    （`release.notesBlocks`，用 Markdown 渲染）。
            //    `hasNotes` 为假 ⇒ **连按钮都不给**（没东西可看，别给一个点开是空的入口）。
            HStack(spacing: Theme.Spacing.s) {
                releaseButton(ExploreRepoCopy.sourceCodeButton)
                releaseButton(release.assetsButtonTitle)
                if release.hasNotes {
                    releaseChip(LatestRelease.notesButtonTitle) { sheet = .releaseNotes }
                }
            }
            .padding(.top, Theme.Spacing.m)
        }
    }

    /// 两颗下载按钮都跳同一个网页端 Release 页。
    ///
    /// ⚠️ **不假装能下载**：资产下载（鉴权 URL、断点续传、文件落盘）是另一个模块的事，
    /// 而"点了只弹一句提示"是 PRD §8.1 明令禁止的"停留在入口或提示"。
    /// 跳到真实页面至少让用户真的拿到东西 —— 与「置顶管理」同一处置模式（§9.1）。
    private func releaseButton(_ title: String) -> some View {
        releaseChip(title) {
            guard let url = URL(string: "https://github.com/\(fullName)/releases/latest") else { return }
            openURL(url)
        }
    }

    /// 卡片底部那一排 chip 的**唯一形态**（描边 + 内边距 + 字色）—— 动作由调用方给。
    ///
    /// ⚠️ 三颗（下载源码 / 资产 / 更多）的外观**逐字相同**、只有动作不同。
    /// 这正是"两份会各自漂移"的典型：外观收在一处，要改也只落在这里。
    private func releaseChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(Theme.Font.label)
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Palette.border, lineWidth: 1)
            )
            .buttonStyle(.plain)
    }

    // MARK: - ⑤ / ⑥ 文件浏览 · README

    /// §4.13 的 ⑤ 与 ⑥ 两分区 —— 由共享件 `RepoTreeSection` 一并渲染
    /// （按原型的顺序画出「文件浏览」小节标题、面包屑、目录卡片、
    /// 以及 `README.md` 的小节标题与正文）。
    ///
    /// ⚠️ **子目录里推入的是一层新页面**（原型 `push('exploreRepoDetail',{repo, sub})`），
    /// 不是"原地换掉目录" —— 所以返回时回到的是上一级，而不是根。
    ///
    /// ⚠️ README **只有根目录**会出现：`LoadRepoTree` 有意只在根目录问 `readme` 端点
    /// （在任何子目录下问它都会拿到同一份仓库级 README，而那不是"这个目录的说明"）。
    /// 原型在子目录里也照样印一份 —— 那是它的演示数据假象，不是规格。
    private var fileSection: some View {
        RepoTreeSection(
            session: model.tree,
            title: ExploreRepoCopy.fileSection(path: path),
            onOpenDirectory: { target in
                // ⚠️ 每一层都带 `fullName`：子目录页是**新的一页**，它不知道上一页是谁。
                env.router.push(.exploreRepoDetail(
                    fullName: fullName,
                    path: target.isRoot ? nil : target.raw
                ))
            },
            onOpenFile: { target in
                // ⚠️ `readOnly: true` —— 走「他人仓库」那一组界面
                //    （`编辑` 换成 `⑂ Fork 后可编辑`、页脚换成 `只读浏览 · 他人仓库文件`）。
                env.router.push(.fileView(
                    fullName: fullName, path: target.raw, readOnly: true
                ))
            },
            onTapBranch: { sheet = .branch },
            onSelectSegment: { index in navigate(toCrumb: index) }
        )
    }

    /// 点面包屑的某一层 —— 与 §4.4 同规矩：**推入一层新页面**，不原地替换。
    ///
    /// - Parameter index: 面包屑上的下标，**第 0 段是仓库全名**。
    private func navigate(toCrumb index: Int) {
        // index 0 ⇒ 仓库根目录；index k ⇒ 仓库内的第 k-1 层（`RepoPath` 里根是空路径）。
        let target = index == 0 ? RepoPath.root : model.tree.path(upTo: index - 1)
        guard let target, target != model.tree.path else { return }
        env.router.push(.exploreRepoDetail(
            fullName: fullName, path: target.isRoot ? nil : target.raw
        ))
    }

    // MARK: - ⑦ 参与协作

    @ViewBuilder
    private var collaborationSection: some View {
        SectionHeader(title: ExploreRepoCopy.collaborationSection)

        CardBox(vertical: Theme.Spacing.xs) {
            LinkRow(
                systemImage: StateIcon.issueOpen,
                iconTint: Theme.Palette.stateOpenIcon,
                title: ExploreRepoCopy.issuesRowTitle,
                subtitle: ExploreRepoCopy.issuesRowSubtitle
            ) {
                env.router.push(.exploreIssueList(fullName: fullName))
            }
            LinkRow(
                systemImage: StateIcon.pullRequestOpen,
                iconTint: Theme.Palette.stateOpenIcon,
                title: ExploreRepoCopy.pullsRowTitle,
                subtitle: ExploreRepoCopy.pullsRowSubtitle,
                showsSeparator: false
            ) {
                env.router.push(.explorePRList(fullName: fullName))
            }
        }
    }

    // MARK: - ⑧ 贡献者

    @ViewBuilder
    private func contributorSection(_ insights: RepoInsights) -> some View {
        let roster = insights.contributors
        // 空名单时用不带计数的标题（`贡献者` 而不是 `贡献者 · 0 位`）——
        // 判据收在 `ContributorRoster.displayTitle`，不在这里各写一次。
        SectionHeader(title: roster.displayTitle)

        if roster.contributors.isEmpty {
            // ⚠️ **不画一排 `?` 占位头像**：那看起来像"头像还在加载"（§9.11 明写）。
            emptyLine(ExploreRepoCopy.noContributors)
        } else {
            CardBox {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    AvatarStack(
                        members: roster.contributors.map {
                            AvatarStack.Member(login: $0.login, avatarURL: $0.avatarURL)
                        }
                    )

                    // `以及另外 N 位贡献者`；全都画出来了 ⇒ `nil` ⇒ 这一行不渲染
                    // （原型那处会算成负数，见 `ContributorRoster.remainingLabel`）。
                    if let remaining = roster.remainingLabel(
                        visibleLimit: AvatarStack.defaultVisibleLimit
                    ) {
                        Text(remaining)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - 空态 / 骨架 / 失败

    /// 分区内的空态：**标题下的一行灰字**（PRD §7 对这三处的统一要求）。
    ///
    /// ⚠️ 与首页那两个空态**有意不同**（那里是 `EmptyBox` 虚线框）：
    /// 首页的空态是"这一整块都没有东西"，需要一个框把它框住、并引导用户怎么做；
    /// 这里的空态是"这一项没有数据，但分区本身还在"（分区在不在本身就是一条信息）。
    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            .padding(.horizontal, Theme.Spacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部大卡
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.m) {
                    SkeletonBar(
                        height: RepoAvatar.standard.diameter,
                        width: RepoAvatar.standard.diameter,
                        cornerRadius: RepoAvatar.standard.cornerRadius
                    )
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        SkeletonBar(height: 16, width: 150)
                        SkeletonBar(height: 11, width: 190)
                    }
                    Spacer(minLength: 0)
                }
                SkeletonBar(height: 12)
                SkeletonBar(height: 12, width: 210)
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

            // 三张卡
            ForEach(0..<3, id: \.self) { _ in
                SkeletonBar(height: 12, width: 96).padding(.top, Theme.Spacing.xl)
                CardBox {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        SkeletonBar(height: 12)
                        SkeletonBar(height: 12, width: 180)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
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
        ExploreRepoDetailView(
            fullName: "kuda/ui-craft",
            path: .root,
            insights: environment.repoInsights,
            treeLoader: environment.repoTree,
            branches: environment.branches,
            starToggle: environment.starToggle,
            starScope: environment.starWriteScope,
            memory: environment.branchMemory,
            visits: environment.recentVisits,
            toast: environment.toast
        )
    }
    .environment(environment)
}
