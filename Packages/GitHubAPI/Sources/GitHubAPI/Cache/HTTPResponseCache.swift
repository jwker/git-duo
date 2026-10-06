import Foundation

/// HTTP 响应缓存（TECH_SPEC §5.1 的 **L2**）—— 自建，**绝不使用系统 `URLCache`**。
///
/// 决策 #32（2026-10-06 真机实测后定）：`URLCache` 落盘的**不只是响应体，还有序列化后的请求对象**，
/// 于是每个带 `Authorization` 的请求都会把 `Bearer ghu_…` 明文写进 `Library/Caches/…/Cache.db`。
/// 所以这一层只存四样东西：**URL / ETag / 响应体 / 抓取时刻** —— 请求对象一概不留。
///
/// **两层介质**：内存（快，条目与字节双限）+ 磁盘（跨启动存活，让冷启动也能打条件请求）。
/// 磁盘是**可选**的（`Configuration.directory == nil` 时纯内存），这样单测可以完全不碰文件系统。
///
/// ⚠️ **`entry(for:)` 不判断过期** —— 这不是疏漏，是 HTTP 缓存的正确语义：
/// ETag 是长期有效的，一条"过了 max-age"的条目**仍然值得拿来发一次条件请求**
/// （304 不消耗配额，§5.2）。判断"能不能不验证直接用"是调用方的事（`CachedHTTPResponse.isExpired`）。
///
/// ⚠️ **缓存是"可丢弃的加速器"**（§5.1）：本类型所有磁盘操作失败都**静默降级**为
/// "这次没缓存"。宁可少命中一次，也不让一个坏掉的缓存目录把请求链路拖垮。
public actor HTTPResponseCache {

    /// 取当前时刻。注入而非直接 `Date()` —— 过期与 LRU 都是时间相关的判断。
    public typealias Clock = @Sendable () -> Date

    public struct Configuration: Sendable {

        /// 内存层条目数上限
        public var memoryEntryLimit: Int

        /// 内存层字节上限
        public var memoryByteLimit: Int

        /// 磁盘层字节上限（超过后按最近使用时间淘汰）
        public var diskByteLimit: Int

        /// `Cache-Control` 没给 `max-age` 时的默认存活时长。
        ///
        /// ⚠️ 它决定的是"能不能**不验证**直接用"，不是"要不要留着"。
        /// 过期条目依然会被保留（ETag 仍有用），只是每次都得先去问一下服务端。
        public var defaultTimeToLive: TimeInterval

        /// 磁盘目录。**由外部注入**（而不是在包内拼 `Caches/` 路径）——
        /// 测试指向临时目录，App 层指向真实容器。`nil` = 纯内存。
        public var directory: URL?

        public init(
            memoryEntryLimit: Int = 200,
            memoryByteLimit: Int = 8 * 1024 * 1024,
            diskByteLimit: Int = 64 * 1024 * 1024,
            defaultTimeToLive: TimeInterval = 300,
            directory: URL? = nil
        ) {
            self.memoryEntryLimit = memoryEntryLimit
            self.memoryByteLimit = memoryByteLimit
            self.diskByteLimit = diskByteLimit
            self.defaultTimeToLive = defaultTimeToLive
            self.directory = directory
        }

        /// 内存 + 磁盘（App 用；磁盘目录仍需由组合根填）。
        public static let standard = Configuration()

        /// 只做内存层（单测与预览用）。
        public static func memoryOnly(
            memoryEntryLimit: Int = 200,
            memoryByteLimit: Int = 8 * 1024 * 1024,
            defaultTimeToLive: TimeInterval = 300
        ) -> Configuration {
            Configuration(
                memoryEntryLimit: memoryEntryLimit,
                memoryByteLimit: memoryByteLimit,
                defaultTimeToLive: defaultTimeToLive,
                directory: nil
            )
        }
    }

    private let configuration: Configuration
    private let clock: Clock

    private var memory: [CacheKey: CachedHTTPResponse] = [:]

    /// 最近使用顺序，**末尾最新**（LRU 用）。
    private var recency: [CacheKey] = []

    private var memoryBytes: Int = 0

    /// 磁盘用量的近似值（写入 +、删除 −）。`nil` = 尚未统计。
    /// 不做逐次精确统计：那要每次写入都遍历目录，而"数字准不准"远不如"别拖慢请求"重要。
    private var diskBytesApprox: Int?

    public init(configuration: Configuration = .standard, clock: @escaping Clock = { Date() }) {
        self.configuration = configuration
        self.clock = clock
    }

    // MARK: - 读

    /// 取缓存条目（**不判断过期** —— 见类型说明）。命中会刷新其 LRU 位置。
    public func entry(for key: CacheKey) -> CachedHTTPResponse? {
        if let cached = memory[key] {
            touch(key)
            return cached
        }
        guard let loaded = loadFromDisk(key) else { return nil }
        admit(loaded, for: key)
        return loaded
    }

    // MARK: - 写

    /// 存入一条响应。
    ///
    /// `Cache-Control: no-store` 的响应会被**拒绝入库**，且顺带清掉可能存在的旧副本 ——
    /// 尊重该指令正是它存在的意义（无视它等于替服务端做安全决定）。
    public func store(_ response: CachedHTTPResponse, for key: CacheKey) {
        guard response.isStorable else {
            remove(key)
            return
        }
        admit(response, for: key)
        writeToDisk(response, for: key)
    }

    /// 删除单个条目（内存 + 磁盘）。
    public func remove(_ key: CacheKey) {
        if let removed = memory.removeValue(forKey: key) {
            memoryBytes -= removed.byteCount
            recency.removeAll { $0 == key }
        }
        removeFromDisk(key)
    }

    /// 失效某条路径前缀下的全部条目 —— §5.4「任意写操作成功 ⇒ 失效该仓库下的相关路径」。
    ///
    /// 匹配的是 URL 的 **path**（不含 host 与查询串），所以
    /// `/repos/owner/repo/contents` 会连带失效 `/repos/owner/repo/contents/README.md`，
    /// 但不会误伤 `/repos/owner/other`。
    ///
    /// 磁盘那一半需要逐个读条目的元数据头来比对（文件名是哈希，反推不出 URL）。
    /// 代价是一次目录遍历 —— 可以接受，因为**写操作远比读少**。
    public func invalidate(pathPrefix: String) {
        let prefix = normalisedPrefix(pathPrefix)

        let doomedMemory = memory.keys.filter { matches($0.url.path, prefix: prefix) }
        for key in doomedMemory {
            if let removed = memory.removeValue(forKey: key) {
                memoryBytes -= removed.byteCount
            }
        }
        recency.removeAll { matches($0.url.path, prefix: prefix) }

        guard let directory = configuration.directory else { return }
        for fileURL in (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? [] {
            guard let urlString = EncodedEntry.readURL(from: fileURL),
                  let url = URL(string: urlString),
                  matches(url.path, prefix: prefix)
            else { continue }
            try? FileManager.default.removeItem(at: fileURL)
            diskBytesApprox = nil
        }
    }

    /// 清空全部缓存，返回释放的字节数（设置页的"清除缓存"要能报告它，§5.4）。
    @discardableResult
    public func removeAll() -> Int {
        let freed = memoryBytes + diskByteCount()

        memory.removeAll()
        recency.removeAll()
        memoryBytes = 0

        if let directory = configuration.directory {
            try? FileManager.default.removeItem(at: directory)
        }
        diskBytesApprox = nil

        return freed
    }

    // MARK: - 统计

    /// 当前占用的总字节（内存 + 磁盘）。
    public var totalByteCount: Int {
        memoryBytes + diskByteCount()
    }

    public var memoryEntryCount: Int { memory.count }

    /// 配置的默认存活时长 —— 供调用方判断"能不能直接用"。
    public var defaultTimeToLive: TimeInterval { configuration.defaultTimeToLive }

    // MARK: - 内存层

    private func admit(_ response: CachedHTTPResponse, for key: CacheKey) {
        if let previous = memory[key] {
            memoryBytes -= previous.byteCount
        }
        memory[key] = response
        memoryBytes += response.byteCount
        touch(key)
        trimMemory()
    }

    private func touch(_ key: CacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func trimMemory() {
        // `recency` 与 `memory` 同增同减，理论上不会空转；`guard` 只为杜绝死循环。
        while memory.count > configuration.memoryEntryLimit
            || memoryBytes > configuration.memoryByteLimit {
            guard let oldest = recency.first else { break }
            recency.removeFirst()
            if let removed = memory.removeValue(forKey: oldest) {
                memoryBytes -= removed.byteCount
            }
        }
    }

    // MARK: - 磁盘层

    private func loadFromDisk(_ key: CacheKey) -> CachedHTTPResponse? {
        guard let directory = configuration.directory else { return nil }
        let fileURL = directory.appendingPathComponent(key.fileName)
        // `.mappedIfSafe`：大响应不必整块读进内存才判断头部
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return nil }
        return EncodedEntry.decode(data)?.response
    }

    private func writeToDisk(_ response: CachedHTTPResponse, for key: CacheKey) {
        guard let directory = configuration.directory else { return }
        guard let encoded = EncodedEntry.encode(response, key: key) else { return }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoded.write(to: directory.appendingPathComponent(key.fileName), options: .atomic)
        } catch {
            // 写不进去就当作"这轮没缓存"。缓存失败不该让请求链路失败。
            return
        }

        if let previous = diskBytesApprox {
            diskBytesApprox = previous + encoded.count
        }
        trimDiskIfNeeded()
    }

    private func removeFromDisk(_ key: CacheKey) {
        guard let directory = configuration.directory else { return }
        let fileURL = directory.appendingPathComponent(key.fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? FileManager.default.removeItem(at: fileURL)
        diskBytesApprox = nil
    }

    /// 磁盘用量（遍历目录）。只在需要报告数字时调用 —— 不是热路径。
    private func diskByteCount() -> Int {
        guard let directory = configuration.directory else { return 0 }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []

        return entries.reduce(into: 0) { total, fileURL in
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += size
        }
    }

    private func trimDiskIfNeeded() {
        guard let directory = configuration.directory else { return }

        // 先看近似值，避免每次写入都遍历目录。第一次（近似值未知）统计一次。
        let approximate: Int
        if let known = diskBytesApprox {
            approximate = known
        } else {
            approximate = diskByteCount()
            diskBytesApprox = approximate
        }
        guard approximate > configuration.diskByteLimit else { return }

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        )) ?? []

        // 最久未修改的先删。用文件的 mtime 而不是内存里的 LRU 顺序：跨启动之后
        // 内存顺序是从零开始的，只有 mtime 记得住"上次真正用到是什么时候"。
        let sorted = entries.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }

        var total = approximate
        for fileURL in sorted where total > configuration.diskByteLimit {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard (try? FileManager.default.removeItem(at: fileURL)) != nil else { continue }
            total -= size
        }
        diskBytesApprox = total
    }

    /// 归一到**无尾斜杠**形式，匹配规则集中到 `matches(_:prefix:)` 一处。
    private func normalisedPrefix(_ prefix: String) -> String {
        prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
    }

    /// `path` 是否落在 `prefix` 之下。
    ///
    /// ⚠️ **两支缺一不可**：
    /// - 少了「相等」⇒ 传 `/repos/o/r/contents` 时**目录清单自身不会被失效**，
    ///   而写文件之后目录清单恰恰是第一个变了的资源（最初就是这么漏的）。
    /// - 少了补斜杠 ⇒ `/repos/o/r/contents-archive` 会被 `/repos/o/r/contents` 误伤。
    private func matches(_ path: String, prefix: String) -> Bool {
        guard !prefix.isEmpty else { return true }
        if path == prefix { return true }
        return path.hasPrefix(prefix + "/")
    }
}

/// 磁盘条目的编解码。
///
/// 布局：`[4 字节大端元数据长度][元数据 JSON][响应体原始字节]`。
///
/// 为什么不用"整个包一层 JSON + base64 body"：base64 会把响应体撑大 33%，
/// 而缓存的价值就在于装得下 —— 尤其头像与 diff 原文这类体积大的响应。
/// 这个布局的代价是需要自己处理字节序，收益是**零膨胀**。
enum EncodedEntry {

    struct Metadata: Codable {
        let url: String
        let statusCode: Int
        let headers: [String: String]
        let etag: String?
        let fetchedAt: Date
    }

    static func encode(_ response: CachedHTTPResponse, key: CacheKey) -> Data? {
        let metadata = Metadata(
            url: key.url.absoluteString,
            statusCode: response.statusCode,
            headers: response.headers.rawValues,
            etag: response.etag,
            fetchedAt: response.fetchedAt
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let metadataBytes = try? encoder.encode(metadata) else { return nil }

        var out = Data()
        var length = UInt32(metadataBytes.count).bigEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(metadataBytes)
        out.append(response.body)
        return out
    }

    static func decode(_ data: Data) -> (key: CacheKey, response: CachedHTTPResponse)? {
        guard let parsed = parseHeader(data) else { return nil }

        let body = data.subdata(in: parsed.bodyOffset..<data.count)
        let metadata = parsed.metadata

        return (
            key: CacheKey(parsed.url),
            response: CachedHTTPResponse(
                statusCode: metadata.statusCode,
                headers: HTTPHeaders(metadata.headers),
                body: body,
                etag: metadata.etag,
                fetchedAt: metadata.fetchedAt
            )
        )
    }

    /// 只取 URL —— 供"按路径前缀失效"遍历磁盘时用，避免解析整条响应。
    static func readURL(from fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return nil }
        return parseHeader(data)?.metadata.url
    }

    private static func parseHeader(
        _ data: Data
    ) -> (metadata: Metadata, url: URL, bodyOffset: Int)? {
        guard data.count >= 4 else { return nil }

        let length = data.prefix(4).withUnsafeBytes { raw -> UInt32 in
            raw.loadUnaligned(as: UInt32.self).bigEndian
        }
        let metadataEnd = 4 + Int(length)
        guard metadataEnd <= data.count else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let metadata = try? decoder.decode(Metadata.self, from: data.subdata(in: 4..<metadataEnd)),
              let url = URL(string: metadata.url)
        else { return nil }

        return (metadata, url, metadataEnd)
    }
}
