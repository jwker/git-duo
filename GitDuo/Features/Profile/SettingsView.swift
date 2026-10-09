import GitHubAPI
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 设置页（PRD §4.20、TECH_SPEC §9.15）。
///
/// 结构（原型 `SCR.settings.render` 逐条）：三个分区 ——
/// 外观（`主题` = `浅色`）· 账户（`GitHub App · {登录名}` = `已授权`；`退出登录`）·
/// 关于（`清除缓存` = `{大小}`；`版本` = `2.0 (1)`）。
///
/// ## ⚠️ 五行的**可点性**是不一样的，而且差别全在"给不给 action"
///
/// | 行 | 动作 |
/// |---|---|
/// | 主题 | **没有**（本期仅浅色，不提供切换器 —— §4.20） |
/// | GitHub App · 账号 | **没有**（它显示的是一个事实） |
/// | 退出登录 | 有 → §5.11 |
/// | 清除缓存 | 有 → 清接口缓存 |
/// | 版本 | **没有** |
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

    // MARK: - 三个分区

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: ProfileCopy.sectionAppearance)
            MenuCard {
                // ⚠️ 纯展示：本期仅浅色（§4.20）。`action` 不给 ⇒ 不是按钮。
                MenuRow(title: ProfileCopy.themeRow, value: ProfileCopy.themeValue)
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: ProfileCopy.sectionAccount)
            MenuCard {
                // 登录名取自 `authState`，**不再打一次 `/user`**（§9.15）。
                MenuRow(title: ProfileCopy.appRow(login: model.login), value: ProfileCopy.authorizationValue)

                MenuRow(
                    title: ProfileCopy.signOutRow,
                    titleTone: .destructive
                ) {
                    model.sheet = .signOut
                }

                // 撤销失败的兜底入口（见类型说明）。⚠️ 它常驻，不是"失败后才出现"。
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

    // MARK: - 动作

    /// 弹层关完之后才做的事（目前只有一件：登出）。
    private func handleSheetDismissal() {
        guard signsOutAfterDismissal else { return }
        signsOutAfterDismissal = false
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
