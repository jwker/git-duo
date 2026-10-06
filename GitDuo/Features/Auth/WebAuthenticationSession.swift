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
/// 校验 `state`、换令牌、写 Keychain 全在 `GitDuoAuth` 里（那边能跑单测，这边不能）。
@MainActor
final class WebAuthenticationSession: NSObject {

    private var session: ASWebAuthenticationSession?

    /// 打开授权页并等待回调。
    ///
    /// - Throws: 用户取消时为 `ASWebAuthenticationSessionError.canceledLogin`
    ///   （调用方应视为**正常操作**，见 `isUserCancellation(_:)`）；
    ///   其余为真实错误。
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
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
}

enum WebAuthenticationError: Error, LocalizedError {

    /// 系统拒绝启动会话（通常是没有可用的呈现上下文）
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
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first { $0.isKeyWindow }
            ?? scenes.first?.windows.first
            ?? ASPresentationAnchor()
    }
}
