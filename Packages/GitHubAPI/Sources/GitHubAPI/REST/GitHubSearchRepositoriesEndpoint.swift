import Foundation

/// 仓库搜索 —— `GET /search/repositories`（TECH_SPEC §4.6.1、§4.6.3、§9.10.1、决策 #37）。
///
/// ## 一个端点，两个调用方
///
/// 1. **探索页双榜**（本切片）：`q=created:>=… stars:>50` / `q=pushed:>=… stars:>50`，
///    限定符由 `GitDuoKit` 的 `ExploreQueryBuilder` 拼好，本类型只负责发出去。
/// 2. **搜索页「仓库」范围**（切片 5）：`q=` 就是用户输入。
///
/// ## ⚠️ 它消耗的是**独立且最紧**的那一档配额
///
/// `search` 桶 **30 次/分钟**，与 `core`（5,000/小时）完全分开计（§4.5、§13.2）。
/// 所以：
/// - **每一次出网都显式声明 `rateLimitResource: .search`** —— 漏了不会报错，
///   只会让闸门按"没有限额"放行，然后在某次连点里打爆搜索配额，
///   连**搜索页一起**拖下水（两个页面共用这一个桶）。
/// - 依赖上层的缓存（决策 #37 的内存 LRU）与 300ms 防抖来压请求数 ——
///   本类型自己不缓存、不防抖：那两件事一旦做了，分页与"下拉刷新只失效当前组合"
///   就没法脱离 UI 单测了（§4.4 的分工）。
public struct GitHubSearchRepositoriesEndpoint: Sendable {

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session —— 理由同
    /// `GitHubRepositoryEndpoint`：生产里所有端点必须共用同一个 `GitHubRESTClient`，
    /// 否则缓存会分成两份、配额各算各的（而它不会报错）。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    /// 搜一页仓库。
    ///
    /// - Parameters:
    ///   - query: `q=` 的值（限定符串）。**不能为空** —— GitHub 会回 422，
    ///     而那次失败**照样消耗搜索配额**，所以在这里就地拦掉（见下方 `guard`）。
    ///   - sort: 服务端排序字段。`stars` 是探索新星榜的天然回退序（无基线时按总 Star 降序，
    ///     §9.10.2）；`updated` 供活跃榜使用 —— 但活跃榜的**最终顺序**由客户端按
    ///     `pushed_at` 重排（§9.10.1），服务端排序只是把最活跃的那批先捞进来。
    ///   - order: `desc` / `asc`。
    ///   - perPage: 首页 30（与其余列表一致，§4.4）。上限 100，超过会被 GitHub 夹到 100
    ///     —— 夹这件事**不会报错**，只会静默改变分页步长，所以别传大数。
    ///   - cursor: 上一页的 `nextCursor`；`nil` 取第一页。
    ///
    /// ⚠️ **续页必须原样用 `cursor`**：搜索的 `Link: rel="next"` 是带游标的完整 URL，
    /// 自己拼 `?page=n` 会在搜索端点上翻错页（§4.4 已为此写过一次教训）。
    public func search(
        query: String,
        sort: String,
        order: String = "desc",
        perPage: Int = 30,
        cursor: URL? = nil
    ) async throws -> SearchRepositoriesResult {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // 搜索配额是全局最紧的一档（30/分钟），而空 q 必然 422 ——
            // 这一次请求**会白白花掉一格**。就地拦掉，别让它出网。
            throw GitHubError.validation(["q: 搜索关键词不能为空"])
        }

        let response: HTTPResponse
        if let cursor {
            response = try await client.send(.get(cursor, rateLimitResource: .search))
        } else {
            response = try await client.send(
                .get(
                    client.url(
                        "search/repositories",
                        query: [
                            URLQueryItem(name: "q", value: query),
                            URLQueryItem(name: "sort", value: sort),
                            URLQueryItem(name: "order", value: order),
                            URLQueryItem(name: "per_page", value: String(perPage))
                        ]
                    ),
                    rateLimitResource: .search
                )
            )
        }

        let envelope = try response.decode(Envelope.self)

        return SearchRepositoriesResult(
            items: envelope.items,
            // 复用 `Page` 的解析 —— `Link` 头只该有一处实现（它有个"不能 split 逗号"的坑）
            nextCursor: Page<SearchRepositoryDTO>.nextCursor(from: response.headers),
            incompleteResults: envelope.incompleteResults
        )
    }

    // MARK: - 私有形状

    /// ⚠️ 搜索的响应是**对象**（`{ total_count, incomplete_results, items }`），不是裸数组
    /// —— 所以走不了 `client.page(...)`（那个按 `[T]` 解）。
    ///
    /// 只声明用得上的两个字段：
    /// - **`total_count` 有意不取**：它**会超过可分页上限**（搜索最多翻到 1000 条，§9.10.1）
    ///   ⇒ 显示"共 3,847 个"等于承诺一个用户永远翻不到的数字，
    ///   而这正是本项目说的"看起来正常的错值"。列表标题用**已加载条数**
    ///   （PRD §4.12 的 `新星榜 · 5 个仓库` 就是加载数）。
    /// - `incomplete_results` 取，因为它是"这一页少了东西"的唯一信号（见该字段的说明）。
    private struct Envelope: Decodable, Sendable {
        let items: [SearchRepositoryDTO]
        let incompleteResults: Bool

        private enum CodingKeys: String, CodingKey {
            case items
            case incompleteResults = "incomplete_results"
        }
    }
}
