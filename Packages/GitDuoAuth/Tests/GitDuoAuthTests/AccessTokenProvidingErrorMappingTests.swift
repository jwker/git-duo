import Foundation
import GitHubAPI
import GitDuoCore
import Testing

@testable import GitDuoAuth

/// `AuthCoordinator` 的**数据层出口**错误口径 —— 归一化映射表的规格。
///
/// 依据：`AccessTokenProviding` 的错误约定；TECH_SPEC §3.2（凭据失效才登出）。
///
/// ⚠️ 本套件**刻意不碰网络桩件**（全部是纯函数断言）。原因：本包的
/// `StubURLProtocol` 用的是进程级静态状态，而 Swift Testing 默认让不同套件**并行** ——
/// 第二个用桩件的套件会和 `AuthCoordinatorTests` 互相覆盖响应，
/// 症状是"单跑全绿、全量跑挂"。凡需要发请求的用例一律并入 `AuthCoordinatorTests`。
@Suite("AuthCoordinator · 令牌出口错误口径")
struct AccessTokenProvidingErrorMappingTests {

    // MARK: - 映射表

    /// 每一条都必须有理由：**重试有没有意义**。有意义的原样抛，没意义的归 `.unauthorized`。
    @Test(
        "AuthError → GitHubError：映射表逐条核对",
        arguments: zip(
            [
                // 凭据没了 / 被撤销 / 拿不到 ⇒ 只能重新授权
                AuthError.notAuthenticated,
                AuthError.refreshTokenExpired,
                AuthError.oauth(.httpStatus(401)),
                AuthError.oauth(.tokenEndpointError(code: "bad_refresh_token", description: nil)),
                AuthError.oauth(.missingAccessToken),
                AuthError.oauth(.missingRefreshToken)
            ],
            [
                GitHubError.unauthorized,
                GitHubError.unauthorized,
                GitHubError.unauthorized,
                GitHubError.unauthorized,
                GitHubError.unauthorized,
                GitHubError.unauthorized
            ]
        )
    )
    func mapsCredentialErrors(_ error: AuthError, _ expected: GitHubError) {
        #expect(error.asGitHubError == expected)
    }

    @Test(
        "服务端/网关的问题绝不能报成 unauthorized（那会把用户登出）",
        arguments: zip(
            [AuthError.oauth(.httpStatus(500)), AuthError.oauth(.httpStatus(403))],
            [GitHubError.serverError(status: 500), GitHubError.serverError(status: 403)]
        )
    )
    func mapsServerErrors(_ error: AuthError, _ expected: GitHubError) {
        #expect(error.asGitHubError == expected)
    }

    @Test(
        "不该被改写的错误：原样上抛，不编造结论",
        arguments: [
            AuthError.notConfigured,
            AuthError.oauth(.notConfigured),
            AuthError.oauth(.invalidResponse),
            AuthError.oauth(.revokeFailed(422)),
            AuthError.missingAuthorizationContext,
            AuthError.callbackRejected(.stateMismatch),
            AuthError.credentialStoreFailed
        ]
    )
    func leavesUnrelatedErrorsAlone(_ error: AuthError) {
        #expect(error.asGitHubError == nil, "没有可靠映射就不映射 —— 假结论比没有结论更危险")
    }

    // MARK: - 出口归一化

    @Test("断网：URLError 换成数据层的 .transport（HTTPTransport 的 throws GitHubError 契约靠它成立）")
    func mapsURLErrorToTransport() {
        let mapped = AuthCoordinator.asTokenProviderError(URLError(.notConnectedToInternet))

        guard let error = mapped as? GitHubError else {
            Issue.record("URLError 应换成 GitHubError，实际拿到 \(type(of: mapped))")
            return
        }
        #expect(error == .transport(URLError(.notConnectedToInternet)))
    }

    @Test("断网**不是** unauthorized —— 这一条是「断网 ≠ 登出」的数据层半边")
    func networkFailureIsNotUnauthorized() {
        let mapped = AuthCoordinator.asTokenProviderError(URLError(.timedOut))

        #expect((mapped as? GitHubError) != .unauthorized)
    }

    @Test("认不出来的错误：原样上抛，不做兜底包装")
    func passesUnknownErrorsThrough() {
        struct Weird: Error {}

        let mapped = AuthCoordinator.asTokenProviderError(Weird())

        #expect(mapped is Weird, "包成 .transport 等于谎称它是网络问题，会给出『检查网络』这种错误引导")
    }

    @Test("映射表命中的 AuthError：不再以 AuthError 形态外泄")
    func mappedErrorsDoNotLeakAuthError() {
        let mapped = AuthCoordinator.asTokenProviderError(AuthError.refreshTokenExpired)

        #expect(mapped is GitHubError)
        #expect(!(mapped is AuthError))
    }
}
