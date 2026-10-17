import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 「我的」Tab 根页（PRD §4.17、TECH_SPEC §9.14）。
///
/// 结构（自上而下，顺序即原型 `12-me.js` 的 `SCR.me`）：
/// 大标题「我的」· 个人资料头部（大头像 / 昵称 / `@登录名` / 简介 / 三个统计项）·
/// 贡献热力图卡片 · 三个入口行（我的 Star / 我的 PR / 我的 Issue）· 设置行。
/// （首条原型逐字「Star 管理」，2026-10-15 起改名，走查第 71 条。）
///
/// ## ⚠️ 2026-10-16 起主干是 **`List`**（NATIVE-MIGRATION P3 第二批）
///
/// 从前是 `ScrollView + VStack` + 两张 `MenuCard`（行自己画内边距与内嵌 hairline）。
/// 现在四组各是一个 `Section`：分隔线、行内边距、卡面与圆角全部由系统给，
/// `MenuRow` 只画内容（`showsSeparator` 随之删除）。
///
/// ⚠️ 两条**有意保留**的自定观感（属 P5 令牌收尾）：页面底 `Theme.Palette.background`、
///    行底 `Theme.Palette.surface`（`.scrollContentBackground(.hidden)` 让开系统底色）。
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
/// 变成"整页重取"，两者走的是同一个 `model.refresh()`（**取的是当前屏幕上那一年**）。
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
        List {
            // ⚠️ 头部那两块（大头像 / 昵称 / 简介 与 三个统计项）**是同一组内容**
            //    ⇒ 坐同一个 `Section` 的**一行**：它们之间不该有一条分隔线
            //    （那条线会把它切成"两条记录"）。
            Section {
                identityBlock
            }

            // 热力图：它自己就是那张面板（`ContributionHeatmap` 自带底与圆角）
            // ⇒ 行底透明、不画分隔线，免得出现"卡里套卡"。
            Section {
                heatmapBlock
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                menuRows
            }

            Section {
                settingsRow
            }
        }
        .listStyle(.insetGrouped)
        // 主题的页面底 / 行底不交给系统（P5 才动令牌）—— 只把 `List` 自带的底色让开。
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.background)
        .navigationTitle(ProfileCopy.pageTitle)
        .refreshable { await model.refresh() }
        .task { await model.loadIfNeeded() }
    }

    // MARK: - 资料头部（头像 / 昵称 / 简介 / 三个统计项）

    /// ⚠️ 三块必须坐**同一行**：`List` 的 `Section` 里每多一个子视图就多一行，
    ///    而"头像 / 昵称 / 简介"与"三个统计项"中间**不该有一条分隔线**
    ///    （那条线会把一个人切成两条记录）⇒ 用一个 `VStack` 合成一行。
    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                SectionFailure(error: error) { Task { await model.refresh() } }
            }
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
                    // 月份表头 = 领域层给的"第几列 + 几月" × 文案层的"1月"（文案是契约）。
                    monthMarks: grid.monthLabels.map {
                        ContributionHeatmap.MonthMark(
                            column: $0.column,
                            title: ProfileCopy.monthLabel($0.month)
                        )
                    },
                    // ⚠️ 年份与总数**必须来自同一份数据**（`overview.year`，不是"用户刚点的那一年"）
                    //    —— 否则切换的那一瞬间屏幕上会出现"写着 2025、画着 2026"。
                    yearTitle: overview.year.label,
                    yearOptions: yearOptions,
                    selectedYear: overview.year.year,
                    // 在途（切年份 / 重试 / 下拉刷新）⇒ 年份标签左边那枚小转圈
                    // （2026-10-12 加，走查第 61 条的后半：那半个往返本来是**没有任何
                    // 反馈**的，用户看不出自己是点上了还是点空了）。
                    // ⚠️ 已有内容时**不换骨架**（§8.5"不遮挡已有内容"）：在途那一段画的
                    //    仍是上一次拿到的那一年，转圈只交代"还有一次没回来"。
                    isLoading: model.isLoading,
                    yearAccessibilityLabel: ProfileCopy.heatmapYearAccessibilityLabel(
                        year: overview.year.year
                    ),
                    onSelectYear: select(year:)
                )

            case let .failure(error):
                // 这一张卡是**内容层** ⇒ 实色，不加 Liquid Glass（§10.2）。
                PanelBox(vertical: 14, horizontal: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        // ⚠️ 失败态**也要有年份切换器**：这一年的数取不到时，用户要做的
                        //    第一件事就是切回能看的那一年（或换个年份再试）。
                        //    没有它，卡片就成了一堵没有出口的墙（`HeatmapHeader` 的说明）。
                        HeatmapHeader(
                            // `nil`（不是 `0 次贡献`）：没拿到 ≠ 这一年没有贡献。
                            totalText: nil,
                            yearTitle: overview.year.label,
                            yearOptions: yearOptions,
                            selectedYear: overview.year.year,
                            // 失败态**同样要有在途反馈**：按了下面那行「重试」之后，
                            // 这一行本来也是"按了没动静"的（同第 61 条后半的理由）。
                            isLoading: model.isLoading,
                            yearAccessibilityLabel: ProfileCopy.heatmapYearAccessibilityLabel(
                                year: overview.year.year
                            ),
                            onSelectYear: select(year:)
                        )
                        SectionFailure(error: error) { Task { await model.refresh() } }
                    }
                }
            }
        } else {
            // 首帧：还没取到任何结果 ⇒ 骨架（§8.5：加载中 ≠ 无数据）。
            // ⚠️ 外面**不再包 `PanelBox`**（NATIVE-MIGRATION P1）：骨架画的是
            //    `ContributionHeatmap` 本人，而它**自己就是那张面板**（见它的类型说明）
            //    —— 再包一层会得到"两层底 + 双份内边距"。
            skeleton
        }
    }

    /// 年份切换器的选项（领域层的年份 × 文案层的 `{年份} 年`）。
    private var yearOptions: [HeatmapYear] {
        model.years.map { HeatmapYear(year: $0.year, title: $0.label) }
    }

    /// 选了某一年 —— 把设计包那个 `Int` 换回领域层的 `ContributionYear`。
    ///
    /// ⚠️ 跨包只走基础类型（设计包不认识领域包），所以这一层转换必须在这里做，
    /// 而且只有这一处：`HeatmapYear.year` 与 `ContributionYear.year` 是同一个数。
    private func select(year: Int) {
        Task { await model.select(year: ContributionYear(year: year)) }
    }

    /// 热力图卡片的骨架 —— **就是真实的 `ContributionHeatmap`**（NATIVE-MIGRATION P1）。
    ///
    /// ⚠️ 上面那段"网格高度必须从 `ContributionHeatmap.gridHeight` 取"的注释随之作废：
    /// 现在画出来的网格**就是**那一份网格（`Placeholders.heatmapLevels()` 给一个
    /// 53 列 × 7 行的最浅档矩阵），高度不可能对不上 —— 那正是当年写死旧值翻车的根因。
    ///
    /// ⚠️ `totalText` 不写 `0 次贡献`（同失败态那条）：骨架期是"还没拿到"，
    /// 不是"这一年确实零贡献"。redacted 之下看不见，但口径不能反。
    ///
    /// ⚠️ 月份标签按"每个月大约隔 4.35 列"摆一个：真实标签来自 `grid.monthLabels`，
    /// 占位只要**形状**（一行字摊在旁边）对得上就够。
    private var skeleton: some View {
        ContributionHeatmap(
            levels: Placeholders.heatmapLevels(),
            totalText: ProfileCopy.contributionCount(0),
            monthMarks: (1...12).map {
                ContributionHeatmap.MonthMark(
                    column: Int(Double($0 - 1) * 4.35),
                    title: ProfileCopy.monthLabel($0)
                )
            },
            // 年份选项在首帧可能还没取到（`model.years` 为空）⇒ 占位给一档，
            // 免得切换器画成一个空菜单。
            yearTitle: model.years.first?.label ?? Placeholders.shortLine,
            yearOptions: yearOptions.isEmpty
                ? [HeatmapYear(year: 0, title: Placeholders.shortLine)]
                : yearOptions,
            selectedYear: model.years.first?.year ?? 0,
            isLoading: false,
            yearAccessibilityLabel: "",
            onSelectYear: { _ in }
        )
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - 入口行（从前是两张菜单卡片）

    /// 三个入口行（我的 Star / 我的 PR / 我的 Issue）。
    ///
    /// ⚠️ 两行会话的去向是 `.myConversations(kind:)`（TECH_SPEC §8.2）——
    ///    与「我的 Star」不同：那一页是**一个**列表，这两项**各是一页**（决策 #73）。
    ///
    /// ⚠️ 2026-10-16 起它们就是 `List` 的行（NATIVE-MIGRATION P3 第二批）：
    ///    分隔线**由系统画**，"首行关掉线"那一条（`showsSeparator`）随 `MenuRow`
    ///    的瘦身一并作废 —— 系统对"谁是首行"有确定的答案。
    @ViewBuilder
    private var menuRows: some View {
        // 图标色档照原型 `12-me.js` 的 `--ic`（方案 D，走查第 73 条）：
        // Star 金 / PR 与收藏链接蓝 / Issue 绿 / 设置缺省灰。
        MenuRow(
            systemImage: GitHubIcon.star,
            iconTone: .gold,
            title: ProfileCopy.menuStars,
            accessory: .chevron,
            showsSeparator: false
        ) {
            env.router.push(.stars)
        }

        // 图标取 `StateIcon` 那两个常量（原型 `I.pr` / `I.issueO` 的出处），
        // 不在 `GitHubIcon` 里再抄一份 —— 见那个文件的尾巴。
        MenuRow(
            systemImage: StateIcon.pullRequestOpen,
            iconTone: .blue,
            title: ProfileCopy.menuPullRequests,
            accessory: .chevron,
            showsSeparator: false
        ) {
            env.router.push(.myConversations(kind: .pullRequest))
        }

        MenuRow(
            systemImage: StateIcon.issueOpen,
            iconTone: .green,
            title: ProfileCopy.menuIssues,
            accessory: .chevron,
            showsSeparator: false
        ) {
            env.router.push(.myConversations(kind: .issue))
        }
    }

    /// 「设置」那一行 —— 它**单独一个 `Section`**（从前是"末尾一张独立卡片"）：
    /// 与三个入口隔开，是"设置不是这一组里的第四项"的意思。
    private var settingsRow: some View {
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

#Preview {
    @Previewable @State var environment = AppEnvironment()
    NavigationStack {
        ProfileView(login: "jiangjiang", overview: environment.profileOverview)
    }
    .environment(environment)
}
