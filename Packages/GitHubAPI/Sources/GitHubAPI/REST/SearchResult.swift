import Foundation

/// 搜索类端点的**通用返回形状** —— `{ total_count, incomplete_results, items }`。
///
/// ## 为什么值得泛型化
///
/// 四个搜索端点（repositories / users / code / issues）的响应外皮**逐字相同**，
/// 只有 `items` 的元素类型不同。四份各自手写一遍的代价不是"多几行"，而是
/// **其中一份迟早漏掉 `total_count` 或 `incomplete_results`** —— 而漏掉的症状是静默的：
/// 那个范围的结果标题永远显示 `0 个结果`，或者永远不提示"结果不完整"。
///
/// ## `totalCount` 与「已加载条数」是两件事
///
/// - **搜索页**用它（决策 #44、§9.2）：标题 `{范围名} · {N} 个结果` 里的 N 就是服务端
///   `total_count`，与 GitHub 网页端一致；
/// - **探索榜不用**它 —— 那边（PRD §4.12）压根不显示条数：列表标题那一行
///   （`新星榜 · 5 个仓库`）2026-10-16 已整行删掉（走查第 **78** 条）。
///   那是另一个页面的另一条口径，不是遗漏。
///
/// ⚠️ 它与决策 #38「拒用服务端计数」**不矛盾**：那边拒的是 `open_issues_count`
/// —— 它把列表**刻意滤掉**的 PR 也算进去 ⇒ 数字必然是错的。这里的 `total_count`
/// 恰好就是"匹配本次查询的总数"。两者共用同一条判据：
/// **数字必须是对屏幕上的这个列表的真话。**
public struct SearchResult<Item: Sendable>: Sendable {

    public let items: [Item]

    /// 服务端 `total_count`：**该条查询**匹配的总数（不是这一页的条数）。
    public let totalCount: Int

    /// 下一页的**完整 URL**；`nil` = 已到底（§4.4）。
    public let nextCursor: URL?

    /// `incomplete_results` —— "这一页少了东西"的唯一信号（§4.6.3）。
    ///
    /// 它不影响解码，所以极易被忽略；但丢掉它等于把这个信号永久删掉，之后想提示也没得提示。
    public let incompleteResults: Bool

    public var hasMore: Bool { nextCursor != nil }

    public var isEmpty: Bool { items.isEmpty }

    public init(items: [Item], totalCount: Int, nextCursor: URL?, incompleteResults: Bool) {
        self.items = items
        self.totalCount = totalCount
        self.nextCursor = nextCursor
        self.incompleteResults = incompleteResults
    }
}

extension SearchResult where Item: Decodable {

    /// 由一次响应解出一页 —— **四个搜索端点唯一的解码入口**。
    ///
    /// 搜索的响应是**对象**而不是裸数组，所以走不了 `GitHubRESTClient.page(...)`
    /// （那个按 `[T]` 解）。下一页仍走 `Page.nextCursor(from:)`：
    /// `Link` 头的解析只该有一处实现（它有个"不能 `split` 逗号"的坑）。
    static func decoded(from response: HTTPResponse) throws -> SearchResult<Item> {
        let envelope = try response.decode(Envelope<Item>.self)
        return SearchResult(
            items: envelope.items,
            totalCount: envelope.totalCount,
            nextCursor: Page<Item>.nextCursor(from: response.headers),
            incompleteResults: envelope.incompleteResults
        )
    }

    /// 响应外皮。键名逐字写进 `CodingKeys`（**不用** `.convertFromSnakeCase`：
    /// "某个键没转过来"在 Swift 里不报错，只表现为该字段静默缺席 —— 见 `GitHubJSON`）。
    ///
    /// ⚠️ 泛型参数叫 `Element` 而不是 `Item`：它嵌在 `SearchResult<Item>` 的扩展里，
    /// 同名会把外层那个**遮蔽**掉，而编译器给的是一句"generic parameter shadows"，
    /// 看起来像命名问题、实际会让整段解码的语义变得难以推理。
    private struct Envelope<Element: Decodable>: Decodable {
        let items: [Element]
        let totalCount: Int
        let incompleteResults: Bool

        private enum CodingKeys: String, CodingKey {
            case items
            case totalCount = "total_count"
            case incompleteResults = "incomplete_results"
        }
    }
}

/// 四个搜索端点共用的两件小事（**收在一处**，免得四个端点各写一遍、各错一处）。
enum SearchEndpointSupport {

    /// 校验 `q`（**去空白后**返回）。
    ///
    /// 空 `q` 服务端必然回 422，而**那次失败照样消耗搜索配额**（30/min，代码那一档 10/min）
    /// —— 所以就地拦掉，别让它出网。这是第二道防线：第一道在领域层
    /// （`SearchQueryBuilder.readiness`），那里连"代码范围只有限定符"都拦得住。
    static func validatedQuery(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitHubError.validation(["q: 搜索关键词不能为空"])
        }
        return trimmed
    }

    /// 搜索端点的查询项。
    ///
    /// ⚠️ **`sort` 为 `nil` 时 `sort` 与 `order` 两个参数都不带**：那才是服务端的
    /// "best match"（相关性）排序 —— 搜索页要的就是它，而 `sort=best+match`
    /// 并不是一个合法取值。探索榜各带各的 `sort`，路径不受影响。
    static func queryItems(
        query: String,
        perPage: Int,
        sort: String? = nil,
        order: String = "desc"
    ) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "q", value: query)]
        if let sort {
            items.append(URLQueryItem(name: "sort", value: sort))
            // `order` 只在有 `sort` 时有意义（官方：不给 sort 时它被忽略）。
            items.append(URLQueryItem(name: "order", value: order))
        }
        items.append(URLQueryItem(name: "per_page", value: String(perPage)))
        return items
    }
}
