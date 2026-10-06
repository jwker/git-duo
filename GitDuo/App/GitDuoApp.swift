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
    ///
    /// ⚠️ 本轮 scheme **只服务 OAuth 回调**：非回调 URL 一律丢弃，
    ///    避免公开的 scheme 变成任意深链入口（§3.9 缓解项 6）。
    ///    完整的形状校验（scheme + host + path）在 `AuthCoordinator` 里再做一遍——
    ///    这里只是第一道闸，两道都不算多。
    private func handleCallback(_ url: URL) {
        guard url.scheme == AppConfig.callbackScheme else { return }
        Task { await environment.handleCallback(url) }
    }
}
