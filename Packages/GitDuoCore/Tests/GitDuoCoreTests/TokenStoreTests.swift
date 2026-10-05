import Foundation
import Testing

@testable import GitDuoCore

@Suite("TokenStore · 凭据存取与过期判定")
struct TokenStoreTests {

    private func makeToken(accessExpiry: Date, refreshExpiry: Date) -> StoredToken {
        StoredToken(
            accessToken: "ghu_test",
            refreshToken: "ghr_test",
            accessTokenExpiry: accessExpiry,
            refreshTokenExpiry: refreshExpiry,
            login: "jiangjiang"
        )
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("保存后可读回，清除后为空")
    func roundTrip() throws {
        let store = InMemoryTokenStore()
        #expect(try store.load() == nil)

        let token = makeToken(accessExpiry: now.addingTimeInterval(8 * 3600),
                              refreshExpiry: now.addingTimeInterval(180 * 24 * 3600))
        try store.save(token)
        #expect(try store.load() == token)

        try store.clear()
        #expect(try store.load() == nil)
    }

    @Test("过期前 5 分钟触发预刷新，之前不刷新")
    func refreshLeadTime() {
        let token = makeToken(accessExpiry: now.addingTimeInterval(8 * 3600),
                              refreshExpiry: now.addingTimeInterval(180 * 24 * 3600))

        #expect(!token.needsRefresh(at: now))
        #expect(!token.needsRefresh(at: now.addingTimeInterval(8 * 3600 - 301)))
        #expect(token.needsRefresh(at: now.addingTimeInterval(8 * 3600 - 299)))
        #expect(token.needsRefresh(at: now.addingTimeInterval(8 * 3600)))
    }

    @Test("refresh_token 过期判定：过期后必须清凭据回登录页")
    func refreshTokenExpiry() {
        let token = makeToken(accessExpiry: now.addingTimeInterval(8 * 3600),
                              refreshExpiry: now.addingTimeInterval(180 * 24 * 3600))

        #expect(!token.isRefreshTokenExpired(at: now))
        #expect(!token.isRefreshTokenExpired(at: now.addingTimeInterval(179 * 24 * 3600)))
        #expect(token.isRefreshTokenExpired(at: now.addingTimeInterval(181 * 24 * 3600)))
    }
}
