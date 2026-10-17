import GitDuoAuth
import GitDuoDesign
import SwiftUI

/// 登录门禁 —— 未认证时的**全屏**界面（PRD §4.0.1 / TECH_SPEC §3.8）。
///
/// 铁律：此时**不构建 `TabView`**。否则 Tab 栏会露在登录页下方，
/// 各 Tab 的 `.task` 还会带着空令牌发请求。
struct LoginFlowView: View {

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        switch env.authState {
        case .authenticating:
            AuthorizingView()
        case .unauthenticated, .authenticated:
            LoginFormView()
        }
    }
}

// MARK: - 登录页

private struct LoginFormView: View {

    @Environment(AppEnvironment.self) private var env

    #if DEBUG
    /// 调试入口输入的那枚令牌（见下面 `debugLogin`）。
    ///
    /// ⚠️ 它只是一个**中转格**：真正落盘的是 Keychain（`env.tokenStore`），
    ///    成功之后这个变量就不再被读，页面也随 `authState` 变进去而整体销毁。
    @State private var debugToken = ""
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                hero
                permissionCard
                foot
                #if DEBUG
                debugLogin
                #endif
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.xxl)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
    }

    private var hero: some View {
        VStack(spacing: Theme.Spacing.m) {
            // ⚠️ 品牌标识（GitHub mark）属「发布准备」待补项，与 App 图标同批
            //（`project.yml` 已注明）。此处在补上之前用代码符号占位。
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("GitDuo")
                .font(Theme.Font.largeTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("为 iPhone 打造的 GitHub 客户端\n代码 · Issues · Pull Requests 一站浏览")
                .font(Theme.Font.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.top, Theme.Spacing.l)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("登录后 GitDuo 会申请")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)

            ForEach(AuthPermission.all) { permission in
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        // 「正向」语义 ⇒ `success`（2026-10-17 主色改橙前，它借的是 `accentStrong` 的绿）。
                        .foregroundStyle(Theme.Palette.success)
                        .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(permission.title)
                            .font(Theme.Font.bodyStrong)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(permission.detail)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.l)
        .background(Theme.Palette.surface, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.borderSoft)
        }
    }

    private var foot: some View {
        VStack(spacing: Theme.Spacing.m) {
            Button {
                Task { await env.signIn() }
            } label: {
                Text("使用 GitHub 登录")
                    .font(Theme.Font.bodyStrong)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(!AppConfig.isConfigured)

            if let notice = env.notice {
                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                    Image(systemName: notice.isError ? "exclamationmark.triangle" : "info.circle")
                    Text(notice.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Theme.Font.caption)
                .foregroundStyle(notice.isError ? Theme.Palette.destructive : Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 三句产品承诺走单一数据源（`AuthDisclosure`）：它们必须与实现同时成立，
            // 因此不能是散在这里的三句字面量——那边的单测守着"文案没退回去"。
            VStack(spacing: Theme.Spacing.xs) {
                ForEach(AuthDisclosure.allCases, id: \.self) { disclosure in
                    Text(disclosure.text)
                        .foregroundStyle(disclosure == .installScope
                            ? Theme.Palette.textSecondary
                            : Theme.Palette.textTertiary)
                }
            }
            .font(Theme.Font.caption)
            .multilineTextAlignment(.center)

            if !AppConfig.isConfigured {
                Text("未检测到 client_id / client_secret（Secrets.xcconfig）")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.destructive)
            }
        }
    }

    // MARK: - 调试入口（仅 Debug 编译）

    #if DEBUG
    /// 不走 OAuth、用一枚 Personal Access Token 直接进主界面。
    ///
    /// 为什么代码长这样（逐条都有理由，改动前先读 `AppEnvironment.debugSignIn(withToken:)`）：
    ///
    /// - **长得故意不像产品的一部分**：最小字号、三级文字色、不加卡片、不要主按钮样式。
    ///   它是一个验收用的工具，被误读成"GitDuo 支持用 PAT 登录"才是真的代价。
    /// - **`SecureField` 而不是 `TextField`**：令牌是凭据，不该明文停在输入框里
    ///   （截屏 / 录屏时尤其；这也是 iOS 自己的做法）。
    /// - **成功之后不需要"退出调试态"**：令牌进的是**同一个** Keychain，
    ///   下次冷启动由正常恢复路径放行 —— 从这一格进来的会话与真实登录**没有区别**。
    /// - **不做剪贴板自动读取**：`UIPasteboard` 那条路会在 iOS 16+ 弹一次系统授权框，
    ///   而那个框在"只是想做一次验收"的场合比手动长按粘贴更烦。
    @ViewBuilder
    private var debugLogin: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("调试入口 · 仅 Debug 构建")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)

            SecureField("粘贴 Personal Access Token", text: $debugToken)
                .font(Theme.Font.caption)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .padding(Theme.Spacing.s)
                .background(Theme.Palette.surface, in: .rect(cornerRadius: Theme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .stroke(Theme.Palette.borderSoft)
                }

            Button("用这枚令牌进入") {
                Task { await env.debugSignIn(withToken: debugToken) }
            }
            .font(Theme.Font.caption)
            .disabled(debugToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif
}

// MARK: - 授权中

/// 系统浏览器关闭 → 换令牌 → 写 Keychain 之间的短暂等待态。
///
/// ⚠️ 真正消耗时间的是 `ASWebAuthenticationSession` 那一段，而那时系统浏览器盖在
///    App 上面，用户看到的是 GitHub 的页面 —— 所以这个界面只在**收尾**时露出来，
///    文案必须如实说明此刻在做什么（换令牌、写 Keychain），而不是含糊的"请稍候"。
private struct AuthorizingView: View {

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ProgressView()
                .controlSize(.large)

            Text("正在完成授权…")
                .font(Theme.Font.bodyStrong)
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("已收到回调 \(AppConfig.callbackURL)\n正在用授权码换取令牌并写入 Keychain")
                .font(Theme.Font.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.background)
    }
}
