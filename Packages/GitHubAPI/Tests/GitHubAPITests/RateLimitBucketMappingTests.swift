import Foundation
import Testing

@testable import GitHubAPI

/// 配额桶的映射规则 —— 响应头里的桶名 ↔ 限流器的桶（TECH_SPEC §4.5）。
///
/// 这一层看着琐碎，但它决定"哪个请求会被闸门拦住"。错了不会有任何编译期或运行时提示：
/// 搜索请求会被当成主桶放过，直到某天配额打爆。
@Suite("配额桶 · 映射与串行规则")
struct RateLimitBucketMappingTests {

    @Test(
        "已知桶名逐条映射",
        arguments: zip(
            [RateLimitResource.core, .search, .graphql, .codeSearch],
            [RateLimiter.Bucket.core, .search, .graphql, .codeSearch]
        )
    )
    func mapsKnownResources(_ resource: RateLimitResource, _ expected: RateLimiter.Bucket) {
        #expect(RateLimiter.Bucket(resource) == expected)
    }

    @Test("未知桶：映射为 nil ⇒ 不限速。**不要落回主桶**")
    func unknownResourceIsNotThrottled() {
        #expect(RateLimiter.Bucket(.other("some_new_bucket")) == nil)
    }

    @Test("只有代码搜索必须串行 —— 官方限额最紧（≈10/分钟），并发会互相加剧失败")
    func onlyCodeSearchSerializes() {
        #expect(RateLimiter.Bucket.codeSearch.requiresSerialization)
        #expect(!RateLimiter.Bucket.search.requiresSerialization)
        #expect(!RateLimiter.Bucket.core.requiresSerialization)
        #expect(!RateLimiter.Bucket.graphql.requiresSerialization)
    }

    @Test("响应头里的桶名能一路对上限流器的桶（含官方两种写法的代码搜索）")
    func headerResourceAlignsWithBucket() {
        #expect(RateLimitResource(rawValue: "core") == .core)
        #expect(RateLimitResource(rawValue: "search") == .search)
        #expect(RateLimitResource(rawValue: "graphql") == .graphql)
        // 官方文档对代码搜索桶存在 `code_search` / `codesearch` 两种写法，两种都得认
        #expect(RateLimitResource(rawValue: "code_search") == .codeSearch)
        #expect(RateLimitResource(rawValue: "codesearch") == .codeSearch)
        #expect(RateLimiter.Bucket(RateLimitResource(rawValue: "search")) == .search)
        // 认不出的值不许"猜成主桶"
        #expect(RateLimiter.Bucket(RateLimitResource(rawValue: "mystery")) == nil)
    }

    @Test("默认请求落在主桶：间隔为 0 ⇒ 不会被闸门拖慢")
    func defaultRequestIsNotThrottled() {
        let url = URL(string: "https://api.github.com/user")!

        #expect(HTTPRequest.get(url).rateLimitResource == .core)
        #expect(HTTPRequest.sending(.delete, to: url).rateLimitResource == .core)
    }
}
