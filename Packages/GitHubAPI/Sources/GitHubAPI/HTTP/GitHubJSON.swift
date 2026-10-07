import Foundation

/// 本包**统一**的 JSON 解码器工厂（`HTTPResponse.decode` 与 `GitHubGraphQLClient` 共用）。
///
/// ## 为什么必须收在一处
///
/// **GitHub 的时间戳是 ISO 8601 字符串，而 `JSONDecoder` 的默认日期策略是 `.deferredToDate`**
/// —— 后者要求"距 2001-01-01 的秒数"（`Double`）。两者形状毫无交集，直接解必然失败，
/// 而报错信息指向的是那个 `Date` 字段，**不是**"日期策略没设"，
/// 很容易被误读成"GitHub 改了响应形状"。切片 4 的探索榜、仓库详情、Releases 全带时间戳，
/// 一旦有第二个解码器漏配，症状就是"某一页整页空白"。
///
/// 做成静态工厂而不是全局单例：`JSONDecoder` 是引用类型且非 `Sendable`，
/// 全局 `static let` 在 Swift 6 严格并发下要么编译报错、要么得打成 `nonisolated(unsafe)`
/// —— 而"每个请求造一个解码器"的代价可以忽略（本来 `HTTPResponse.decode` 也是每次新建）。
enum GitHubJSON {

    /// 造一个配置好的解码器。
    ///
    /// 只动了**日期策略**：键名一律走各 DTO 自己的 `CodingKeys`。
    /// 不用 `.convertFromSnakeCase` —— 它对 `spdx_id` / `nameWithOwner` / `pull_request`
    /// 这类名字的处理全靠约定，且"某个键没转过来"在 Swift 里**不报错**，
    /// 只表现为该字段静默为 `nil`（或可选字段为"没有"）。显式 `CodingKeys` 是一份
    /// 看得见、可 grep 的契约。
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = GitHubDate.parse(text) else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "不是可识别的 ISO 8601 时间戳：\(text)"
                    )
                )
            }
            return date
        }
        return decoder
    }
}

/// GitHub 时间戳的解析器。
///
/// **两种形状都要认**：
/// - `2026-08-05T12:34:56Z` —— REST 的常规形状
/// - `2026-08-05T12:34:56.789Z` —— 带小数秒（少数端点的 `updated_at` 会这样）
///
/// 为什么不直接用 `.iso8601`（底层是 `ISO8601DateFormatter` 的 `.withInternetDateTime`）：
/// 官方把它描述为"不接受小数秒"，而一条带小数秒的时间戳会让**整个列表**解码失败
/// —— 代价是"整页拿不到内容"，而它只差了一个小数点。
enum GitHubDate {

    /// ⚠️ 顺序有意为"先严后宽"。
    ///
    /// **本机实测（macOS 26 / 当前 SDK）：两支各自都能解出上面两种形状**，
    /// 也就是说今天留第二支属于冗余。之所以仍然留着：这件事**没有契约**
    /// （`Date.ISO8601FormatStyle` 的小数秒容错范围在文档里没有承诺），
    /// 只在这一个 SDK 版本上验过 —— 而它失效的后果是"带小数秒的响应整页解不出"。
    /// 四行代码换掉这一类失败，划算。
    ///
    /// 若将来确认某一支恒为冗余，删它之前请先补一个断言两种形状的单测。
    private static let styles: [Date.ISO8601FormatStyle] = [
        Date.ISO8601FormatStyle(includingFractionalSeconds: true),
        Date.ISO8601FormatStyle(includingFractionalSeconds: false),
    ]

    static func parse(_ text: String) -> Date? {
        for style in styles {
            if let date = try? style.parse(text) { return date }
        }
        return nil
    }
}
