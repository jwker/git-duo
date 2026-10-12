import Foundation

/// 缓存键 —— 一个**完整 URL**。
///
/// 依据：TECH_SPEC §5.2 末尾「ETag 是**按 URL 维度**的，同一数据用不同参数
/// （`?ref=`、`?state=`、`per_page=`）请求会拿到不同 ETag，**缓存 key 必须包含完整查询串**」。
///
/// ⚠️ 这条不是理论洁癖：探索页的缓存键漏了"语言/日期"任一维度，用户每切一次筛选都会
/// 真的发一次请求（§13.2 预算里把这件事单列为纪律 1）。用整个 URL 作键是**结构性**地
/// 满足该要求 —— 不存在"忘了把某个参数拼进去"的可能。
public struct CacheKey: Hashable, Sendable, CustomStringConvertible {

    public let url: URL

    /// 同一个 URL 的**另一种表示**（目前只有一条通道用到：`Accept: application/vnd.github.raw`）。
    ///
    /// ## 为什么必须有（2026-10-12，修的真缺陷）
    ///
    /// `contents`（JSON 外壳）与 `rawFile`（裸字节）在数据层是**同一个 URL**
    /// （`/repos/{o}/{r}/contents/{path}`），差别只在 `Accept` 头。
    /// 键里不带它，两条表示会**互相污染**：
    ///
    /// 1. `contents` 先跑（JSON）⇒ 缓存写下 JSON 与它的 ETag；
    /// 2. `rawFile` 随后请求同一 URL ⇒ **命中上面那一条** ⇒ 带上**同一个 ETag**
    ///    ⇒ 服务端回 **304**（在它看来"你要的那份没变"）⇒ transport 把
    ///    **缓存里的 JSON** 当响应体交出去；
    /// 3. 拿"一张图"的代码得到一段 JSON 文本 ⇒ `UIImage(data:)` 为 `nil`。
    ///
    /// 症状：**md 正文里的图片全部显示「图片加载失败」**，而且**一旦发生就再也出不来**
    /// —— 304 永远回那条 JSON。反过来（先 raw 后 JSON）则是"JSON 解析失败"。
    ///
    /// ## ⚠️ 默认 `""` 是有意保留的
    ///
    /// 绝大多数请求只有一种表示，它们的键**逐字未变**（`fileName` 也不变）
    /// ⇒ 升级到这一版不会把已落盘的缓存整体作废。
    public let variant: String

    public init(_ url: URL, variant: String = "") {
        self.url = url
        self.variant = variant
    }

    public var description: String {
        variant.isEmpty ? url.absoluteString : "\(url.absoluteString) [\(variant)]"
    }

    /// 磁盘文件名。
    ///
    /// 用 SHA256 而不是 URL 本身：URL 里含 `/`、`?`、`&`，直接当文件名要么非法、
    /// 要么需要层层转义（而转义后的长度可能超过文件系统的名字上限）。
    /// 哈希也顺带避免了"文件名泄露查询内容"（搜索词会出现在 URL 里）。
    ///
    /// internal 而非 private：测试要断言"不同 URL 不同名、同一 URL 稳定同名"。
    var fileName: String {
        // ⚠️ 变体为空时哈希的输入**与原实现逐字一致**（见 `variant` 那条说明）——
        //    这样"只有一种表示"的那些条目在升级后仍是同一个文件，缓存不作废。
        let material = variant.isEmpty ? url.absoluteString : "\(variant)\n\(url.absoluteString)"
        // 局部 import：只有这里用到哈希，不必让整个包依赖 CryptoKit（系统框架，非第三方）
        let digest = SHA256Digest.hex(of: Data(material.utf8))
        return "\(digest).cache"
    }
}

/// 一条缓存下来的 HTTP 响应。
///
/// 只存**原始**响应（状态码 / 头 / 体 / ETag / 抓取时刻）—— 不存已解码的领域模型：
/// 后者属于 L1，而领域模型要到各 Feature 落地时才定义（§5.1）。
public struct CachedHTTPResponse: Sendable, Equatable {

    public let statusCode: Int
    public let headers: HTTPHeaders
    public let body: Data
    /// 响应的 `ETag`；`nil` 表示服务端没给（那就没有条件请求可用）。
    public let etag: String?
    public let fetchedAt: Date

    public init(
        statusCode: Int,
        headers: HTTPHeaders = HTTPHeaders([:]),
        body: Data,
        etag: String? = nil,
        fetchedAt: Date
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.etag = etag
        self.fetchedAt = fetchedAt
    }

    public var byteCount: Int { body.count }

    /// 是否已过可缓存时限。
    ///
    /// 时限优先取自响应自己的 `Cache-Control: max-age=`（§5.1「L2 生命周期：按 `Cache-Control`」），
    /// 头里没说才用调用方给的默认值。
    public func isExpired(now: Date, defaultTimeToLive: TimeInterval) -> Bool {
        let ttl = maxAge(fallback: defaultTimeToLive)
        guard ttl > 0 else { return true }
        return now.timeIntervalSince(fetchedAt) >= ttl
    }

    /// 由 `Cache-Control` 决定这条响应**该不该**被缓存。
    ///
    /// `no-store` 必须尊重 —— 它正是"别把这个响应留在磁盘上"的标准表达，
    /// 无视它等于替服务端做了安全决定。
    public var isStorable: Bool {
        !CacheDirective.parse(headers["cache-control"]).contains(.noStore)
    }

    private func maxAge(fallback: TimeInterval) -> TimeInterval {
        let directives = CacheDirective.parse(headers["cache-control"])
        for directive in directives {
            if case let .maxAge(seconds) = directive { return seconds }
        }
        return fallback
    }
}

/// `Cache-Control` 里我们关心的几种指令。
///
/// 只解析这几种：其余（`private` / `public` / `must-revalidate` …）对本项目的决策没有影响，
/// 收着不用反而会让人以为它们被处理过了。
public enum CacheDirective: Sendable, Equatable {

    /// `no-store` —— 任何地方都不要留
    case noStore

    /// `max-age=N`
    case maxAge(TimeInterval)

    /// 解析逗号分隔的指令列表；认不出的忽略（不报错 —— 一个头的写法不该让请求失败）。
    public static func parse(_ raw: String?) -> [CacheDirective] {
        guard let raw, !raw.isEmpty else { return [] }

        return raw.split(separator: ",").compactMap { piece in
            let trimmed = piece.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed == "no-store" { return .noStore }
            if trimmed.hasPrefix("max-age=") {
                let value = trimmed.dropFirst("max-age=".count)
                guard let seconds = TimeInterval(value) else { return nil }
                return .maxAge(seconds)
            }
            return nil
        }
    }
}
