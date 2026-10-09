import GitHubAPI
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 设置页（PRD §4.20、TECH_SPEC §9.15）。
///
/// 结构（原型 `SCR.settings.render` 逐条 + 偏差第 46 条）：三个分区，**外加末尾一张独立卡片** ——
/// 外观（`主题` = `浅色`）· 账户（`GitHub App · {登录名}` = `已授权`；`前往 GitHub 手动撤销授权`）·
/// 关于（`清除缓存` = `{大小}`；`版本` = `2.0 (1)`）· **最底部**：`退出登录`
/// （单独一张卡片、**不带分区标题** —— 见 `signOutSection`）。
///
/// ## ⚠️ 六行的**可点性**是不一样的，而且差别全在"给不给 action"
///
/// | 行 | 动作 |
/// |---|---|
/// | 主题 | **没有**（本期仅浅色，不提供切换器 —— §4.20） |
/// | GitHub App · 账号 | **没有**（它显示的是一个事实） |
/// | 前往 GitHub 手动撤销授权 | 有 → 开浏览器 |
/// | 清除缓存 | 有 → 清接口缓存 |
/// | 版本 | **没有** |
/// | 退出登录 | 有 → §5.11；**在途时不给**（`signOutSection`） |
///
/// 不给动作的行**不是 `.disabled`**：那会把它变灰、看起来像"暂时不可用"，
/// 而它们本来就只是事实（决策 #51）。
///
/// ## ⚠️ 「退出登录」是**从这里**进来的（切片 1 的例外到此结束）
///
/// 它此前临时挂在「我的」页上 —— 那是为了让 1.8 真机验收的第 6/7 步
/// （登出 → 回登录页 · GitHub 侧授权记录真的消失）有入口可点，
/// 而原型里登出走的就是「我的 → 设置 → 退出登录」。现在那一行迁到这里，
/// 并**连同确认弹层一起**（§5.11）。
///
/// ⚠️ 有意**多出**一行「前往 GitHub 手动撤销授权」：原型与 PRD §4.20 的表里都没有它，
/// 但 PRD §5.11 末句逐字写着「**设置页保留手动撤销入口**」、TECH_SPEC §3.6 与 §9.15
/// 同样要求，而 `ProfileCopy.signOutDegradedNotice` 那句降级提示就点名"可在设置中手动撤销"
/// —— 那一句是给**撤销失败**的人看的，而登出之后人已经在登录页上了，
/// 所以这个入口**只能常驻**（不能等失败时才出现）。缺了它，那句提示就是一句空头承诺
/// （`AGENTS.md §5` 点名的那类问题：文案不得承诺实现做不到的事）。
struct SettingsView: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL

    @State private var model: SettingsViewModel

    /// 「弹层关完之后才登出」的标记。
    ///
    /// ⚠️ **不能在确认按钮里直接 `await env.signOut()`**：登出会把 `authState`
    /// 打回未认证 ⇒ `RootView` 整个换掉主界面，而本页（连同挂在它身上的弹层）
    /// 就在那棵即将消失的树上 —— 表现是"弹层被突然掀掉"。
    /// 所以先记标记、把弹层关掉，等 `.sheet(onDismiss:)` 真的走完再登出
    /// （同 `FileView` 那条"弹层关完才 pop"的先例）。
    @State private var signsOutAfterDismissal = false

    /// 登出**在途**（最底下那一行右侧的 `正在退出…` 靠它，决策 #78）。
    ///
    /// ⚠️ **它与上面那个标记是两件事，别合并**：`signsOutAfterDismissal` 管的是
    /// "**等弹层关掉**"（闸门，关完才动手），本标记管的是"**已经动手了、还没走完**"
    /// （等待期反馈）。两者之间正好隔着一个 `.sheet(onDismiss:)`。
    ///
    /// ⚠️ 放视图的 `@State`、**不进 `SettingsViewModel`**：它只在这一屏活一次，
    /// 而这一屏**必然以"被登录页替换"告终**（`signOut()` 不抛错，最差也是降级完成）
    /// ⇒ 不需要重置逻辑，也没有可测的领域数据要交给 ViewModel。
    @State private var isSigningOut = false

    init(login: String, cache: HTTPResponseCache, toast: ToastCenter) {
        _model = State(initialValue: SettingsViewModel(
            login: login,
            cache: cache,
            toast: toast
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                appearanceSection
                accountSection
                aboutSection
                signOutSection
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        .navigationTitle(ProfileCopy.settingsTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 这一页唯一的活数据就是那个缓存大小，而它要遍历磁盘目录（决策 #75 末段）
        // ⇒ 只在进页与下拉时量。
        .refreshable { await model.loadCacheSize() }
        .task { await model.loadCacheSize() }
        .sheet(item: $model.sheet, onDismiss: handleSheetDismissal) { route in
            switch route {
            case .signOut:
                SignOutConfirmSheet {
                    // ① 记下"要登出" ② 关弹层（等价于点遮罩关闭）。
                    //    **不在这里 await** —— 见 `signsOutAfterDismissal` 的说明。
                    signsOutAfterDismissal = true
                    model.sheet = nil
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - 三个分区 + 末尾那张独立卡片

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: ProfileCopy.sectionAppearance)
            MenuCard {
                // ⚠️ 纯展示：本期仅浅色（§4.20）。`action` 不给 ⇒ 不是按钮。
                MenuRow(title: ProfileCopy.themeRow, value: ProfileCopy.themeValue)
            }
        }
    }

    /// 「账户」分区 —— ⚠️ **「退出登录」已经不在这一张卡片里**（搬去了 `signOutSection`）。
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: ProfileCopy.sectionAccount)
            MenuCard {
                // 登录名取自 `authState`，**不再打一次 `/user`**（§9.15）。
                MenuRow(title: ProfileCopy.appRow(login: model.login), value: ProfileCopy.authorizationValue)

                // 撤销失败的兜底入口（见类型说明）。⚠️ 它**常驻**，不是"失败后才出现"。
                // ⚠️ 它**不跟着「退出登录」搬走**（决策 #78）：两者语义虽相连，但这个是**兜底**
                //    （只有撤销失败的人才用），与"登出"这个主动作分开摆更接近它本来的位置。
                // ⚠️ 现在**它是本卡片最后一行** ⇒ 分隔线交给它关掉
                //    （原型 `.menu-item:last-child{border-bottom:none}`）——
                //    这条规则只认"谁在最后"，与谁搬去别处无关。
                MenuRow(
                    title: ProfileCopy.manualRevokeAction,
                    showsSeparator: false
                ) {
                    openManualRevoke()
                }
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: ProfileCopy.sectionAbout)
            MenuCard {
                MenuRow(
                    title: ProfileCopy.clearCacheRow,
                    // ⚠️ 还没量过时**不画值**（`nil` ⇒ 右侧什么都没有），
                    //    不是画一个 `0.0 MB` —— "还没量"与"确实是零"是两件事。
                    value: model.cacheBytes.map { ProfileCopy.cacheSize(bytes: $0) }
                ) {
                    Task { await model.clearCache() }
                }

                MenuRow(
                    title: ProfileCopy.versionRow,
                    value: model.versionText,
                    showsSeparator: false
                )
            }
        }
    }

    /// 末尾那一张**独立卡片**：退出登录（2026-10-09 用户走查裁定 · 决策 **#78** · 偏差第 **46** 条）。
    ///
    /// ## ⚠️ 它在最底部、**没有分区标题**，与上面隔开
    ///
    /// 原型把它排在「账户」分区里（`GitHub App · {账号}` 的下一行，`SCR.settings.render`）；而它是本页
    /// **唯一不可逆、且会撤销 GitHub 侧授权**的动作 ⇒ 与一列设置项隔开、摆到最下方，
    /// 免得在一列长得一样的行里被误点。
    ///
    /// **为什么不给它一个 `SectionHeader`**：原型那三个标题（外观 / 账户 / 关于）没有一个装得下它 ——
    /// 「账户」已经归上面那张卡片，而"登出"不是一个分类、是一个动作。
    /// ⚠️ 代价如实登记：PRD 那句"三个分区"由此变成"三分区 + 一张无标题卡片"（偏差第 46 条）。
    ///
    /// ⚠️ **上边距要自己补**：分区之间那 16pt 是 `SectionHeader` 的 `margin:16px 2px 8px` 给的，
    /// 而本张卡片没有标题 ⇒ 不补的话它会**贴着「关于」那张卡片**，看起来像"关于"分区里的一行 ——
    /// 正好把这处改动想表达的"隔开"抹掉（**屏幕上看着仍然很正常**，所以这类漏补只有对着原型才发现）。
    private var signOutSection: some View {
        MenuCard {
            // ⚠️ 在途**不给 `action`**（而不是 `.disabled`）：`MenuRow` 在 `action == nil` 时
            //    **根本不画成 `Button`**（决策 #51）⇒ 既不可点、也不会变灰；
            //    变灰会看起来像"这个功能坏了"，而此刻它只是"正在做"。
            let open: (() -> Void)? = isSigningOut ? nil : { model.sheet = .signOut }

            MenuRow(
                title: ProfileCopy.signOutRow,
                // ⚠️ 在途时说一句 `正在退出…`（决策 #78）：登出期间这一页**只剩这一行是活的**，
                //    而 `MenuRow` 本来就有一个右侧值位（`浅色` / `已授权` / `12.4 MB` 都在那儿）
                //    ⇒ 零新形态、页面结构一点不动。
                value: isSigningOut ? ProfileCopy.signingOutValue : nil,
                titleTone: .destructive,
                // ⚠️ 它是本卡片**唯一的一行**（也就是最后一行）⇒ 按原型
                //    `.menu-item:last-child{border-bottom:none}` 把线关掉；
                //    不关的话卡片底边上方会多出一条线，看着像"下面还有内容"。
                showsSeparator: false,
                action: open
            )
        }
        .padding(.top, Theme.Spacing.l)
    }

    // MARK: - 动作

    /// 弹层关完之后才做的事（目前只有一件：登出）。
    private func handleSheetDismissal() {
        guard signsOutAfterDismissal else { return }
        signsOutAfterDismissal = false
        // 弹层**真的关完了** ⇒ 现在才轮到"正在退出"这句话（决策 #78）：
        // 在那之前弹层还盖在屏幕上，说了也看不见。
        isSigningOut = true
        Task { await env.signOut() }
    }

    /// 打开 GitHub 的授权管理页（`TECH_SPEC §3.6` 给了完整地址）。
    ///
    /// ⚠️ 与「Revert」「置顶管理」那几处不同，这里**先不弹提示**：
    /// 那些地方要先解释"为什么这件事在 App 里做不到"，而本行的标题已经是一句
    /// 完整的动作说明（「前往 GitHub 手动撤销授权」）—— 再弹一句就是重复。
    /// 同 `ExploreRepoDetailView.releaseButton` 的处置（直接开浏览器、不预告）。
    private func openManualRevoke() {
        guard let url = Self.manualRevokeURL else { return }
        openURL(url)
    }

    /// GitHub 侧的授权记录在哪 —— `github.com/settings/apps/authorizations`
    /// （TECH_SPEC §3.6 逐字给出的地址）。
    ///
    /// ⚠️ 路径是 `/settings/apps/authorizations`（**Apps 下**那一页）。
    /// 写成 `/settings/authorizations` 会落到另一页（那里管的是 classic OAuth App
    /// 的授权），用户会**找不到本 App 的记录**、并在网页上以为"撤销成功了"。
    private static let manualRevokeURL = URL(string: "https://github.com/settings/apps/authorizations")
}

#Preview {
    @Previewable @State var environment = AppEnvironment()

    NavigationStack {
        SettingsView(
            login: "jiangjiang",
            cache: environment.responseCache,
            toast: environment.toast
        )
    }
    .environment(environment)
}
