import Foundation
import Testing

@testable import GitHubAPI

/// 出网会话的配置规格：**结构性不落盘**。
///
/// 依据：TECH_SPEC §3.3。
/// 这几条断言看着"只是在读配置"，但它们守着一类**真机上真实发生过**的事故：
/// `URLCache` 会把带 `Authorization` 头的**序列化请求对象**写进 `Cache.db`
/// （2026-10-06 实测，`cfurl_cache_blob_data.proto_props` 里躺着 `Bearer ghu_…`）。
/// 会话上不挂 `URLCache` ⇒ 这条路径根本不存在。
@Suite("GitHubURLSession · 不落盘")
struct GitHubURLSessionTests {

    @Test("没有 URLCache ⇒ 请求对象与响应体都无处落盘")
    func hasNoURLCache() {
        let configuration = GitHubURLSession.shared.configuration

        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    @Test("没有 Cookie 罐 —— API 客户端不需要 Cookie（令牌走 Authorization 头）")
    func hasNoCookieJar() {
        let configuration = GitHubURLSession.shared.configuration

        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
    }

    @Test("noCache() 是工厂（每次给新实例），shared 才是共享实例")
    func factoryReturnsFreshInstance() {
        #expect(GitHubURLSession.noCache() !== GitHubURLSession.shared)
        #expect(GitHubURLSession.noCache().configuration.urlCache == nil)
    }

    @Test("令牌会话与 API 会话共用同一份配置（避免两处漂移）")
    func tokenSessionSharesTheSameConfiguration() {
        let client = GitHubOAuthClient(
            credentials: GitHubAppCredentials(
                clientID: "Iv23liTESTclientid",
                clientSecret: "s3cr3t-soft",
                callbackURL: "gitduo://oauth/callback",
                apiVersion: "2026-03-10"
            )
        )

        #expect(client.session.configuration.urlCache == nil)
        #expect(client.session.configuration.requestCachePolicy
            == GitHubURLSession.shared.configuration.requestCachePolicy)
        #expect(client.session.configuration.httpShouldSetCookies == false)
    }
}
