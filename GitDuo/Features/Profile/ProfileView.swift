import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 「我的」Tab 根页（PRD §4.17、TECH_SPEC §9.14）。
///
/// 结构（自上而下，顺序即原型 `12-me.js` 的 `SCR.me`）：
/// 大标题「我的」· 个人资料头部（大头像 / 昵称 / `@登录名` / 简介 / 三个统计项）·
/// 贡献热力图卡片 · 菜单卡片一（Star 管理 / 我的收藏 / 我的 PR / 我的 Issue）·
/// 菜单卡片二（设置）。
///
/// ## ⚠️ 切片 1 的那条例外到此结束
///
/// 本页此前整体是骨架屏，只有「退出登录」是真实现 —— 那是为了让 1.8 真机验收的
/// 第 6/7 步（登出 → 回登录页 · GitHub 侧授权记录真的消失）有入口可点。
/// 现在登出有了正规入口（我的 → 设置 → 退出登录，§4.20），
/// 那一行**已迁进 `SettingsView`**，本页的临时实现与注释一并删除。
///
/// ## ⚠️ 三块数据的失败是**分块**的（决策 #76 末句）
///
/// | 块 | 失败时 |
/// |---|---|
/// | 大头像 + `@登录名` | **不会失败** —— 登录名取自 `authState`；头像取不到（或还没加载完）时回落成本机画的首字母块（偏差第 43 条）。这一块**任何情形下都画得出来** |
/// | 昵称 / 简介 | 整行不渲染（PRD §4.17 第 2 条逐字）＋ 头部块内一行灰字 + 重试 |
/// | 三个统计项 | 逐项降级（缺的那项整项不画，**不填 0**） |
/// | 热力图 | 卡片内一行灰字 + 重试 |
///
/// 所以这里**没有"整页失败态"** —— 两个失败块各自带着「重试」出口。
///
/// ## 下拉刷新
///
/// 本页有 `.refreshable`，与**其余每一个取数页**一致（首页 / 仓库 / 探索 / 四个详情页
/// 都挂了它）。⚠️ 原型里一个都没有 —— 它是静态 HTML，没有下拉刷新这回事 ⇒
/// 这是本 App 的**页面级约定**，不是原型的偏离。它顺带把两个失败块的重试
/// 变成"整页重取"，两者走的是同一个 `model.load()`。
struct ProfileView: View {

    /// 登录名。**不可空** —— 它来自 `authState`（`RootView` 只在已认证时才构建主界面），
    /// 也是头像与 `@登录名` 那一行的唯一来源。
    let login: String

    @Environment(AppEnvironment.self) private var env
    @State private var model: ProfileViewModel

    /// 依赖由**组合根**经 `MainTabView` 传下来（同 `HomeView` / `ReposView`），
    /// 本视图与 ViewModel 都不自行构造客户端（AGENTS.md §3）。
    init(login: String, overview: LoadProfileOverview) {
        self.login = login
        // `State(initialValue:)` 只在首次构造时生效 —— 视图重建不会把状态冲掉。
        _model = State(initialValue: ProfileViewModel(loader: overview))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                identityBlock
                heatmapBlock
                    // 原型 `.heatmap{margin:12px 0}`。
                    .padding(.vertical, Theme.Spacing.m)
                menuCards
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        .navigationTitle(ProfileCopy.pageTitle)
        .refreshable { await model.load() }
        .task { await model.loadIfNeeded() }
    }

    // MARK: - 资料头部（头像 / 昵称 / 简介 / 三个统计项）

    @ViewBuilder
    private var identityBlock: some View {
        // ⚠️ `name` / `bio` 传的是 `ProfileOverview` 里那一份（拿不到就是 `nil`）
        //    —— `ProfileHeader` 对 `nil` 与空串的处置都是"整行不渲染"，见它的说明。
        // ⚠️ `avatarURL` 同理：`/user` 那一路失败时它是 `nil` ⇒ 头像回落成首字母块。
        //    **两种情形都不需要额外分支**（把 `nil` 一路传下去就行），
        //    所以这里没有 `if let` —— 一写就变成"两条渲染路径"，而它们该长得一样。
        ProfileHeader(
            login: login,
            name: model.overview?.profile?.name,
            bio: model.overview?.profile?.bio,
            avatarURL: model.overview?.profile?.avatarURL
        )

        ProfileStatBar(stats: statItems)

        // `/user` 那一路失败 ⇒ 在头部块内给一行灰字 + 重试（TECH_SPEC §9.14「两处降级」）。
        // 位置贴着失败的那一块，而不是塞进热力图卡片里 —— 那张卡说的是贡献数据。
        if let error = model.overview?.identity.error {
            SectionFailure(error: error) { Task { await model.load() } }
        }
    }

    /// 三个统计项 —— 顺序与取舍全在领域层（`ProfileStats.items`），这里只翻成设计包要的形状。
    ///
    /// ⚠️ **只有「Star」那一项可点**（原型只给它挂了 `onclick`，另两项是纯展示）——
    /// 走 `action: nil` 而不是 `.disabled`：后者会让它变灰、像"暂时不可用"（决策 #51）。
    private var statItems: [ProfileStatBar.Item] {
        (model.overview?.stats.items ?? []).map { item in
            ProfileStatBar.Item(
                valueText: item.valueText,
                title: item.title,
                action: item.kind == .stars ? { env.router.push(.stars) } : nil
            )
        }
    }

    // MARK: - 贡献热力图

    @ViewBuilder
    private var heatmapBlock: some View {
        if let overview = model.overview {
            switch overview.grid {
            case let .value(grid):
                // ⚠️ 零贡献**不是**失败：那时 `grid` 仍是 `.value`，图照画（全最浅档）。
                //    两种情形在画面上完全不同 —— 这正是 `ProfileSection` 把它们分开的原因。
                ContributionHeatmap(
                    levels: grid.levelMatrix,
                    totalText: ProfileCopy.contributionCount(grid.totalContributions),
                    rangeText: ProfileCopy.contributionRange
                )

            case let .failure(error):
                // 这一张卡是**内容层** ⇒ 实色，不加 Liquid Glass（§10.2）。
                CardBox(vertical: 14) {
                    SectionFailure(error: error) { Task { await model.load() } }
                }
            }
        } else {
            // 首帧：还没取到任何结果 ⇒ 骨架（§8.5：加载中 ≠ 无数据）。
            CardBox(vertical: 14) { skeleton }
        }
    }

    /// 热力图卡片的骨架 —— 照着它的真实布局画那两行（§8.5 第 1 条纪律：尺寸要匹配）。
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部那行：左边「1,024 次贡献」、右边「过去一年」。
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                SkeletonBar(height: 13, width: 104)
                Spacer(minLength: 0)
                SkeletonBar(height: 11, width: 48)
            }
            // 网格：53 列 × 7 行铺满宽度后的高度量得约 44pt（见 `ContributionHeatmap` 的说明）。
            .padding(.bottom, 10)

            SkeletonBar(height: 44)
        }
    }

    // MARK: - 两张菜单卡片

    @ViewBuilder
    private var menuCards: some View {
        // ⚠️ 两行会话的去向是 `.myConversations(kind:)`（TECH_SPEC §8.2）——
        //    与「我的 Star」不同：那一页是**一个**列表，这两项**各是一页**（决策 #73）。
        MenuCard {
            MenuRow(
                systemImage: GitHubIcon.star,
                title: ProfileCopy.menuStars,
                accessory: .chevron
            ) {
                env.router.push(.stars)
            }
            MenuRow(
                systemImage: GitHubIcon.bookmark,
                title: ProfileCopy.menuFolders,
                accessory: .chevron
            ) {
                env.router.push(.folders)
            }
            // 图标取 `StateIcon` 那两个常量（原型 `I.pr` / `I.issueO` 的出处），
            // 不在 `GitHubIcon` 里再抄一份 —— 见那个文件的尾巴。
            MenuRow(
                systemImage: StateIcon.pullRequestOpen,
                title: ProfileCopy.menuPullRequests,
                accessory: .chevron
            ) {
                env.router.push(.myConversations(kind: .pullRequest))
            }
            MenuRow(
                systemImage: StateIcon.issueOpen,
                title: ProfileCopy.menuIssues,
                accessory: .chevron,
                // 最后一行不画分隔线（原型 `.menu-item:last-child{border-bottom:none}`）。
                showsSeparator: false
            ) {
                env.router.push(.myConversations(kind: .issue))
            }
        }
        // 原型 `.menu-card{margin-bottom:12px}`。
        .padding(.bottom, Theme.Spacing.m)

        MenuCard {
            MenuRow(
                systemImage: GitHubIcon.settings,
                title: ProfileCopy.menuSettings,
                accessory: .chevron,
                showsSeparator: false
            ) {
                env.router.push(.settings)
            }
        }
    }
}

#Preview {
    @Previewable @State var environment = AppEnvironment()
    NavigationStack {
        ProfileView(login: "jiangjiang", overview: environment.profileOverview)
    }
    .environment(environment)
}
