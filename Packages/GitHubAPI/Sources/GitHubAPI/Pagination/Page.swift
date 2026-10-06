import Foundation

/// 一页结果 —— REST 列表接口的通用返回形状。
///
/// 依据：TECH_SPEC §4.4（`items` + `nextCursor`；列表默认 `per_page=30`）。
///
/// 设计取舍：**只承载"这一页拿到了什么"与"下一页在哪"**，不承载 `isLoading` / `error` /
/// `canLoadMore` 这类展示状态 —— 那些属于各列表 ViewModel 的 `state`（§4.4 末段），
/// 混进来会让"数据"与"数据怎么显示"绑死，分页逻辑就没法脱离 UI 单测了。
public struct Page<Item: Sendable>: Sendable {

    public let items: [Item]

    /// 下一页的**完整 URL**（取自 `Link` 头的 `rel="next"`）；`nil` 表示已到底。
    ///
    /// 之所以存完整 URL 而不是页码：GitHub 的 `next` 可能携带 `?page=` 之外的参数
    /// （搜索接口的游标形式就是如此），自己拼页码会在那些端点悄悄翻错页。
    public let nextCursor: URL?

    /// 本次响应的头。保留它是因为：
    /// ① 配额快照（`rateLimit`）由此派生；② 搜索接口的 `total_count` 之类偶尔要看。
    public let headers: HTTPHeaders

    /// 本次响应携带的配额快照（头里没有则为 `nil`）。派生而非存储，避免两份真相。
    public var rateLimit: RateLimitSnapshot? { RateLimitSnapshot(headers: headers) }

    public var hasMore: Bool { nextCursor != nil }

    public var isEmpty: Bool { items.isEmpty }

    public init(items: [Item], nextCursor: URL?, headers: HTTPHeaders = HTTPHeaders([:])) {
        self.items = items
        self.nextCursor = nextCursor
        self.headers = headers
    }

    /// 直接由响应头推出下一页 —— REST 客户端的常规入口。
    public init(items: [Item], headers: HTTPHeaders) {
        self.init(items: items, nextCursor: Page.nextCursor(from: headers), headers: headers)
    }

    /// 从响应头取下一页地址。
    ///
    /// 单独抽出来是为了让分页的其余部分（要不要继续加载、缓存怎么命中）能独立测试，
    /// 不必每次都组装一个完整的 `Page`。
    public static func nextCursor(from headers: HTTPHeaders) -> URL? {
        headers["link"].map { LinkHeader($0).next } ?? nil
    }

    /// 映射元素类型（列表接口拿到 DTO 后转领域模型时用）。
    public func map<Mapped: Sendable>(_ transform: (Item) throws -> Mapped) rethrows -> Page<Mapped> {
        Page<Mapped>(items: try items.map(transform), nextCursor: nextCursor, headers: headers)
    }
}
