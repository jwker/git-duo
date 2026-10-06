import Foundation
import Testing

@testable import GitHubAPI

/// `OAuthCallback` 的行为规格。
///
/// 依据：TECH_SPEC §3.9（四类风险场景与缓解）、§3.8（取消与失败出口表）、§12.2（回调校验测试项）。
/// 这一组断言守卫的核心是：**「不是我们的回调」「用户取消」「校验失败」三者不能混同**。
@Suite("OAuthCallback · 形状校验 / state 一次性 / 取消语义")
struct OAuthCallbackTests {

    private func url(_ raw: String) throws -> URL {
        try #require(URL(string: raw), "测试用的 URL 字面量写错了：\(raw)")
    }

    // MARK: - 成功路径

    @Test("正常回调 → authorized，带回 code 与已校验的 state")
    func happyPath() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo://oauth/callback?code=the-code&state=the-state"),
            expectedState: "the-state"
        )
        #expect(outcome == .authorized(code: "the-code"))
    }

    @Test("多余参数不影响解析")
    func extraParametersAreTolerated() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo://oauth/callback?code=c&state=s&foo=bar&installation_id=42"),
            expectedState: "s"
        )
        #expect(outcome == .authorized(code: "c"))
    }

    @Test("code 里的百分号编码被正确解码")
    func percentEncodedCodeIsDecoded() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo://oauth/callback?code=a%2Fb%2Bc&state=s"),
            expectedState: "s"
        )
        #expect(outcome == .authorized(code: "a/b+c"))
    }

    @Test("scheme 大小写不敏感（iOS 传入的 scheme 可能被规范化）")
    func schemeIsCaseInsensitive() throws {
        let outcome = OAuthCallback.resolve(
            try url("GitDuo://oauth/callback?code=c&state=s"),
            expectedState: "s"
        )
        #expect(outcome == .authorized(code: "c"))
    }

    // MARK: - state（一次性）

    @Test("state 不匹配 → failed(.stateMismatch)，且**不泄露**任何 code")
    func stateMismatchIsRejected() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo://oauth/callback?code=attacker-code&state=wrong"),
            expectedState: "expected"
        )
        #expect(outcome == .failed(.stateMismatch))
    }

    @Test("本地没有等待中的授权（expectedState 为 nil）→ 一律 stateMismatch")
    func noPendingAuthorizationRejectsEverything() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo://oauth/callback?code=c&state=s"),
            expectedState: nil
        )
        #expect(outcome == .failed(.stateMismatch))
    }

    @Test("重复回调：state 已消费（置 nil）后，同一 URL 第二次投递必须被拒")
    func duplicateCallbackIsRejected() throws {
        let callback = try url("gitduo://oauth/callback?code=one-time-code&state=st")

        let first = OAuthCallback.resolve(callback, expectedState: "st")
        #expect(first == .authorized(code: "one-time-code"))

        // 编排层收到 authorized 后立即作废 state —— 此处模拟该行为
        let second = OAuthCallback.resolve(callback, expectedState: nil)
        #expect(second == .failed(.stateMismatch))
    }

    @Test("state 为空串视同缺失")
    func emptyStateIsTreatedAsMissing() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo://oauth/callback?code=c&state="),
            expectedState: "s"
        )
        #expect(outcome == .failed(.missingState))
    }

    // MARK: - 缺参数

    @Test("缺 code → failed(.missingCode)")
    func missingCode() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo://oauth/callback?state=s"),
            expectedState: "s"
        )
        #expect(outcome == .failed(.missingCode))
    }

    @Test("裸回调（无任何 query）→ failed(.missingCode)")
    func bareCallback() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo://oauth/callback"),
            expectedState: "s"
        )
        #expect(outcome == .failed(.missingCode))
    }

    @Test("code 为空串视同缺失")
    func emptyCodeIsTreatedAsMissing() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo://oauth/callback?code=&state=s"),
            expectedState: "s"
        )
        #expect(outcome == .failed(.missingCode))
    }

    // MARK: - 取消 vs 服务端错误

    @Test("error=access_denied → cancelled（用户取消属正常操作，不是错误）")
    func accessDeniedIsCancellation() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo://oauth/callback?error=access_denied&error_description=The+user+denied+the+request"),
            expectedState: "s"
        )
        #expect(outcome == .cancelled)
    }

    @Test("其它 error → failed(.serviceError)，并保留错误码与说明")
    func serviceErrorIsReported() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo://oauth/callback?error=incorrect_client_credentials&error_description=Bad+secret"),
            expectedState: "s"
        )
        #expect(outcome == .failed(.serviceError(
            code: "incorrect_client_credentials",
            description: "Bad secret"
        )))
    }

    @Test("error 优先于 code：即使同时带了 code，也必须按失败处理")
    func errorTakesPrecedenceOverCode() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo://oauth/callback?error=access_denied&code=sneaky"),
            expectedState: "s"
        )
        #expect(outcome == .cancelled)
    }

    // MARK: - 形状不符 ⇒ 静默丢弃

    @Test("scheme 不符（https）→ ignored")
    func wrongSchemeIsIgnored() throws {
        let outcome = OAuthCallback.resolve(
            try url("https://oauth/callback?code=c&state=s"),
            expectedState: "s"
        )
        #expect(outcome == .ignored)
    }

    @Test("host 不符（gitduo://evil/callback）→ ignored —— 只比 path 会漏掉这种伪装")
    func wrongHostIsIgnored() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo://evil/callback?code=c&state=s"),
            expectedState: "s"
        )
        #expect(outcome == .ignored)
    }

    @Test("path 不符 → ignored")
    func wrongPathIsIgnored() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo://oauth/other?code=c&state=s"),
            expectedState: "s"
        )
        #expect(outcome == .ignored)
    }

    @Test("缺 host 的裸 scheme → ignored")
    func hostlessURLIsIgnored() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo:/oauth/callback?code=c&state=s"),
            expectedState: "s"
        )
        #expect(outcome == .ignored)
    }

    @Test("形状不符时**即便 state 是对的**也必须忽略（先验形状，后验 state）")
    func shapeIsCheckedBeforeState() throws {
        let outcome = OAuthCallback.resolve(
            try url("gitduo://evil/callback?code=c&state=s"),
            expectedState: "s"
        )
        #expect(outcome == .ignored)
    }

    // MARK: - 与配置对齐

    @Test("默认形状与 AppConfig 的回调契约一致：gitduo://oauth/callback")
    func defaultShapeMatchesDocumentedContract() {
        let shape = OAuthCallback.Shape.gitduoCallback
        #expect(shape.scheme == "gitduo")
        #expect(shape.host == "oauth")
        #expect(shape.path == "/callback")
        #expect("\(shape.scheme)://\(shape.host)\(shape.path)" == "gitduo://oauth/callback")
    }
}
