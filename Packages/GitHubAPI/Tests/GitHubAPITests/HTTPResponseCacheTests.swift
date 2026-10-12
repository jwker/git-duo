import Foundation
import Testing

@testable import GitHubAPI

@Suite("HTTP 响应缓存（§5.1 L2 / 决策 #32）")
struct HTTPResponseCacheTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeKey(_ urlString: String) -> CacheKey {
        CacheKey(URL(string: urlString)!)
    }

    private func makeResponse(
        status: Int = 200,
        body: String = #"{"ok":true}"#,
        etag: String? = "W/\"abc\"",
        headers: [String: String] = [:],
        fetchedAt: Date? = nil
    ) -> CachedHTTPResponse {
        CachedHTTPResponse(
            statusCode: status,
            headers: HTTPHeaders(headers),
            body: Data(body.utf8),
            etag: etag,
            fetchedAt: fetchedAt ?? now
        )
    }

    /// 建一个用完即删的临时目录 —— 缓存测试绝不碰真实容器。
    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitduo-cache-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - 内存层

    @Test("存了就取得到，字段逐个保住")
    func memoryRoundTrip() async {
        let cache = HTTPResponseCache(configuration: .memoryOnly())
        let key = makeKey("https://api.github.com/user")
        let response = makeResponse()

        await cache.store(response, for: key)
        let loaded = await cache.entry(for: key)

        #expect(loaded == response)
        #expect(loaded?.etag == "W/\"abc\"")
        #expect(loaded?.statusCode == 200)
    }

    @Test("没存过就是 nil（不返回空壳条目）")
    func missReturnsNil() async {
        let cache = HTTPResponseCache(configuration: .memoryOnly())

        let loaded = await cache.entry(for: makeKey("https://api.github.com/nope"))

        #expect(loaded == nil)
    }

    @Test("⚠️ 键含完整查询串：只差一个参数就是两条不同条目")
    func queryStringIsPartOfTheKey() async {
        let cache = HTTPResponseCache(configuration: .memoryOnly())
        let pageTwo = makeKey("https://api.github.com/repos/o/r/issues?page=2")
        let pageThree = makeKey("https://api.github.com/repos/o/r/issues?page=3")

        await cache.store(makeResponse(body: #"{"page":2}"#, etag: "e2"), for: pageTwo)
        await cache.store(makeResponse(body: #"{"page":3}"#, etag: "e3"), for: pageThree)

        let two = await cache.entry(for: pageTwo)
        let three = await cache.entry(for: pageThree)

        #expect(two?.etag == "e2")
        #expect(three?.etag == "e3")
    }

    @Test("覆盖同一条：不重复计数（旧的字节要退回来）")
    func overwriteReplacesWithoutDoubleCounting() async {
        let cache = HTTPResponseCache(configuration: .memoryOnly())
        let key = makeKey("https://api.github.com/user")

        await cache.store(makeResponse(body: String(repeating: "a", count: 1000)), for: key)
        await cache.store(makeResponse(body: "b"), for: key)

        let count = await cache.memoryEntryCount
        let loaded = await cache.entry(for: key)

        #expect(count == 1)
        #expect(loaded?.body == Data("b".utf8))
    }

    // MARK: - `Cache-Control` 纪律

    @Test("`no-store` 的响应拒绝入库，且清掉已有旧副本")
    func noStoreIsRefusedAndPurgesExisting() async {
        let cache = HTTPResponseCache(configuration: .memoryOnly())
        let key = makeKey("https://api.github.com/user")

        await cache.store(makeResponse(body: "first"), for: key)
        #expect(await cache.entry(for: key) != nil)

        await cache.store(
            makeResponse(body: "second", headers: ["Cache-Control": "no-store"]),
            for: key
        )

        // 关键：不是"没存进去"，而是"连旧的也清了" —— 否则会留下一条本该消失的副本
        #expect(await cache.entry(for: key) == nil)
    }

    @Test("Cache-Control 解析：no-store / max-age / 认不出的忽略")
    func cacheControlParsing() {
        #expect(CacheDirective.parse("no-store") == [.noStore])
        #expect(CacheDirective.parse("private, max-age=60, s-maxage=60") == [.maxAge(60)])
        #expect(CacheDirective.parse("no-cache, NO-STORE") == [.noStore])
        #expect(CacheDirective.parse("public") == [])
        #expect(CacheDirective.parse(nil) == [])
        #expect(CacheDirective.parse("") == [])
    }

    @Test("过期判定：优先用响应自己的 max-age，没有才用默认值")
    func expiryUsesResponseMaxAgeFirst() {
        let withMaxAge = makeResponse(headers: ["Cache-Control": "max-age=60"])

        #expect(!withMaxAge.isExpired(now: now.addingTimeInterval(59), defaultTimeToLive: 3600))
        #expect(withMaxAge.isExpired(now: now.addingTimeInterval(61), defaultTimeToLive: 3600))

        let withoutMaxAge = makeResponse()
        #expect(!withoutMaxAge.isExpired(now: now.addingTimeInterval(59), defaultTimeToLive: 60))
        #expect(withoutMaxAge.isExpired(now: now.addingTimeInterval(61), defaultTimeToLive: 60))
    }

    @Test("max-age=0 ⇒ 立刻过期（仍留在缓存里，但每次都得先问服务端）")
    func zeroMaxAgeExpiresImmediatelyButStays() async {
        let cache = HTTPResponseCache(configuration: .memoryOnly())
        let key = makeKey("https://api.github.com/user")

        await cache.store(makeResponse(headers: ["Cache-Control": "max-age=0"]), for: key)

        let loaded = await cache.entry(for: key)
        #expect(loaded != nil)
        #expect(loaded?.isExpired(now: now, defaultTimeToLive: 300) == true)
    }

    // MARK: - 内存淘汰

    @Test("内存层按条目数淘汰：最久未用的先走（LRU）")
    func memoryLRUByEntryCount() async {
        let cache = HTTPResponseCache(configuration: .memoryOnly(memoryEntryLimit: 2, memoryByteLimit: .max))
        let a = makeKey("https://api.github.com/a")
        let b = makeKey("https://api.github.com/b")
        let c = makeKey("https://api.github.com/c")

        await cache.store(makeResponse(body: "a"), for: a)
        await cache.store(makeResponse(body: "b"), for: b)

        // 访问 a ⇒ a 变成最近使用，被淘汰的应该是 b 而不是 a
        _ = await cache.entry(for: a)

        await cache.store(makeResponse(body: "c"), for: c)

        #expect(await cache.entry(for: a) != nil)
        #expect(await cache.entry(for: c) != nil)
        #expect(await cache.entry(for: b) == nil)
    }

    @Test("内存层按字节淘汰：大条目进来会把小的挤出去")
    func memoryLRUByBytes() async {
        let cache = HTTPResponseCache(
            configuration: .memoryOnly(memoryEntryLimit: 100, memoryByteLimit: 100)
        )
        let big = makeKey("https://api.github.com/big")
        let small = makeKey("https://api.github.com/small")

        await cache.store(makeResponse(body: String(repeating: "x", count: 80)), for: small)
        await cache.store(makeResponse(body: String(repeating: "y", count: 80)), for: big)

        // 两条各 80 字节，上限 100 ⇒ 后进来的把先前的挤掉
        #expect(await cache.entry(for: small) == nil)
        #expect(await cache.entry(for: big) != nil)
    }

    // MARK: - 磁盘层

    @Test("磁盘往返：换一个实例（模拟冷启动）仍读得到，ETag 也在")
    func diskSurvivesNewInstance() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let key = makeKey("https://api.github.com/repos/o/r")
        let response = makeResponse(body: #"{"full_name":"o/r"}"#, etag: "W/\"disk\"")

        let first = HTTPResponseCache(configuration: .init(directory: directory))
        await first.store(response, for: key)

        // 新实例 = 进程重启后的样子：内存层为空，只能靠磁盘
        let second = HTTPResponseCache(configuration: .init(directory: directory))
        let loaded = await second.entry(for: key)

        #expect(loaded?.etag == "W/\"disk\"")
        #expect(loaded?.body == response.body)
        #expect(loaded?.statusCode == 200)
    }

    @Test("磁盘条目零膨胀：读回来的 body 与写进去的逐字节相等（不是 base64 解出来的）")
    func diskBodyIsByteExact() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let key = makeKey("https://api.github.com/image")
        // 含 0x00 与随机字节 —— base64 方案在这里会引入长度与内容上的细微差别
        let raw = Data((0..<512).map { UInt8($0 % 256) })

        let cache = HTTPResponseCache(configuration: .init(directory: directory))
        await cache.store(
            CachedHTTPResponse(statusCode: 200, body: raw, etag: nil, fetchedAt: now),
            for: key
        )

        let reloaded = HTTPResponseCache(configuration: .init(directory: directory))
        let loaded = await reloaded.entry(for: key)

        #expect(loaded?.body == raw)
    }

    @Test("只做内存层时（directory 为 nil）不产生任何文件")
    func memoryOnlyWritesNothing() async {
        let cache = HTTPResponseCache(configuration: .memoryOnly())
        let key = makeKey("https://api.github.com/user")

        await cache.store(makeResponse(), for: key)

        #expect(await cache.totalByteCount > 0)
        // 没有任何目录配置 ⇒ 不可能写出文件；这里断言的是"取值路径不会崩"
        #expect(await cache.entry(for: key) != nil)
    }

    // MARK: - 失效与清空

    @Test("按路径前缀失效：只动该路径下的（目录自身要清、形近路径不能误伤）")
    func invalidateByPathPrefix() async {
        let cache = HTTPResponseCache(configuration: .memoryOnly())
        let contentsFile = makeKey("https://api.github.com/repos/o/r/contents/a.md")
        let contentsDir = makeKey("https://api.github.com/repos/o/r/contents")
        let sibling = makeKey("https://api.github.com/repos/o/r/branches")
        let otherRepo = makeKey("https://api.github.com/repos/o/other/contents/a.md")
        // 形近路径：`hasPrefix` 少了补斜杠的话会被误伤
        let lookalike = makeKey("https://api.github.com/repos/o/r/contents-archive/a.md")

        for key in [contentsFile, contentsDir, sibling, otherRepo, lookalike] {
            await cache.store(makeResponse(), for: key)
        }

        await cache.invalidate(pathPrefix: "/repos/o/r/contents")

        #expect(await cache.entry(for: contentsFile) == nil)
        // ⚠️ 目录清单自身也必须清掉 —— 写文件后它第一个变了
        #expect(await cache.entry(for: contentsDir) == nil)
        #expect(await cache.entry(for: sibling) != nil)
        // ⚠️ 前缀是 "/repos/o/r/"，不是 "/repos/o/" —— 否则会连别的仓库一起清掉
        #expect(await cache.entry(for: otherRepo) != nil)
        #expect(await cache.entry(for: lookalike) != nil)
    }

    @Test("按路径前缀失效：磁盘上的条目也要清掉（写操作后的失效不能只在内存生效）")
    func invalidateAlsoPurgesDisk() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = makeKey("https://api.github.com/repos/o/r/contents/a.md")
        let keeper = makeKey("https://api.github.com/repos/o/r/branches")

        let cache = HTTPResponseCache(configuration: .init(directory: directory))
        await cache.store(makeResponse(body: "a"), for: target)
        await cache.store(makeResponse(body: "b"), for: keeper)
        await cache.invalidate(pathPrefix: "/repos/o/r/contents")

        // 换新实例，绕过内存层直接验磁盘
        let fresh = HTTPResponseCache(configuration: .init(directory: directory))
        #expect(await fresh.entry(for: target) == nil)
        #expect(await fresh.entry(for: keeper) != nil)
    }

    @Test("清空：返回释放的字节数，且之后什么都取不到（§5.4 设置页要报告大小）")
    func removeAllReportsFreedBytes() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = HTTPResponseCache(configuration: .init(directory: directory))
        await cache.store(makeResponse(body: String(repeating: "a", count: 500)), for: makeKey("https://api.github.com/a"))
        await cache.store(makeResponse(body: String(repeating: "b", count: 300)), for: makeKey("https://api.github.com/b"))

        let freed = await cache.removeAll()

        #expect(freed > 0)
        #expect(await cache.totalByteCount == 0)
        #expect(await cache.memoryEntryCount == 0)

        let fresh = HTTPResponseCache(configuration: .init(directory: directory))
        #expect(await fresh.entry(for: makeKey("https://api.github.com/a")) == nil)
    }

    @Test("删除单条：内存与磁盘同步消失")
    func removeSingleEntry() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let key = makeKey("https://api.github.com/user")
        let cache = HTTPResponseCache(configuration: .init(directory: directory))
        await cache.store(makeResponse(), for: key)

        await cache.remove(key)

        let fresh = HTTPResponseCache(configuration: .init(directory: directory))
        #expect(await fresh.entry(for: key) == nil)
    }

    // MARK: - 坏数据兜底

    @Test("磁盘上有垃圾文件时静默跳过（缓存坏了不该让请求链路失败）")
    func garbageOnDiskIsIgnored() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try? Data("not a valid cache entry".utf8)
            .write(to: directory.appendingPathComponent("garbage.cache"))

        let cache = HTTPResponseCache(configuration: .init(directory: directory))

        #expect(await cache.entry(for: makeKey("https://api.github.com/user")) == nil)
        // 前缀失效遍历到它时也不该崩
        await cache.invalidate(pathPrefix: "/repos/o/r")
    }

    @Test("CacheKey 的文件名：不同 URL 不同名、同一 URL 同名（稳定）")
    func cacheKeyFileNamesAreStable() {
        let a = makeKey("https://api.github.com/repos/o/r?page=1")
        let b = makeKey("https://api.github.com/repos/o/r?page=2")
        let aAgain = makeKey("https://api.github.com/repos/o/r?page=1")

        #expect(a.fileName != b.fileName)
        #expect(a.fileName == aAgain.fileName)
    }

    @Test("⚠️ 同一 URL 的两种表示（variant 不同）**不共用**文件名")
    func cacheKeyVariantsDoNotShareFileName() {
        let url = URL(string: "https://api.github.com/repos/o/r/contents/logo.png")!

        let json = CacheKey(url)
        let raw = CacheKey(url, variant: "application/vnd.github.raw")

        // 撞在一起的话，`rawFile` 会带着 JSON 那次的 ETag 去问、被答 304，
        // 于是"取一张图"拿回来的是 JSON 文本（症状：图片全显示加载失败）。
        #expect(json.fileName != raw.fileName)
        #expect(json != raw)
    }

    @Test("⚠️ 变体为空时文件名与本条修复之前**逐字一致**（升级不作废已落盘的缓存）")
    func emptyVariantKeepsLegacyFileName() {
        let url = URL(string: "https://api.github.com/user")!
        // 旧实现的哈希输入就是 `url.absoluteString` —— 这里显式钉住它，
        // 将来谁再往哈希输入里加料，这条会红。
        let legacy = "\(SHA256Digest.hex(of: Data(url.absoluteString.utf8))).cache"

        #expect(CacheKey(url).fileName == legacy)
        #expect(CacheKey(url, variant: "").fileName == legacy)
    }
}
