import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 「我的仓库」**首页**（PRD §4.4、TECH_SPEC §9.4）—— 2026-10-14 起它是**枢纽页**。
///
/// ## 结构：头部大卡 + 四行入口 + README
///
/// | 块 | 是什么 |
/// |---|---|
/// | 仓库头部大卡 | 图标 + 全名 + 描述 + Star / Watch / Fork |
/// | 四行入口 | `代码` / `Issues` / `Pull Requests` / `Commits` —— 四个**独立页面**的入口 |
/// | **README** | ⚠️ **2026-10-14 晚些加**（用户要求它从代码页挪到首页），在四行入口**之下** |
///
/// ## ⚠️ README 为什么在**四行入口之下**（这是用户裁定，不是排版随手定的）
///
/// README 可以很长（几十到几百行）。放在四行入口**之上**，等于让一段仓库自述
/// 把这一页的四个出口推出首屏 —— 而"四行入口"正是这一页作为枢纽的**主要用途**
/// （见下面那条第 63 条的改动：整件事的出发点就是"别让首屏被别的东西占满"）。
/// 放在下面：枢纽该露的照常露，README 是"再往下看"的内容。
///
/// ⚠️ 它是**块级**取数（`LoadRepoReadme`，要头部里的 `defaultBranch` 才知道用哪条分支
/// 读 ⇒ 比头部晚一拍开始）。取不到**只让那一块给「重试」**，头部与四行入口照常
/// —— 判据与分工写在 `RepoDetailViewModel` 的类型说明里，渲染的三档收在
/// `RepoReadmeSection` 里（两页共用）。
///
/// ## ⚠️ 2026-10-14 的大改：分段条撤掉、四个分区各自成页（走查第 63 条）
///
/// 用户的原话是「在仓库首页放一个『代码』的菜单条，点击进入目录结构，之后的操作
/// 都在这个新的页面中」，并列出了两个症状：文件浏览**占太多空间**、点进下级目录
/// **整页重新加载**。谈下来选定的是最彻底的一档 ——
/// **这一页只做枢纽**（大卡 + 四行入口），四个分区全部搬到自己的页面上：
///
/// | 原来 | 现在 |
/// |---|---|
/// | 一条分段条四项，内容就地换 | 四行入口，点进去是**独立页面** |
/// | 「代码」= 内嵌在页面里的目录树 | 「代码」= 独立页面，**自己承载目录层级** |
/// | 进一层目录 = `push` 一个新仓库详情页 | 进一层目录 = **页内推进一层**（不换页面）|
///
/// ⇒ 首屏省下来的正是**头部大卡（约 145pt）+ 分段条连上下间距（约 60pt）**
/// —— 那 200pt 原来顶在**每一层目录**上面，进几次目录就要重复看几次。
///
/// ⚠️ 这一页**不再取**目录 / 提交 / Issues / PR：四行入口的落点各页自己去取自己的数据。
/// 本页只取两件：头部（连带 Star 基准）与 README。
///
/// ## ⚠️ 本页是「自己的仓库」，写入口的有无由**路由**决定
///
/// `ReposView.open()` / 首页置顶 / 最近访问按可写性二选一推入本页或 §4.13。
/// 所以这里**不读** `detail.canWrite` 去长出入口 —— 那会让"两种入口能做的事不一致"
/// （铁律 #7：只读态显式传参，不让下层页自行推断）。`RepoDetailViewModel` 也因此
/// 直接按 `canWrite: true` 记一次最近访问。
struct RepoDetailView: View {

    let fullName: String

    let detail: LoadRepoDetail
    let readme: LoadRepoReadme
    let starToggle: ToggleStar

    /// ⚠️ 决策 #80 那一档判定的来源（"这个仓库写不写得动"）—— 传的必须是组合根里那
    /// **同一个**缓存：另 new 一个的代价是每次进页白问一次 `GET /user/installations`，
    /// 而且它拿不到组合根预热过的那份结果。
    let starScope: StarWriteScopeCache

    let visits: any RecentVisitStore
    let toast: ToastCenter

    @Environment(AppEnvironment.self) private var env

    @State private var model: RepoDetailViewModel

    init(
        fullName: String,
        detail: LoadRepoDetail,
        readme: LoadRepoReadme,
        starToggle: ToggleStar,
        starScope: StarWriteScopeCache,
        visits: any RecentVisitStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.detail = detail
        self.readme = readme
        self.starToggle = starToggle
        self.starScope = starScope
        self.visits = visits
        self.toast = toast
        _model = State(initialValue: RepoDetailViewModel(
            fullName: fullName,
            detail: detail,
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
        .task { await model.start() }
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
                        // 决策 #80：确定写不了时头部那颗星标变灰 + 下方一行说明。
                        // ⚠️ 本页多半恒为 `true`（自己的仓库必然在安装范围内），
                        //    唯一的例外是"组织仓库且那个组织没装 GitDuo"。
                        canStar: model.starWritable,
                        isTogglingStar: model.isTogglingStar
                    ) {
                        Task { await model.toggleStar() }
                    }

                    entries
                        .padding(.top, Theme.Spacing.m)

                    // ⚠️ README 在**四行入口之下**（用户裁定）—— 理由见类型说明：
                    //    上面那四行是这一页作为枢纽的主要出口，一段长 README
                    //    不该把它们推出首屏。
                    //
                    // ⚠️ `ref` 用头部里的 `defaultBranch`：与 `LoadRepoReadme` 取数时
                    //    用的是同一个值（正文与图片必须同源，见 `RepoReadmeSection`）。
                    RepoReadmeSection(
                        state: model.readme,
                        fullName: fullName,
                        ref: snapshot.detail.defaultBranch,
                        // ⚠️ `readOnly: false` —— 本页是「自己的仓库」，写入口的有无
                        //    由**路由**在进入前定下（铁律 #7），这里不自己去推断。
                        readOnly: false
                    ) {
                        Task { await model.retryReadme() }
                    }
                }
            }

        case let .failure(error):
            // 头部拿不到 ⇒ **整页失败**：连四行入口都不画 ——
            // 那四行里有三行要仓库全名之外的上下文，而它们推进去也只会各失败一次。
            PageFailure(error: error) { Task { await model.refresh() } }
        }
    }

    // MARK: - 四行入口

    /// 四行入口（`代码` + `RepoSection.allCases` 那三档）。
    ///
    /// ⚠️ **顺序**：`代码` 恒在第一行，后三行走 `RepoSection.allCases`
    /// （`CaseIterable` 的顺序就是原型分段条从左到右的顺序）——
    /// 不在这里手写一个数组，否则"入口顺序变了"不会有人当成 bug 报上来。
    ///
    /// ⚠️ 图标只有「Commits」那一行是新加的（`GitHubIcon.commit`）；
    /// 另外三行复用已有字形：`folder`（代码）、`StateIcon.issueOpen`、`StateIcon.pullRequestOpen`
    /// —— 后两个与 §4.13「参与协作」那两行**同一个字形、同一个颜色**，
    /// 于是"同一个东西在两个页面上长得一样"这条继续成立。
    private var entries: some View {
        let rows = entryRows

        return CardBox(vertical: Theme.Spacing.xs) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                LinkRow(
                    systemImage: row.icon,
                    iconTint: row.tint,
                    title: row.title,
                    showsSeparator: index < rows.count - 1
                ) {
                    env.router.push(row.route)
                }
            }
        }
    }

    /// 四行入口的定义（图标 / 颜色 / 文字 / 落点全在一处）。
    ///
    /// ⚠️ 做成一个中间结构而不是在 `ForEach` 里 `switch`：四行里三行的图标与颜色
    /// 随 `section` 变、落点也随它变，散在视图里就是"改一行颜色要翻三层"。
    private var entryRows: [EntryRow] {
        var rows = [
            EntryRow(
                id: "code",
                icon: GitHubIcon.folder,
                tint: Theme.Palette.textTertiary,
                title: RepoCopy.codeEntryTitle,
                route: .repoCode(fullName: fullName, readOnly: false, path: nil)
            )
        ]

        rows += RepoSection.allCases.map { section in
            EntryRow(
                id: section.rawValue,
                icon: icon(for: section),
                tint: tint(for: section),
                title: section.title,
                route: .repoSection(fullName: fullName, section: section)
            )
        }

        return rows
    }

    private func icon(for section: RepoSection) -> String {
        switch section {
        case .issues: StateIcon.issueOpen
        case .pullRequests: StateIcon.pullRequestOpen
        case .commits: GitHubIcon.commit
        }
    }

    /// 状态图标用**开放态那个颜色**（与 §4.13 那两行一致）。
    ///
    /// ⚠️ 这三个入口**都不是状态**（它们是"去哪个列表"），所以颜色只是沿用
    /// "这一类东西"的固定色 —— 与列表行上的状态胶囊无关，不要从这里推"这个仓库
    /// 有没有开放的 Issue"。
    private func tint(for section: RepoSection) -> Color {
        switch section {
        case .issues, .pullRequests: Theme.Palette.stateOpenIcon
        case .commits: Theme.Palette.textTertiary
        }
    }

    /// 一行入口。
    private struct EntryRow: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let route: Route
    }

    // MARK: - 骨架

    /// 首屏骨架（头部大卡 + 四行入口）。
    ///
    /// ⚠️ 它此前是"大卡 + 分段条 + 代码分区骨架"三块 ——
    /// 后两块随分段条一起删掉了（这次改动的核心就是**别让骨架盖住半屏**）。
    ///
    /// ⚠️ 四行那一段的形状必须与真实内容**对齐**（`CardBox(vertical: Theme.Spacing.xs)`
    /// + 每行约 42pt）—— 数据到达时整块跳动是最容易被做出来、也最容易被忽略的瑕疵。
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

            CardBox(vertical: Theme.Spacing.xs) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: 11) {
                        SkeletonBar(height: 17, width: 20)
                        SkeletonBar(height: 14, width: 120)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)
                    .padding(.horizontal, Theme.Spacing.xs)
                }
            }
            .padding(.top, Theme.Spacing.m)
        }
        .accessibilityHidden(true)
    }
}
