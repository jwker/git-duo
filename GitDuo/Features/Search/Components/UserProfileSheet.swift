import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 用户资料弹层（PRD §5.10；原型 `openUserSheet`）。
///
/// 结构：标题 `用户` → 头像 52 + 昵称 + `@登录名 · N 个仓库 · M 关注者` → 简介 →
/// `关注` / `查看公开仓库` 两个按钮。
///
/// ## 列表行精简、点开才补全（C 方案）
///
/// 搜索结果的 `UserHit` 只有登录名（`/search/users` 不返回昵称 / 简介 / 人数）。
/// 弹层打开时，用 `LoadUserProfile` 走一次 `GET /users/{login}` 补全；
/// 加载期间先用精简数据（头像 + `@登录名`）占位，失败也保持它 —— 至少呈现得出"这个人是谁"，
/// 不因为补充字段没拿到就整块打不开。
///
/// ## ⚠️ 两个按钮**纯展示、不可点**（2026-10-07 拍板，决策 #46）
///
/// - **关注**：它是**会改变账号状态的写操作**，在落地方案定下来之前不做半截；
/// - **查看公开仓库**：它会造出一条 App 外的路径。
///
/// 照原型**画出来**（含文字），但用 `allowsHitTesting(false)` **而不是** `.disabled`
/// —— 后者会变灰、看起来像"暂时不可用"，而这一层本来就只是呈现"这个人是谁"。
/// 裁据与 §4.13 的 Watch / Fork 同源（见 `RepoHeroCard`）。
///
/// ⚠️ `allowsHitTesting(false)` 挡的是**触摸**；读屏的激活动作绕过命中测试，
/// 所以 `action` 必须是**真的什么都不做**（这里传空闭包，而不是"打算以后补上"的调用）。
/// 同时按先例去掉 `.isButton` trait 并补一句 hint —— 否则读屏用户只会听到
/// 一个点不动的按钮，不知道原因。
///
/// ## 它是弹层内容，不是开关
///
/// 同 `ExploreFilterSheet`：由 `SearchView` 用 `.sheet(item:)` 呈现，
/// 本视图只画内容（`TECH_SPEC §8.4`）。
struct UserProfileSheet: View {

    /// 搜索行给出的精简数据（至少含登录名），作为加载前与失败时的兜底。
    let fallback: UserHit

    /// 点开后补全完整资料的用例。
    let loader: LoadUserProfile

    /// 当前用于渲染的资料；初始值是精简兜底，补全成功后被替换。
    @State private var user: UserHit

    init(fallback: UserHit, loader: LoadUserProfile) {
        self.fallback = fallback
        self.loader = loader
        _user = State(initialValue: fallback)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            bio
            followButton
            publicReposButton

            Spacer(minLength: 0)
        }
        // 8 / 10 / 12 是原型 `.sheet{padding:8px 10px 12px}` 那一族原值。
        .padding(.horizontal, 10)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface)
        .task(id: fallback.login) {
            await loadProfile()
        }
    }

    /// 补全完整资料。失败时保持精简兜底（不抛错、不阻塞弹层）。
    private func loadProfile() async {
        do {
            user = try await loader.load(login: fallback.login)
        } catch {
            // 保持 @State 的初始值（精简兜底）—— 这是"降级呈现"而非"静默失败"，
            // 与 `ToggleStar.initialState` 取不到基准时的处理同源。
        }
    }

    // MARK: - 标题与头部

    private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 原型 `.sheet-title{font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.4px}`.
            Text(SearchCopy.userSheetTitle)
                .font(Theme.Font.sectionLabel)
                .tracking(0.4)
                .foregroundStyle(Theme.Palette.textTertiary)
                .textCase(.uppercase)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, 6)

            HStack(spacing: Theme.Spacing.m) {
                UserAvatar(login: user.login, diameter: UserAvatar.sheetDiameter)

                VStack(alignment: .leading, spacing: 0) {
                    // 昵称为空时退到 `@登录名` —— 原型直接印 `x.n`，
                    // 遇到没填昵称的人会显示 `undefined`（它的演示数据里都有昵称）。
                    Text(user.name ?? user.handle)
                        // 原型 `font-size:16px` ⇒ 本仓最近的一档是 `body`(17)。
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)

                    // ⚠️ 这一句与结果行上的**有意不同**：少了「公开」二字、多了 `@登录名`
                    //    （原型 `openUserSheet` 就是 `@${u} · …`）；`@登录名` 恒在，所以非空。
                    //    两个数拿不到时只显示 handle。
                    Text(user.profileMetaLabel)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.top, 3)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.s)
            // 原型 `padding:2px 8px 10px`。
            .padding(.top, Theme.Spacing.xxs)
            .padding(.bottom, 10)
        }
    }

    /// 简介。**为空时整块不渲染**（原型会把 `undefined` 印出来）。
    @ViewBuilder
    private var bio: some View {
        if let text = user.bio, !text.isEmpty {
            Text(text)
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 两个纯展示按钮

    private var followButton: some View {
        SheetActionButton(
            title: SearchCopy.followAction,
            style: .primary,
            hint: Self.followHint
        )
    }

    private var publicReposButton: some View {
        SheetActionButton(
            title: SearchCopy.publicReposAction,
            style: .ghost,
            hint: Self.publicReposHint
        )
        // 原型两个按钮之间 `margin-top:8px`。
        .padding(.top, Theme.Spacing.s)
    }

    /// 读屏用的原因说明。原型没给这两句（它的按钮是能点的演示），
    /// 按 `RepoHeroCard` 的 `watchHint` / `forkHint` 同一口径补。
    static let followHint = "关注是账号级写操作，落地方案未定，本版本不可用"
    static let publicReposHint = "会打开 App 外的页面，本版本不可用"
}

/// 弹层里的胶囊形按钮（原型 `.btn.primary` / `.btn.ghost`）。
///
/// ```css
/// .btn{border-radius:9px;padding:9px 16px;font-size:13.5px;font-weight:650}
/// .btn.primary{background:var(--green);color:#fff}
/// .btn.ghost{background:var(--chip);color:var(--text)}
/// ```
private struct SheetActionButton: View {

    enum Style {
        case primary
        case ghost

        var background: Color {
            switch self {
            case .primary: Theme.Palette.accentStrong
            case .ghost: Theme.Palette.surfaceSunken
            }
        }

        var foreground: Color {
            switch self {
            case .primary: Theme.Palette.surface
            case .ghost: Theme.Palette.textPrimary
            }
        }
    }

    let title: String
    let style: Style
    let hint: String

    var body: some View {
        Button(action: {
            // ⚠️ 真的什么都不做 —— `allowsHitTesting(false)` 挡不住读屏的激活动作，
            // 留一个空闭包是"这个按钮确实没有行为"的明确表达。
        }) {
            Text(title)
                .font(Theme.Font.footnote.weight(.semibold))
                .foregroundStyle(style.foreground)
                .frame(maxWidth: .infinity)
                // 原型 `padding:11px`（它在这一处覆写了 `.btn` 的 `9px 16px`）。
                .padding(.vertical, 11)
                .background(
                    // 9 是原型原值（`.btn{border-radius:9px}`），4pt 阶里没有这一档。
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(style.background)
                )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(false)
        // 去掉"可点"的语义：它不是暂时不可用，而是这一层根本不该点。
        .accessibilityRemoveTraits(.isButton)
        .accessibilityHint(hint)
    }
}

#Preview {
    @Previewable @State var environment = AppEnvironment()

    VStack(spacing: Theme.Spacing.xl) {
        UserProfileSheet(
            fallback: UserHit(
                login: "dev-j", name: "jiangjiang", bio: "my-git · iOS / SwiftUI 开发",
                publicRepoCount: 3, followerCount: 21
            ),
            loader: environment.userProfile
        )

        // 昵称与简介都缺、两个计数也查不到 ⇒ 三处各退到"不渲染"或"@登录名"。
        UserProfileSheet(
            fallback: UserHit(login: "torvalds"),
            loader: environment.userProfile
        )
    }
    .background(Theme.Palette.background)
}
