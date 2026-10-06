import AuthenticationServices
import UIKit

/// `ASWebAuthenticationSession` 的薄封装 —— App 层唯一的一处"系统浏览器"胶水。
///
/// 依据：TECH_SPEC §3.1 步骤 3–4。
///
/// 为什么是系统浏览器会话而不是 `WKWebView`（§3.1 步骤 4）：
/// - 用户能看到**真实的地址栏**与证书状态，钓鱼页无处藏身；
/// - 能复用系统里已有的 GitHub 登录态，不必在 App 里再输一次密码
///   （密码因此**从不经过 GitDuo**，这是登录页对用户的承诺）。
///
/// 这一层刻意保持"无逻辑"：它只负责开窗口、把回调 URL 原样交回去。
/// 唯一多出来的一点是**挑一个呈现窗口**（见 `resolvePresentationAnchor`）——那仍属"开窗口"本身。
/// 校验 `state`、换令牌、写 Keychain 全在 `GitDuoAuth` 里（那边能跑单测，这边不能）。
@MainActor
final class WebAuthenticationSession: NSObject {

    private var session: ASWebAuthenticationSession?

    /// 已解析的呈现锚点 —— `authenticate` 在 `start()` 之前填好（见 `resolvePresentationAnchor`）。
    private var anchor: ASPresentationAnchor?

    /// 打开授权页并等待回调。
    ///
    /// - Throws: 用户取消时为 `ASWebAuthenticationSessionError.canceledLogin`
    ///   （调用方应视为**正常操作**，见 `isUserCancellation(_:)`）；
    ///   其余为真实错误。
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        // 先解析"从哪个窗口弹出来"。取不到就**不必启动** —— 系统那条路只会回
        // `presentationContextInvalid`，而且文案是系统串，不如我们自己提前失败。
        guard let anchor = Self.resolvePresentationAnchor() else {
            throw WebAuthenticationError.cannotStart
        }
        self.anchor = anchor

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? WebAuthenticationError.cannotStart)
                }
            }
            session.presentationContextProvider = self
            // ⚠️ `false` = **复用**系统里已有的 GitHub 登录态。
            //    改成 `true`（临时会话）会让每次登录都要重新输账号密码——
            //    看似"更安全"，实际是把用户推向"用更简单的密码"。
            session.prefersEphemeralWebBrowserSession = false
            self.session = session

            if !session.start() {
                continuation.resume(throwing: WebAuthenticationError.cannotStart)
            }
        }
    }

    /// 该错误是否只是"用户点了取消"——是的话不该报错，回登录页即可（§3.8 出口表）。
    static func isUserCancellation(_ error: any Error) -> Bool {
        (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
            || error is CancellationError
    }

    // MARK: - 呈现锚点

    /// 解析"从哪个窗口弹出授权页"；解析不到返回 `nil`。
    ///
    /// ⚠️ **不要退回 `UIWindow()`**：iOS 26 起它已废弃，而且它**本来就不合用**——
    /// - `windowScene` 为 nil 时 *"window will not appear on any screen"*（`UIWindow.h`）；
    /// - 系统要求锚点窗口必须**处于前台场景**：`presentationContextInvalid` 的文档原话是
    ///   *"For iOS, validate that the UIWindow is in a foreground scene"*。
    ///
    /// 也就是说"没有场景就造一个窗口"这条路**结构上不可能被系统接受**，走到它登录必然失败。
    /// 因此末路改为"挂到某个场景上新建窗口"，它仍是一个合法锚点。
    private static func resolvePresentationAnchor() -> ASPresentationAnchor? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard !scenes.isEmpty else { return nil }

        let foreground = scenes.filter { $0.activationState == .foregroundActive }
        // 1) 前台场景里的 key window —— 最理想
        if let window = foreground.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
        // 2) 任意场景里的 key window（App 瞬时 inactive 时，这个才是对的窗口）
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
        // 3) 前台场景里的任意窗口
        if let window = foreground.first?.windows.first { return window }
        // 4) 场景连一个窗口都没有（极早期）：挂到场景上新建一个
        return scenes.first.map { ASPresentationAnchor(windowScene: $0) }
    }
}

enum WebAuthenticationError: Error, LocalizedError {

    /// 系统拒绝启动会话（通常是没有可用的呈现上下文）；
    /// 也在**我们自己**解析不到呈现锚点窗口时抛出（见 `resolvePresentationAnchor`）。
    case cannotStart

    var errorDescription: String? {
        switch self {
        case .cannotStart:
            "无法打开 GitHub 登录页面，请稍后重试"
        }
    }
}

extension WebAuthenticationSession: ASWebAuthenticationPresentationContextProviding {

    /// 会话需要知道"从哪个窗口弹出来"。
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let anchor { return anchor }
        if let resolved = Self.resolvePresentationAnchor() { return resolved }
        // 绊线：`authenticate` 在 `start()` 之前已保证锚点非 nil，这里不该被走到。
        preconditionFailure("没有可用的窗口场景，不应启动登录会话")
    }
}
