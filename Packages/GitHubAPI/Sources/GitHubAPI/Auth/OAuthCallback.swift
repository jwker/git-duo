import Foundation

/// 授权回调的解析与校验 —— 纯逻辑，不碰网络、不碰 UI。
///
/// 依据：TECH_SPEC §3.1 步骤 5、§3.8（取消与失败出口表）、§3.9（回调与 scheme 安全）、
///      §12.2（「授权回调校验」测试项）。
///
/// ⚠️ 三条语义必须分清（"不能把正常操作当错误报"）：
/// 1. **不是我们的回调** → `ignored`：**静默丢弃、不改任何状态**。
///    scheme 一旦发布就成为公开契约，任何人都能往它投递 URL（§3.9 场景 B）——
///    对不认识的 URL 报错，等于把 scheme 变成骚扰入口。
/// 2. **用户取消** → `cancelled`：属正常操作，回登录页且**不报错、不写任何凭据**（§3.8 出口表）。
/// 3. **校验失败** → `failed`：state 不匹配 / 缺参数 —— 必须丢弃该次 `code` 并回登录页提示。
///
/// ⚠️ `state` 是**一次性**的：调用方在收到 `authorized` 后必须**立即**清掉期望值，
///    这样同一授权码的二次投递（重复回调）会自然落到 `.stateMismatch`。
public enum OAuthCallback {

    /// 回调 URL 的形状。
    ///
    /// ⚠️ 注意 `gitduo://oauth/callback` 的真实解析结果：`scheme = gitduo`、
    ///    **`host = oauth`**、`path = /callback` —— 中间那段是 authority 而不是路径前缀。
    ///    只比 `path` 会漏掉 `gitduo://evil/callback` 这类伪装。
    public struct Shape: Sendable, Equatable {
        public let scheme: String
        public let host: String
        public let path: String

        public init(scheme: String, host: String, path: String) {
            self.scheme = scheme
            self.host = host
            self.path = path
        }

        /// `gitduo://oauth/callback`（§3.7 决策：注册后即对外契约）
        public static let gitduoCallback = Shape(scheme: "gitduo", host: "oauth", path: "/callback")
    }

    public enum FailureReason: Sendable, Equatable {
        /// 回调带回的 `state` 与本地暂存值不一致（或本地根本没有等待中的授权）
        case stateMismatch
        case missingCode
        case missingState
        /// GitHub 返回了 `error=…`（非 `access_denied`，例如 `bad_verification_code`）
        case serviceError(code: String, description: String?)
    }

    public enum Outcome: Sendable, Equatable {
        case authorized(code: String)
        case cancelled
        case ignored
        case failed(FailureReason)
    }

    /// 解析并校验回调。
    ///
    /// - Parameter expectedState: 发起授权时暂存的 `state`；**没有等待中的授权时传 `nil`**，
    ///   此时任何回调都会落到 `.failed(.stateMismatch)`。
    public static func resolve(
        _ url: URL,
        expectedState: String?,
        shape: Shape = .gitduoCallback
    ) -> Outcome {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .ignored
        }

        // ① 形状校验：scheme / host / path 任一不符 ⇒ 不是给我们的，静默丢弃
        //    （scheme 大小写不敏感；host 同理）
        guard components.scheme?.lowercased() == shape.scheme.lowercased(),
              (components.host ?? "").lowercased() == shape.host.lowercased(),
              components.path == shape.path
        else {
            return .ignored
        }

        let queryItems = components.queryItems ?? []

        /// - Parameter formDecoded: 是否补做 `+` → 空格（见下方说明）。
        func value(_ name: String, formDecoded: Bool = false) -> String? {
            guard let raw = queryItems.first(where: { $0.name == name })?.value, !raw.isEmpty else {
                return nil
            }
            // ⚠️ OAuth 回调的参数按 `application/x-www-form-urlencoded` 编码（RFC 6749 §4.1.2），
            //    其中 `+` 表示空格；而 `URLComponents` 只做百分号解码、**不**处理 `+`。
            //    不补这一步，用户会看到 `The+user+denied+the+request` 这种原文。
            // ⚠️ 只对**展示类字段**补：`code` / `state` 是不透明标识，若其中真的含 `+`
            //    （由 `%2B` 解码而来），改写会破坏 `state` 匹配。
            return formDecoded ? raw.replacingOccurrences(of: "+", with: " ") : raw
        }

        // ② 失败分支：GitHub 用 error 参数回传拒绝 / 失败
        if let error = value("error", formDecoded: true) {
            if error == "access_denied" {
                return .cancelled          // 用户取消，不是错误
            }
            return .failed(.serviceError(
                code: error,
                description: value("error_description", formDecoded: true)
            ))
        }

        // ③ 成功分支：必须同时有 code 与 state
        guard let code = value("code") else { return .failed(.missingCode) }
        guard let state = value("state") else { return .failed(.missingState) }

        // ④ 一次性 state 校验（常量时间比较，见 PKCE.isValidCallbackState）
        guard PKCE.isValidCallbackState(state, expected: expectedState) else {
            return .failed(.stateMismatch)
        }

        return .authorized(code: code)
    }
}
