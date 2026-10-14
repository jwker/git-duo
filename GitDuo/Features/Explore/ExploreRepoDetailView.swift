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
/// ## ⚠️ 2026-10-14：⑤ / ⑥ 两分区先后改了**两次**（走查第 63 条 + README 进仓库首页）
///
/// **第一次**：两分区原先是本页里的一整块目录浏览（`RepoTreeSection` + `RepoTreeSession`，
/// 与 §4.4 的「代码」分区共用），于是子目录要"推入一层新页面"。它被改成**一条入口行**，
/// 点进去是 **`RepoCodeView`（只读进去）** —— 目录层级在那一页内部推进，
/// 而这一页不再有"当前层"这件事。
///
/// **第二次**（同日，用户要求）：⑥ **README 搬回本页** —— 就在 ⑤ 那条入口行之后。
/// README 是"这个仓库是什么"，它不是目录的一部分；当年跟着目录进代码页只因为
/// "在根目录顺带取到了那一份"。现在它与 §4.4 首页共用 `RepoReadmeSection`，
/// 取数走 `LoadRepoReadme`（两页都已经有头部在手 ⇒ 不必解析分支）。
///
/// ⚠️ 连带变化两条（都是**第一次**那次带来的）：
/// - **本页不再能切分支**（原型那一处——`exploreTree`——已随同步删除；分支胶囊现在
///   长在代码页的面包屑上）。
///   分支切换跟着面包屑一起去了代码页 —— 那一页是唯一还有面包屑的地方，
///   而"在他人仓库上切分支"的语义（记忆照写、只读的切）在那里与 §4.4 共用一个实现。
/// - 弹层从两个（分支 / 版本说明）收成一个（版本说明）。
///
/// ## ⚠️ 本页**不含任何写操作**（Star 除外）
///
/// 没有 添加 / 编辑 / 提交 / Revert —— 那些只在「我的仓库」详情页。
/// 归属由**路由**在进入前定下（铁律 #7），所以这里**不要**读 `detail.canWrite`
/// 去长出编辑入口：那会让"两种入口能做的事不一致"。
struct ExploreRepoDetailView: View {

    let fullName: String

    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL

    @State private var model: ExploreRepoViewModel

    /// 版本说明全文（`LatestRelease.notesBlocks`）—— 卡片那颗「更多」的落点。
    ///
    /// ⚠️ 2026-10-11 新增（原型里**没有**这张弹层）：正文从卡片挪到这里，
    ///    卡片才不会被一段长说明撑爆。见 `LatestRelease.notesBlocks` 的说明。
    ///
    /// ⚠️ 2026-10-14：它从"两张弹层里的一个 enum case"简化成**一个布尔量** ——
    ///    分支那张随目录浏览一起搬去了代码页，本页只剩这一张
    ///    （一个 `enum` 只有一个 case 时，它存在的理由——"两个布尔量同时为真谁盖谁"
    ///    ——已经不成立了）。
    @State private var showsReleaseNotes = false

    /// 「现在」只在**进页与刷新时**取一次，不在 `body` 里取。
    ///
    /// ⚠️ 在 `body` 里取 `Date()` 会让每次重绘都拿到略微不同的值 —— 那本身无害，
    /// 但它让"相对时间"变成渲染时机的一部分，测试与截图都无从稳定。
    @State private var now = Date()

    init(
        fullName: String,
        insights: LoadRepoInsights,
        readme: LoadRepoReadme,
        starToggle: ToggleStar,
        // ⚠️ 决策 #80：本页**几乎每一条都写不了**（都是别人的仓库），
        //    所以这个缓存比在 §4.4 更要紧 —— 传组合根那**同一个**（预热过的那份）。
        starScope: StarWriteScopeCache,
        visits: any RecentVisitStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        _model = State(initialValue: ExploreRepoViewModel(
            fullName: fullName,
            loader: insights,
            readme: readme,
            starToggle: starToggle,
            starScope: starScope,
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
        .sheet(isPresented: $showsReleaseNotes) {
            // ⚠️ 这一档**读的是弹层自己那一份**（`model.insights` 上的 `release`），
            //    不另存一份「要展示的版本说明」到 `@State` —— 那会变成第二个真相源，
            //    而下拉刷新（`model.refresh()`）会把它换成新的、旧的却还挂在弹层里。
            //    取不到就什么都不画（正常到不了：`hasNotes` 为假时按钮就不给）。
            if let release = model.insights.value?.release {
                ReleaseNotesSheet(release: release)
                    // ⚠️ 这里是**读全文**的弹层 ⇒ 直接给 `.large`，
                    //    别让它先只有半屏、还要用户自己往上拽。
                    .presentationDetents([.large])
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

            // ⑥ README —— ⚠️ **2026-10-14 晚些回到本页**（用户要求它从代码页挪到仓库首页）。
            //    它与 §4.4 首页那块是**同一个** `RepoReadmeSection`：三档（骨架 / 内容 /
            //    块级失败）与三套接线（相对链接、相对图片、小节标题）全在那一件里。
            //    ⚠️ 位置：按 §4.13 的分区顺序，它在 ⑤ 文件浏览之后、⑦ 参与协作之前。
            RepoReadmeSection(
                state: model.readme,
                fullName: fullName,
                // ⚠️ `ref` 取详情里的默认分支 —— 与 `LoadRepoReadme` 取数时同一个值
                //    （正文与图片必须同源；本页不解析分支记忆，见 `ExploreRepoViewModel`）。
                ref: insights.detail.defaultBranch,
                // ⚠️ `readOnly: true` —— 本页恒是**他人仓库**（路由在进入前定下，铁律 #7）
                //    ⇒ README 里点进文件页 / 代码页都走只读那一组界面。
                readOnly: true
            ) {
                Task { await model.retryReadme() }
            }

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
                // ⚠️ 图标用 `tag` 而不是原型里那个 fork 字形：原型 `10-explore-repo.js:44`
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

            // ⚠️ 正文**不在这里画**（2026-10-11 改口径）：原型 `10-explore-repo.js:45`
            //    把整段说明铺在卡片正文里，于是一段几百字的 release note 会把这张卡
            //    撑到占满整屏、把下面的语言构成 / 文件浏览全推走。
            //    现在卡片里一个字都不画，只多一颗「更多」⇒ 点开弹层看全文
            //    （`release.notesBlocks`，用 Markdown 渲染）。
            //    `hasNotes` 为假 ⇒ **连按钮都不给**（没东西可看，别给一个点开是空的入口）。
            HStack(spacing: Theme.Spacing.s) {
                releaseButton(ExploreRepoCopy.sourceCodeButton)
                releaseButton(release.assetsButtonTitle)
                if release.hasNotes {
                    releaseChip(LatestRelease.notesButtonTitle) { showsReleaseNotes = true }
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

    /// §4.13 的 ⑤ / ⑥ 两分区 —— 一条入口行（2026-10-14 起，走查第 63 条）。
    ///
    /// ## ⚠️ 它原先**就是这两分区本身**（一块内嵌的目录浏览）
    ///
    /// 那时它渲染的是 `RepoTreeSection`（面包屑 + 目录卡片 + README），
    /// 子目录要"推入一层新页面"。现在换成一个落点：
    /// 点这一行 → `RepoCodeView（readOnly: true）` —— 目录层级在那一页内部推进，
    /// 「哪一层」不再出现在本页（连带 `path` 参数一起删掉）。
    ///
    /// ⚠️ 小节标题留着（原型这一块有「文件浏览」这个标题），
    /// 但 ` · {path}` 那一半删了：本页已经不存在"当前目录"。
    ///
    /// ⚠️ **只读那一档在代码页里少一项**：导航栏右上角那颗「⋯」照给，
    /// 只是菜单里只剩 `复制路径`（`添加文件` 在别人的仓库上做不了）。
    @ViewBuilder
    private var fileSection: some View {
        SectionHeader(title: ExploreRepoCopy.fileSection)

        CardBox(vertical: Theme.Spacing.xs) {
            LinkRow(
                systemImage: GitHubIcon.folder,
                title: ExploreRepoCopy.fileBrowseRowTitle,
                showsSeparator: false
            ) {
                env.router.push(.repoCode(
                    fullName: fullName,
                    // ⚠️ `readOnly: true` —— 走「他人仓库」那一组界面
                    //    （那颗「⋯」不给、分支弹层不给「管理分支…」）。
                    readOnly: true,
                    // ⚠️ 根目录进：这一步的用户意图是"去看这个仓库有什么"，
                    //    而不是"打开某个已知目录"（那个场景在文件页的 README 链接上，
                    //    见 `FileView` 那一处）。
                    path: nil
                ))
            }
        }
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
            insights: environment.repoInsights,
            readme: environment.repoReadme,
            starToggle: environment.starToggle,
            starScope: environment.starWriteScope,
            visits: environment.recentVisits,
            toast: environment.toast
        )
    }
    .environment(environment)
}
