import SwiftUI
import GitDuoDesign

/// 根视图 —— 按认证状态**二分**。
///
/// 依据：TECH_SPEC §8.1 / §3.8。
/// 铁律：`unauthenticated` / `authenticating` 时**不构建 `TabView`**（登录是门禁，不是页面）。
struct RootView: View {

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        switch env.authState {
        case .unauthenticated, .authenticating:
            LoginFlowPlaceholder()
        case let .authenticated(login):
            MainTabView(login: login)
        }
    }
}

/// ⚠️ 登录流程占位 —— **切片 1 用真实的 `LoginFlowView` 替换整个类型**。
/// 现在只提供"进入主界面"的临时通道，让主界面骨架可被检视。
private struct LoginFlowPlaceholder: View {

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)

            Text("GitDuo")
                .font(Theme.Font.largeTitle)
                .foregroundStyle(Theme.Palette.textPrimary)

            Text("登录流程 · 切片 1 落地")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)

            Text("PRD §4.0 / TECH_SPEC §3.1 · §3.8")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)

            if !AppConfig.isConfigured {
                Text("未检测到 client_id（Secrets.xcconfig）")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.destructive)
            }

            // ⚠️ 临时通道：切片 1 完成后删除
            Button("跳过登录（骨架期临时）") {
                env.debugBypassLogin()
            }
            .buttonStyle(.glass)
            .padding(.top, Theme.Spacing.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.background)
    }
}

#Preview {
    RootView().environment(AppEnvironment())
}
