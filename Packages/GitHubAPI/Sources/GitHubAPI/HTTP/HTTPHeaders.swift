import Foundation

/// HTTP 消息头的**大小写不敏感**包装。
///
/// 为什么不能直接用 `[String: String]`：HTTP 头字段名**不区分大小写**（RFC 7230 §3.2），
/// 而 GitHub 在不同端点、不同代理链路上返回的大小写并不稳定 ——
/// `ETag` / `Etag`、`X-RateLimit-Remaining` / `x-ratelimit-remaining` 都出现过。
/// 拿原字典直接查会**间歇性查不到**，而这类缺陷只在生产环境偶发：
/// 单测里用的是从文档复制粘贴的固定大小写，会一直是绿的。
///
/// 所以构造时统一转小写落库，取值也转小写 —— 让"查得到"成为类型保证。
public struct HTTPHeaders: Sendable, Equatable {

    /// 键一律为小写。
    private let storage: [String: String]

    /// - Parameter raw: 任意大小写的原始头。
    ///
    /// ⚠️ **大小写不同的同名字段会归一化成一个**（`ETag` 与 `etag` 只留一项），
    /// 但**不承诺**留下的是哪一个 —— 入参是无序字典，迭代顺序取决于哈希种子。
    /// 现实中这不是问题：`URLSession` 给的 `allHeaderFields` 已经合并过重复字段，
    /// 而 HTTP 本身也不允许同一字段出现两次。
    public init(_ raw: [String: String]) {
        var storage: [String: String] = [:]
        storage.reserveCapacity(raw.count)
        for (name, value) in raw {
            storage[name.lowercased()] = value
        }
        self.storage = storage
    }

    /// 从 `HTTPURLResponse` 构造（`allHeaderFields` 的键是 `AnyHashable`，需过滤）。
    public init(response: HTTPURLResponse) {
        var raw: [String: String] = [:]
        raw.reserveCapacity(response.allHeaderFields.count)
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String else { continue }
            raw[name] = String(describing: value)
        }
        self.init(raw)
    }

    /// 大小写不敏感取值。
    public subscript(_ name: String) -> String? {
        storage[name.lowercased()]
    }

    public var isEmpty: Bool { storage.isEmpty }

    public var count: Int { storage.count }

    /// 全部头（键为小写）。供"把响应原样存起来"这类需要完整复制的场合使用
    /// （缓存落盘时要保住响应头，否则 304 之后重建的响应会丢 `Content-Type`）。
    public var rawValues: [String: String] { storage }

    /// 整数头的便捷读取（`x-ratelimit-remaining`、`retry-after` 的秒数形式等）。
    func intValue(_ name: String) -> Int? {
        self[name].flatMap(Int.init)
    }

    /// Unix 秒时间戳头的便捷读取（`x-ratelimit-reset`）。
    func unixDate(_ name: String) -> Date? {
        self[name]
            .flatMap(TimeInterval.init)
            .map { Date(timeIntervalSince1970: $0) }
    }
}
