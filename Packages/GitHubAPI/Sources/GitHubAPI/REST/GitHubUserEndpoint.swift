import Foundation

/// `GET /user` —— 用访问令牌换回"我是谁"。
///
/// 依据：TECH_SPEC §3.1 步骤 8、§3.6。
///
/// 职责边界（有意收窄）：**只发这一个请求**，不持有令牌、不管刷新、不管缓存。
/// 完整的 REST 客户端（分页 / ETag / 限流 / 401 刷新重放）是切片的产物（§9.1），
/// 届时它接管通用逻辑，本类型是否保留以那时为准——**现在不要预造一个"万能客户端"**。
///
/// 令牌由调用方逐次传入，而非构造时注入：本类型因此是无状态的，
/// 也就天然不会被误当成"凭据持有者"。
public struct GitHubUserEndpoint: Sendable {

    private let credentials: GitHubAppCredentials
    private let session: URLSession

    public init(credentials: GitHubAppCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    /// 校验令牌并取回登录名。
    ///
    /// - Throws: `OAuthError.invalidResponse`（非 HTTP 响应 / body 解不出 `login`）、
    ///           `OAuthError.httpStatus(_)`（非 2xx，401 表示令牌已失效）。
    public func fetchAuthenticatedUser(accessToken: String) async throws -> AuthenticatedUser {
        let request = makeRequest(accessToken: accessToken)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OAuthError.httpStatus(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(AuthenticatedUser.self, from: data)
        } catch {
            throw OAuthError.invalidResponse
        }
    }

    /// internal：供测试直接断言请求形状，无需起网络桩件。
    func makeRequest(accessToken: String) -> URLRequest {
        var request = URLRequest(url: credentials.apiBaseURL.appendingPathComponent("user"))
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(credentials.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub App 用户令牌用 `Bearer`（§3.7）；令牌只出现在请求头，绝不进 URL 或日志
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}
