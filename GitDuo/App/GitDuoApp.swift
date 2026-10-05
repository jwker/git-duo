import SwiftUI

/// App 入口。
///
/// 依据：TECH_SPEC §8.1。
/// - 本轮 scheme **只服务 OAuth 回调**：`onOpenURL` 只保留回调分支，不注册任何深链（§3.9）。
/// - 决策 #3：Liquid Glass 是 iOS 27 的**默认基线**，无需也不应主动"开启"。
@main
struct GitDuoApp: App {

    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .onOpenURL { url in
                    handleCallback(url)
                }
        }
    }

    /// 授权回调入口。
    /// ⚠️ 这里只做**分流**，真正的校验（`state` 一致 → 换令牌）在切片 1 的 `AuthSession` 中实现。
    /// 骨架期必须**明确拒绝**非回调 URL，避免 scheme 变成任意深链入口（§3.9 缓解项 6）。
    private func handleCallback(_ url: URL) {
        guard url.scheme == AppConfig.callbackScheme else { return }
        // 切片 1：把 url 交给 AuthSession.completeAuthorization(with:)
    }
}
