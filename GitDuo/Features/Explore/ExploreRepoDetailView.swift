import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 探索仓库详情 · 他人仓库（推入页）（PRD §4.13、TECH_SPEC §9.11）。
///
/// ## 8 个分区**全部落地**（PRD §4.13 的分片表）
///
/// | 分区 | 落地 |
/// |---|---|
/// | ① 仓库头部 · ③ 语言构成 · ④ Latest Release · ⑤ 文件浏览 · ⑥ README.md · ⑦ 参与协作 · ⑧ 贡献者 | 切片 4 / 6.4 |
/// | ② 我的收藏（私人整理） | **切片 9**（本件） |
///
/// ⚠️ ② 落地之后本页**再没有占位块**，`PendingSection` 随之全 App 消失
/// （切片 9 是"占位清零"的那一片，`REVIEW-CHECKLIST` 第 149 条）。
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
/// ## ⚠️ 本页**不含任何写操作**（Star 与收藏除外）
///
/// 没有 添加 / 编辑 / 提交 / Revert —— 那些只在「我的仓库」详情页。
/// 归属由**路由**在进入前定下（铁律 #7），所以这里**不要**读 `detail.canWrite`
/// 去长出编辑入口：那会让"两种入口能做的事不一致"。
///
/// ⚠️ **收藏不在此列**：它是**本机数据**，与仓库归属无关 ——
/// 谁都能把别人的仓库收进自己的私人列表（PRD §6.2 的"私人整理 · 仅你自己可见"）。
/// 所以它不受"他人仓库只读"这条约束，也不需要 `canWrite`。
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
    /// 三张弹层里有两条**互相切换**的路径（② 的「新建收藏夹…」→ §5.6），
    /// 两个布尔量同时为真时"哪一张盖在上面"就变成了呈现顺序问题，
    /// 而那种 bug 只在特定点击序列下出现。一个枚举天然只有一张。
    ///
    /// ⚠️ 收藏那两张之间**只换值、不经过 `nil`**（关一次再开一次会空一帧，
    /// 与 `FoldersViewModel.SheetRoute` 同一条）。
    @State private var sheet: ExploreSheet?

    private enum ExploreSheet: String, Identifiable {
        case branch
        /// §5.5 选择收藏列表（PRD §4.13 的 ② 分区那颗按钮）。
        case favorites
        /// §5.6 前半 —— 从上面那张弹层底部的「新建收藏夹…」进来，按钮是「创建并收藏」。
        case newFolder

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
        folders: any FolderStore,
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
            // ⚠️ 组合根那**唯一一个** `FolderStore`（与「我的收藏」管理页共用）。
            folders: folders,
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

            case .favorites:
                // §5.5。⚠️ 清单与"当前在哪个夹"都是 `model` 上的那一份快照
                //    —— 弹层自己不读存储（读第二遍就可能与 ② 分区那一行对不上）。
                FavoriteListSheet(
                    summaries: model.folderSummaries,
                    current: model.favoriteFolder,
                    onPick: { name in
                        // ⚠️ **先关再做事**：`pickFolder` 会 toast，
                        //    而 toast 挂在 `MainTabView` 上、弹层盖不住它的话人看不见。
                        //    这里沿用原型 `pickFav` 的顺序（先 `closeSheet()` 再吐提示）。
                        sheet = nil
                        Task { await model.pickFolder(name) }
                    },
                    onNewFolder: {
                        // ⚠️ **只换值、不经过 `nil`**（见 `ExploreSheet` 的说明）。
                        sheet = .newFolder
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)

            case .newFolder:
                // §5.6 前半 —— 仓库详情入口，按钮是「创建并收藏」。
                // ⚠️ 空名那一档**弹层留着** ⇒ 提示画在弹层里（`model.sheetHint`，
                //    决策 #77）；建成 / 重名复用两档**关弹层** ⇒ 照旧走提示条。
                NewFolderSheet(entry: .repository, hint: model.sheetHint) { name in
                    Task {
                        if await model.createFolderAndFavorite(name: name) { sheet = nil }
                    }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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

    /// 分区顺序 = PRD §4.13 的 1…8（**8 个全部落地**，切片 9 之后没有占位块）。
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

            favoriteSection

            languageSection(insights)

            releaseSection(insights)

            fileSection

            collaborationSection

            contributorSection(insights)
        }
    }

    // MARK: - ② 我的收藏（私人整理 · 仅自己可见）

    /// 两颗按钮互斥，由 `favoriteFolder` 决定（原型 `10-explore-repo.js` 逐字）。
    ///
    /// ## ⚠️ 这一块**与 Star 那一套完全不同**
    ///
    /// 它是**纯本地**的（GitHub 没有收藏夹这个资源，§9.12）⇒ 没有"在途"、
    /// 没有失败态、不需要先确认基准。唯一需要注意的是**首帧**：
    /// `favoriteFolder` 在读到之前是 `nil`，而"没读过"与"没收藏过"在画面上长得一样
    /// （都是那颗「收藏到我的列表」）。差别只在一瞬（本地读），所以这里不另造一档骨架
    /// —— 但 `ExploreRepoViewModel.start()` 里那次读**必须排在网络取数之前**
    /// （那里的注释写着为什么）。
    ///
    /// ## ⚠️ 两颗按钮都走 `ActionButton(.ghost)`，**这一步与原型有三处不同**
    ///
    /// 原型那颗「已收藏 · {夹名}」用的是 `.btn.ghost` + 行内覆盖（链接色前景 + 链接色描边），
    /// 而且两颗按钮**都带图标**（书签；已收藏那颗还带一个尾部尖角）。
    /// `ActionButton` 没有图标槽位（`REVIEW-CHECKLIST` 有意偏差第 24 条），
    /// 也没有"链接色"这一档 —— 新造一档要同时定它的前景 / 描边两个值，
    /// 而原型只在一处用过它。取舍是**用既有那一档、把差别记进第 24 条**：
    /// 三处差别（图标 / 链接色 / 尖角）都是"少了一小截"，不是行为差别。
    @ViewBuilder
    private var favoriteSection: some View {
        SectionHeader(title: ExploreRepoCopy.myFoldersSection)

        if let folder = model.favoriteFolder {
            ActionButton(
                // 原型 `${svg(I.bm)} 已收藏 · ${favFolderOf(p.repo)} ${svg(I.chevD)}`
                // —— 前缀（含 ` · ` 分隔）在 `FolderCopy` 里，夹名由这里拼。
                title: FolderCopy.favoritedActionPrefix + folder,
                style: .ghost,
                // 原型 `style="width:100%;padding:11px"`。
                verticalPadding: 11
            ) {
                sheet = .favorites
            }
            hint(FolderCopy.favoriteHintFavorited)
        } else {
            ActionButton(
                title: FolderCopy.favoriteAction,
                style: .ghost,
                verticalPadding: 11
            ) {
                // ⚠️ 首次收藏是**一发本地写**（原型 `favNow`）—— 不进弹层。
                //    弹层留给"已经收藏过、想换夹"那一步（§9.12 的两段式交互）。
                Task { await model.favoriteToDefault() }
            }
            hint(FolderCopy.favoriteHintIdle)
        }
    }

    /// 按钮下面那行灰字（原型 `.t3{text-align:center;margin-top:6px}`）。
    ///
    /// ⚠️ `margin-top:6px` 不在 4pt 阶里 ⇒ 写原值（同 `SheetHint` 的处置）。
    private func hint(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
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

            // 版本说明为空 ⇒ 整段不渲染（渲染一个空盒子更糟）。
            if release.hasNotes, let notes = release.notes {
                Text(notes)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 7)
            }

            HStack(spacing: Theme.Spacing.s) {
                releaseButton(ExploreRepoCopy.sourceCodeButton)
                releaseButton(release.assetsButtonTitle)
            }
            .padding(.top, Theme.Spacing.m)
        }
    }

    /// 两个按钮都跳同一个网页端 Release 页。
    ///
    /// ⚠️ **不假装能下载**：资产下载（鉴权 URL、断点续传、文件落盘）是另一个模块的事，
    /// 而"点了只弹一句提示"是 PRD §8.1 明令禁止的"停留在入口或提示"。
    /// 跳到真实页面至少让用户真的拿到东西 —— 与「置顶管理」同一处置模式（§9.1）。
    private func releaseButton(_ title: String) -> some View {
        Button(title) {
            guard let url = URL(string: "https://github.com/\(fullName)/releases/latest") else { return }
            openURL(url)
        }
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
            folders: environment.folders,
            toast: environment.toast
        )
    }
    .environment(environment)
}
