import Foundation

/// GitHub App 的 OAuth 客户端 —— 只负责**网络**，不含任何编排或状态。
///
/// 依据：TECH_SPEC §3.1（授权流程步骤 3 / 6）、§3.2（刷新）、§3.6（撤销）、决策 #30。
///
/// 职责边界（有意收窄）：
/// - 本类型**不管** `code_verifier` / `state` 的生成与暂存（那是 `PKCE` 与上层编排的事）；
/// - 本类型**不管** Keychain、不管刷新时机、不管 single-flight —— 这些属于编排层；
/// - 本类型**不读全局配置**，凭据一律由构造时注入（见 `GitHubAppCredentials`）。
///
/// ⚠️ `client_secret` 只出现在本文件的三条请求里（换令牌 / 刷新 / 撤销）。
///    它**不得**进入日志、崩溃上报或任何缓存 —— 后一条由「本类型自带不挂 `URLCache` 的会话」
///    结构性保证（见 `makeTokenSession`），而不是靠请求头。
public struct GitHubOAuthClient: Sendable {

    public let credentials: GitHubAppCredentials

    /// internal（而非 private）：供测试断言"默认会话**没有**缓存"。
    let session: URLSession

    /// - Parameter session: 仅测试需要注入桩件（`StubURLProtocol`）。
    ///   **默认不是 `URLSession.shared`**：共享会话带磁盘缓存，会把令牌响应写到
    ///   `Library/Caches/<bundle-id>/Cache.db`（真机实测，2026-10-06）。
    public init(credentials: GitHubAppCredentials, session: URLSession? = nil) {
        self.credentials = credentials
        self.session = session ?? Self.makeTokenSession()
    }

    /// 令牌专用会话：**`urlCache = nil`** ⇒ 任何响应都无从落盘。
    ///
    /// 依据：TECH_SPEC §3.1 / §3.7 —— `client_secret` 与令牌响应不得进入任何缓存。
    /// ⚠️ 光设 `URLRequest.cachePolicy` **不够**：默认策略下 `URLCache` 仍会把响应存下来，
    ///    所以"不挂缓存"必须落在会话上；`cachePolicy` 只是第二道（见 `makeFormRequest`）。
    ///    配置本体收在 `GitHubURLSession.noCache()` —— 与 API 会话共用一份，避免两处漂移。
    private static func makeTokenSession() -> URLSession {
        GitHubURLSession.noCache()
    }

    // MARK: - 步骤 3：授权页 URL

    /// 构造授权页 URL（5 个参数：`client_id` / `redirect_uri` / `state` / `code_challenge` / `code_challenge_method`）。
    ///
    /// - 不在 URL 里出现 `client_secret`（它在步骤 6 的请求体里，§3.1）。
    /// - **不使用** `prompt=none` 之类无交互出码参数：必须让用户看到授权页并明确同意（§3.9 缓解项 4）。
    /// - **不启用** device flow（§3.1：官方明确反对）。
    public func authorizationURL(state: String, codeChallenge: String) -> URL? {
        var components = URLComponents(
            url: credentials.authorizeEndpoint,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "redirect_uri", value: credentials.callbackURL),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components?.url
    }

    // MARK: - 步骤 6：授权码换令牌

    /// `POST /login/oauth/access_token`，`grant_type=authorization_code`（省略即为默认值）。
    ///
    /// ⚠️ 必须携带 `client_secret`：GitHub **不区分** public / confidential 客户端，
    ///    官方参数表将其标为 Required，PKCE 不能免除它（决策 #30）。
    public func exchangeCode(_ code: String, codeVerifier: String) async throws -> OAuthToken {
        let request = try makeExchangeRequest(code: code, codeVerifier: codeVerifier)
        return try await sendTokenRequest(request)
    }

    // MARK: - 刷新

    /// `grant_type=refresh_token`。
    ///
    /// ⚠️ 刷新请求**同样必须带 `client_secret`**——官方原文为
    ///    "Required unless the user access token was generated using the device flow"，
    ///    本项目不走 device flow（决策 #30）。
    public func refresh(refreshToken: String) async throws -> OAuthToken {
        let request = try makeRefreshRequest(refreshToken: refreshToken)
        return try await sendTokenRequest(request)
    }

    // MARK: - 撤销

    /// `DELETE /applications/{client_id}/grant`，Basic Auth 为 `client_id` : `client_secret`（§3.6）。
    ///
    /// 撤销的是 **grant**（而非单个 token）：该用户在本 App 下的全部令牌一并作废，不留悬空刷新令牌。
    ///
    /// - Throws: `OAuthError.revokeFailed`。调用方**应降级但不阻塞**登出（§3.6）。
    public func revokeAuthorization(accessToken: String) async throws {
        let request = try makeRevokeRequest(accessToken: accessToken)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.invalidResponse
        }
        // 204 No Content 为官方成功码。
        // 404 亦按成功处理：表示该授权本就不存在（重复登出 / 已在网页端撤销）——即"已撤销"，
        // 此时若抛错会让上层提示"未能撤销"，属反向谎报（§3.6 要求文案如实）。
        if (200..<300).contains(http.statusCode) || http.statusCode == 404 {
            return
        }
        _ = data   // 错误响应体不解析：它可能回显请求上下文，不值得进日志
        throw OAuthError.revokeFailed(http.statusCode)
    }

    // MARK: - 请求构造（internal：供测试直接断言，无需起网络桩件）

    func makeExchangeRequest(code: String, codeVerifier: String) throws -> URLRequest {
        try makeFormRequest(
            to: credentials.accessTokenEndpoint,
            fields: [
                "client_id": credentials.clientID,
                "client_secret": credentials.clientSecret,
                "code": code,
                "redirect_uri": credentials.callbackURL,
                "code_verifier": codeVerifier
            ]
        )
    }

    func makeRefreshRequest(refreshToken: String) throws -> URLRequest {
        try makeFormRequest(
            to: credentials.accessTokenEndpoint,
            fields: [
                "client_id": credentials.clientID,
                "client_secret": credentials.clientSecret,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken
            ]
        )
    }

    func makeRevokeRequest(accessToken: String) throws -> URLRequest {
        guard credentials.isConfigured, let url = credentials.revokeGrantURL else {
            throw OAuthError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.cachePolicy = Self.nonCachingPolicy
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(basicAuthorizationHeader, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["access_token": accessToken])
        return request
    }

    // MARK: - Private

    /// 三条令牌请求共用的缓存策略：**不使用、也不更新任何中间层缓存**。
    ///
    /// 会话层已无 `URLCache`（`makeTokenSession`），这一道是为了防"会话被换回 `.shared`"
    /// 或上游代理缓存 —— 令牌请求永远不该命中缓存，命中即等于把令牌交给缓存。
    static let nonCachingPolicy: URLRequest.CachePolicy = .reloadIgnoringLocalAndRemoteCacheData

    private func makeFormRequest(to url: URL, fields: [String: String]) throws -> URLRequest {
        guard credentials.isConfigured else { throw OAuthError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = Self.nonCachingPolicy
        // Accept: application/json 让端点返回 JSON 而不是 form-urlencoded（§3.1 步骤 7）
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(fields)
        return request
    }

    /// Basic Auth：`base64(client_id : client_secret)`（§3.6）。
    private var basicAuthorizationHeader: String {
        let raw = "\(credentials.clientID):\(credentials.clientSecret)"
        return "Basic " + Data(raw.utf8).base64EncodedString()
    }

    private func sendTokenRequest(_ request: URLRequest) async throws -> OAuthToken {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OAuthError.httpStatus(http.statusCode)
        }

        // ⚠️ 关键：令牌端点在**出错时也可能返回 200**，把错误放在 body 的 error 字段里。
        //    因此状态码通过 ≠ 成功，必须继续检查 body。
        let payload: TokenEndpointResponse
        do {
            payload = try JSONDecoder().decode(TokenEndpointResponse.self, from: data)
        } catch {
            throw OAuthError.invalidResponse
        }

        if let code = payload.error, !code.isEmpty {
            throw OAuthError.tokenEndpointError(code: code, description: payload.errorDescription)
        }
        guard let accessToken = payload.accessToken, !accessToken.isEmpty else {
            throw OAuthError.missingAccessToken
        }
        guard let refreshToken = payload.refreshToken, !refreshToken.isEmpty else {
            throw OAuthError.missingRefreshToken
        }

        return OAuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: payload.tokenType ?? "bearer",
            // §3.2：官方固定值 —— 缺失时按固定值兜底，避免"过期时刻 = now"引发刷新死循环
            expiresIn: TimeInterval(payload.expiresIn ?? 28_800),
            refreshTokenExpiresIn: TimeInterval(payload.refreshTokenExpiresIn ?? 15_897_600),
            scope: payload.scope ?? ""
        )
    }
}
