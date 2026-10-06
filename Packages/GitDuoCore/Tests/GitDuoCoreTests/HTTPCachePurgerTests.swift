import Foundation
import Testing

@testable import GitDuoCore

/// `SystemHTTPCachePurger` 的行为规格。
///
/// 这里测的是**真实副作用**（往缓存里塞一条再清掉），而不是"调用了一个方法"。
/// 理由：真机上要清掉的那个令牌副本就躺在磁盘缓存里，如果清理手段清不干净，
/// 这个测试应该最先发现。
///
/// ⚠️ 用**隔离的 `URLCache` 实例**，不用 `URLCache.shared`：
///    测试进程里后者的默认容量是 0，`storeCachedResponse` 会**静默丢弃**，
///    于是"前置条件"永远不成立、断言永远空过（一个永远绿的假测试）。
@Suite("SystemHTTPCachePurger · 清空 URL 缓存")
struct SystemHTTPCachePurgerTests {

    /// 内存-only 的缓存实例（`directory: nil`），容量足够放下一条响应。
    private func makeIsolatedCache() -> URLCache {
        URLCache(memoryCapacity: 1 << 20, diskCapacity: 0, directory: nil)
    }

    @Test("清掉已存入的缓存条目（登出的前提：副本真的会消失）")
    func purgeRemovesStoredResponses() throws {
        let cache = makeIsolatedCache()
        let url = try #require(URL(string: "https://api.github.com/probe/purge-test"))
        let request = URLRequest(url: url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Cache-Control": "max-age=3600"]
        ))
        cache.storeCachedResponse(
            CachedURLResponse(response: response, data: Data(#"{"login":"probe"}"#.utf8)),
            for: request
        )

        // 前置条件：先证明条目确实进去了 —— 否则后面的断言是空过
        #expect(
            cache.cachedResponse(for: request) != nil,
            "前置条件失败：条目没存进 URLCache，本测试无意义"
        )

        SystemHTTPCachePurger(cache: cache).purge()

        #expect(
            cache.cachedResponse(for: request) == nil,
            "登出后缓存里不该再留任何响应 —— 磁盘上的令牌副本正是靠这一步消失"
        )
    }

    @Test("清空是幂等的：没有缓存时调用也不出错")
    func purgeIsIdempotent() {
        let purger = SystemHTTPCachePurger(cache: makeIsolatedCache())
        purger.purge()
        purger.purge()
        // 只要求"不清空一个空缓存就不崩"——清空本来就是无声的操作
    }
}
