import Foundation
import Testing

@testable import GitHubAPI

@Suite("PKCE · RFC 7636")
struct PKCETests {

    /// RFC 7636 附录 B 的官方测试向量
    private static let rfcVerifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    private static let rfcChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

    @Test("S256 challenge 与 RFC 7636 附录 B 向量逐字符一致")
    func rfc7636Vector() {
        #expect(PKCE.codeChallenge(for: Self.rfcVerifier) == Self.rfcChallenge)
    }

    @Test("base64url 输出不含 + / =，可安全放进 URL 查询串")
    func base64URLAlphabet() {
        let encoded = PKCE.base64URLEncoded(Data([0xFB, 0xFF, 0xBF, 0x00, 0x3E, 0x3F]))
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
    }

    @Test("生成的 code_verifier 满足 RFC 7636 §4.1 的长度与字符集")
    func verifierShape() {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        for length in [43, 64, 128] {
            let verifier = PKCE.makeCodeVerifier(length: length)
            #expect(verifier.count == length)
            #expect(verifier.allSatisfy { allowed.contains($0) })
        }
    }

    @Test("两次生成不重复（保证随机源真的在被使用）")
    func uniqueness() {
        #expect(PKCE.makeCodeVerifier() != PKCE.makeCodeVerifier())
        #expect(PKCE.makeState() != PKCE.makeState())
    }

    @Test("state 校验：一致通过，不一致 / 缺失 / 长度不同一律拒绝")
    func stateValidation() {
        let state = PKCE.makeState()
        #expect(PKCE.isValidCallbackState(state, expected: state))
        #expect(!PKCE.isValidCallbackState(state, expected: PKCE.makeState()))
        #expect(!PKCE.isValidCallbackState(state, expected: nil))
        #expect(!PKCE.isValidCallbackState(state, expected: ""))
        #expect(!PKCE.isValidCallbackState("", expected: state))
        #expect(!PKCE.isValidCallbackState(state + "x", expected: state))
    }
}
