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
/// ## ⚠️ 2026-10-16 主干是 **`List`**，当天又回退成 **`ScrollView + VStack + CardBox`**
///
/// P3 第二批曾把整页换成 `List`：七块各一个 `Section`。实测复现了 §4.4 当年那个回归——
/// **上下间距过大**：`List` 行默认 insets + Section 间距，把几块之间的距离拉得比设计大；
/// 而且头部大卡 / README 这种"自带白面圆角、内部还有 `FlowLayout`"的块坐在 `List` 行里
/// 会被行内边距再压窄一截（`FlowLayout` 在 ideal-size 测量下塌缩）。于是当天改回
/// `ScrollView`：头部大卡与 README 自绘白卡、宽度由页面 padding 决定；语言 / Release /
/// 贡献者三块用 `SectionHeader` + `CardBox`；导航入口那一组（Issues / PR / 文件浏览）
/// 是 `CardBox` + `MenuRow`，并加 `SectionHeader`（标题 `参与协作`、副标题 `他人仓库 · 只读`）
/// （与个人仓库首页四行入口同一件，见 `MenuRow`）。
/// 这正是 P3 实证口径的"富详情页一律 `ScrollView`、自带白面圆角的块不进 `List` 行"。
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
    ///
    /// ## ⚠️ 2026-10-16 回退到 `ScrollView + VStack`：七块平铺
    ///
    /// 七块直接平铺在一个 `VStack(spacing: 0)` 里，组距由 `SectionHeader` 自带的
    /// 22pt 顶距给（同原型 `.section-label{margin:22px}`，也正是 §4.4 仓库首页那一份）。
    /// 头部大卡与 README 自带白面圆角 ⇒ 直接放（不进 `CardBox`，免"卡里套卡"）；
    /// 其余五块各是 `SectionHeader` + `CardBox`（见 `group(_:vertical:horizontal:content:)`）。
    ///
    /// ⚠️ `isPlaceholder` = 骨架态：骨架仍走**同一个** `sections(_:)` 喂 `.placeholder`
    /// （P1 判据 ②），只是把每一块遮成灰块 —— 见 `masked(_:content:)`。
    @ViewBuilder
    private func sections(_ insights: RepoInsights, isPlaceholder: Bool = false) -> some View {
        masked(isPlaceholder) {
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
        }

        masked(isPlaceholder) { languageGroup(insights) }

        masked(isPlaceholder) { releaseGroup(insights) }

        masked(isPlaceholder) { menuGroup }

        // ⑥ README —— ⚠️ **2026-10-14 晚些回到本页**（用户要求它从代码页挪到仓库首页）。
        //    它与 §4.4 首页那块是**同一个** `RepoReadmeSection`：三档（骨架 / 内容 /
        //    块级失败）与三套接线（相对链接、相对图片、小节标题）全在那一件里。
        //    ⚠️ 位置：按 §4.13 的分区顺序，它在 ⑤ 文件浏览之后、⑦ 参与协作之前。
        masked(isPlaceholder) {
            RepoReadmeSection(
                state: model.readme,
                fullName: fullName,
                // ⚠️ `ref` 取详情里的默认分支 —— 与 `LoadRepoReadme` 取数时同一个值
                //    （正文与图片必须同源；本页不解析分支记忆，见 `ExploreRepoViewModel`）。
                ref: insights.detail.defaultBranch,
                // ⚠️ `readOnly: true` —— 本页恒是**他人仓库**（路由在进入前定下，铁律 #7）
                //    ⇒ README 里点进文件页 / 代码页都走只读那一组界面。
                readOnly: true
                // ⚠️ `headerMargins` 用默认 `.section`：本页是 `ScrollView`
                //    ⇒ "README.md" 标题自带 22pt 顶距当组距（同 `RepoReadmeSection` 文档；
                //    `List` 版的 `.none` 覆盖在此不再需要）。
            ) {
                Task { await model.retryReadme() }
            }
        }

        masked(isPlaceholder) { contributorGroup(insights) }
    }

    /// 一个「分区标题 + 白卡」的组合（语言构成 / Latest Release / 贡献者三块共用）。
    ///
    /// ⚠️ `SectionHeader` 自带 22pt 顶距当组距；`CardBox` 给白面圆角与 14 内边距
    ///    （横向 14）。导航入口那一组（`menuGroup`：Issues / Pull Requests / 文件浏览）
    ///    是 `CardBox(horizontal: 0)` + 行自带 `contentPadding: 14` 的 `MenuRow`
    ///    （与个人仓库首页四行入口逐字同构：40pt 色块图标 + 15/600 标题 + 14 内边距），
    ///    并加 `SectionHeader`（标题 `参与协作`、副标题 `他人仓库 · 只读`）—— 见 `menuGroup`。
    private func group(
        _ title: String,
        subtitle: String? = nil,
        vertical: CGFloat = 14,
        horizontal: CGFloat = 14,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: title, subtitle: subtitle)
            CardBox(vertical: vertical, horizontal: horizontal) { content() }
        }
    }

    /// 骨架期把一块遮成灰块。
    ///
    /// ⚠️ **逐块加，不加在整张 `ScrollView` 内容上**：`.allowsHitTesting(false)` 挂在
    ///    某个块上，触摸会穿透到下面的 `ScrollView` ⇒ 滚动照旧、只是这一块不再接收点击
    ///    （`ScrollView` 自己的滚动手势在容器上，不受内容 `redacted` / `allowsHitTesting` 影响）。
    ///
    /// ⚠️ `.redacted` **不拦截点击** ⇒ 两件事必须一起给：遮住的那几行入口
    ///    （文件浏览 / Issues / PR）真的会推页，而且推过去的是 `placeholder/placeholder`。
    @ViewBuilder
    private func masked<Content: View>(
        _ isPlaceholder: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .redacted(reason: isPlaceholder ? .placeholder : [])
            .allowsHitTesting(!isPlaceholder)
    }

    // MARK: - ③ 语言构成

    /// 空仓库 / 只有配置文件 ⇒ **分区保留 + 标题下一行灰字**（PRD §7）。
    ///
    /// ⚠️ 不画一根全灰的条：那看起来像"这个仓库 100% 是某种语言"（§9.11 明写）。
    @ViewBuilder
    private func languageGroup(_ insights: RepoInsights) -> some View {
        group(ExploreRepoCopy.languageSection) {
            if insights.languages.isEmpty {
                emptyLine(ExploreRepoCopy.noLanguages)
            } else {
                LanguageBar(shares: insights.languages)
            }
        }
    }

    // MARK: - ④ Latest Release

    @ViewBuilder
    private func releaseGroup(_ insights: RepoInsights) -> some View {
        group(ExploreRepoCopy.releaseSection) {
            if let release = insights.release {
                releaseCard(release)
            } else {
                // `nil` = 这个仓库从没发过版本（**不是错误** —— `releases/latest` 的 404
                // 在端点里已被翻译成 nil，见 `GitHubRepoInsightsEndpoint`）。
                emptyLine(ExploreRepoCopy.noRelease)
            }
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

    // MARK: - ⑤ / ⑦ 导航入口（文件浏览 · 参与协作 · 合并为一组）

    /// §4.13 的 ⑤「文件浏览」与 ⑦「参与协作（Issues / Pull Requests）」合并为**一组**
    /// 导航入口（用户 2026-10-16 要求：三行放一起、Issues / PR 挪到 文件浏览 之上）。
    ///
    /// ## ⚠️ 它原先**就是这两分区** —— 各自一条入口行
    ///
    /// ⑤ 文件浏览点进去是 `RepoCodeView（readOnly: true）`；⑦ 两行推到 Issues / PR 列表。
    /// 现在三行坐在**同一张裸卡**里（与个人仓库首页四行入口逐字同构）：
    ///
    /// - 裸 `CardBox(vertical: 0, horizontal: 0)` —— 留白由行自己出；
    /// - 每行 `MenuRow` 传 `contentPadding: 14`（原型 `.menu-item{padding:14px}`）
    ///   ⇒ 文字离卡边 14、40pt 色块图标、15/600 标题；
    /// - 分隔线由 `MenuRow` 自己画（首行不画，其后逐行画，见 §4.4 `entries`）。
    ///
    /// ⚠️ **加 `SectionHeader`（标题 = 参与协作）**：这一组是 Issues / PR / 文件浏览
    /// 三行合并的导航入口，标题把它兜成一组（不做"只读"副标题，用户 2026-10-16 要求去掉）。
    /// 容器用 `group(..., vertical: 0, horizontal: 0)`。
    ///
    /// ⚠️ 顺序 = **Issues → Pull Requests → 文件浏览**（用户裁定：Issues / PR 挪到上面）。
    @ViewBuilder
    private var menuGroup: some View {
        group(
            ExploreRepoCopy.collaborationSection,
            vertical: 0,
            horizontal: 0
        ) {
            MenuRow(
                systemImage: StateIcon.issueOpen,
                iconTone: .green,
                title: ExploreRepoCopy.issuesRowTitle,
                accessory: .chevron,
                showsSeparator: false,
                contentPadding: 14
            ) {
                env.router.push(.exploreIssueList(fullName: fullName))
            }
            MenuRow(
                systemImage: StateIcon.pullRequestOpen,
                iconTone: .blue,
                title: ExploreRepoCopy.pullsRowTitle,
                accessory: .chevron,
                showsSeparator: true,
                contentPadding: 14
            ) {
                env.router.push(.explorePRList(fullName: fullName))
            }
            MenuRow(
                systemImage: GitHubIcon.folder,
                iconTone: .slate,
                title: ExploreRepoCopy.fileBrowseRowTitle,
                accessory: .chevron,
                showsSeparator: true,
                contentPadding: 14
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

    // MARK: - ⑧ 贡献者

    @ViewBuilder
    private func contributorGroup(_ insights: RepoInsights) -> some View {
        let roster = insights.contributors
        group(roster.displayTitle) {
            if roster.contributors.isEmpty {
                // ⚠️ **不画一排 `?` 占位头像**：那看起来像"头像还在加载"（§9.11 明写）。
                emptyLine(ExploreRepoCopy.noContributors)
            } else {
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

    /// ## ⚠️ 2026-10-16 起不再手抄几何（NATIVE-MIGRATION P1）
    ///
    /// 画的是真实的 `sections(_:)` + 占位洞察 —— 七个分区的形状
    /// （头部大卡、三张卡的标题条与内容条）从此与内容同源。
    ///
    /// ⚠️ 遮罩由 `sections(_:isPlaceholder:)` **逐块**加（见 `masked(_:content:)` 那条：
    ///    加在整张 `List` 上会把手势一起关掉，骨架期就滚不动了）。
    private var skeleton: some View {
        sections(.placeholder, isPlaceholder: true)
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
