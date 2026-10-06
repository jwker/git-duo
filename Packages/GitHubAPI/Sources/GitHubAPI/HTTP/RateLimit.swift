import Foundation

/// 一次响应携带的配额快照（`x-ratelimit-*` 三个头）。
///
/// 依据：TECH_SPEC §4.5。GitHub 对**每个请求**都会返回当前桶的余量，
/// 所以不必额外调 `GET /rate_limit` 就能在设置页展示"剩余配额"。
///
/// ⚠️ **三个头缺一不可**，缺任意一个就返回 `nil`（而不是补 0）——
/// 补 0 会被读成"配额已耗尽"，把一个"这个端点没返回该头"误报成"额度用光了"。
/// 这是典型的"错误的值比没有值更危险"。
public struct RateLimitSnapshot: Sendable, Equatable {

    public let resource: RateLimitResource
    public let limit: Int
    public let remaining: Int
    public let resetAt: Date

    public init?(headers: HTTPHeaders) {
        guard let limit = headers.intValue("x-ratelimit-limit"),
              let remaining = headers.intValue("x-ratelimit-remaining"),
              let reset = headers.unixDate("x-ratelimit-reset")
        else { return nil }

        self.resource = RateLimitResource(rawValue: headers["x-ratelimit-resource"] ?? "")
        self.limit = limit
        self.remaining = remaining
        self.resetAt = reset
    }

    public var isExhausted: Bool { remaining <= 0 }
}

/// 配额桶。GitHub 的桶彼此独立（§4.5）：`core` 用完了不影响 `search`。
///
/// 用 `other` 兜住未知值而不是删除该字段：将来 GitHub 加新桶（或本项目开始用搜索代码桶）
/// 时，快照仍然可用，不至于整个 `RateLimitSnapshot` 构造失败。
public enum RateLimitResource: Sendable, Equatable {

    /// REST 主桶：5,000 请求/小时
    case core

    /// 搜索桶（仓库 / 用户 / Issue）：30 请求/分钟
    case search

    /// GraphQL：5,000 点/小时
    case graphql

    /// 代码搜索：约 10 请求/分钟（本项目按 9 保守预算，§4.5）
    case codeSearch

    /// 其余/未知桶
    case other(String)

    /// 映射 GitHub 的实际取值。⚠️ 官方在不同文档里对代码搜索桶的命名不完全一致，
    /// 因此把两种写法都收进来；认不出的一律落 `other`，**不猜**。
    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "core":
            self = .core
        case "search":
            self = .search
        case "graphql":
            self = .graphql
        case "code_search", "codesearch":
            self = .codeSearch
        default:
            self = .other(rawValue)
        }
    }
}
