import GitDuoCore
import GitDuoDesign
import SwiftUI

/// 根视图 —— 按认证状态**二分**。
///
/// 依据：TECH_SPEC §8.1 / §3.8。
/// 铁律：`unauthenticated` / `authenticating` 时**不构建 `TabView`**（登录是门禁，不是页面）。
struct RootView: View {

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        content
            // 冷启动恢复凭据（读 Keychain，必要时刷新一次）。只在根视图出现时跑一次。
            .task { await env.bootstrap() }
    }

    @ViewBuilder
    private var content: some View {
        if env.isBootstrapping {
            // 启动那一瞬：既不是登录页也不是主界面。
            // 直接渲染登录页会让已登录用户每次启动都看到一次"闪一下"。
            Theme.Palette.background.ignoresSafeArea()
        } else {
            switch env.authState {
            case .unauthenticated, .authenticating:
                LoginFlowView()
            case let .authenticated(login):
                MainTabView(login: login)
            }
        }
    }
}

#Preview {
    RootView().environment(AppEnvironment(tokenStore: InMemoryTokenStore()))
}
