import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 探索仓库详情 · 他人仓库（推入页）（PRD §4.13、TECH_SPEC §9.11）。
///
/// ## 8 个分区分属三个切片（PRD §4.13 的分片表）
///
/// | 分区 | 本切片 |
/// |---|---|
/// | ① 仓库头部 · ③ 语言构成 · ④ Latest Release · ⑦ 参与协作 · ⑧ 贡献者 | ✅ 本切片 |
/// | ② 我的收藏（私人整理） | 切片 9 |
/// | ⑤ 文件浏览 · ⑥ README.md | 切片 6 |
///
/// 未落地的三个用 `PendingSection` 显式标注 —— 整块不渲染会让评审看不出还差什么
/// （`AGENTS.md §0` 的"一眼可辨、不冒充成品"）。
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

    /// 「现在」只在**进页与刷新时**取一次，不在 `body` 里取。
    ///
    /// ⚠️ 在 `body` 里取 `Date()` 会让每次重绘都拿到略微不同的值 —— 那本身无害，
    /// 但它让"相对时间"变成渲染时机的一部分，测试与截图都无从稳定。
    @State private var now = Date()

    init(
        fullName: String,
        insights: LoadRepoInsights,
        starToggle: ToggleStar,
        visits: any RecentVisitStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        _model = State(initialValue: ExploreRepoViewModel(
            loader: insights,
            starToggle: starToggle,
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
            await model.start(fullName: fullName)
            // 四路并发取完之后再对一次表：网速慢时"30 分钟前推送"可能已经变成"31 分钟前"。
            now = Date()
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

    /// 分区顺序 = PRD §4.13 的 1…8（跳过的两个用占位块顶住位置，让评审能逐条对照）。
    @ViewBuilder
    private func sections(_ insights: RepoInsights) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RepoHeroCard(
                detail: insights.detail,
                now: now,
                star: model.star,
                isTogglingStar: model.isTogglingStar
            ) {
                Task { await model.toggleStar() }
            }

            PendingSection(
                title: ExploreRepoCopy.myFoldersSection,
                note: "切片 9 落地 · 收藏是纯本地能力（PRD §6.2）"
            )

            languageSection(insights)

            releaseSection(insights)

            PendingSection(
                title: ExploreRepoCopy.fileSection,
                note: "切片 6 落地 · 只读文件树 + 分支切换（PRD §4.5 / §5.7）"
            )
            PendingSection(
                title: ExploreRepoCopy.readmeSection,
                note: "切片 6 落地 · 块级 Markdown 渲染（TECH_SPEC §11.1）"
            )

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
            starToggle: environment.starToggle,
            visits: environment.recentVisits,
            toast: environment.toast
        )
    }
    .environment(environment)
}
