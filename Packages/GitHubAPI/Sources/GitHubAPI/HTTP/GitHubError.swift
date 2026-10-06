import Foundation

/// 网络层的**统一错误模型**。
///
/// 依据：TECH_SPEC §4.3。
///
/// **与 §4.3 的差异（两处，均已拍板）**：
/// 1. §4.3 列了 8 个 case，但**没给 5xx 留落点**，而「幂等 GET 有限退避重试」恰恰需要以 5xx
///    作为触发条件 ⇒ 补 `serverError(status:)`，共 9 个。该 case 同时是**兜底**：
///    5xx 与"其余未被上面归类"的状态码（400 / 415 / 451 …）都落这里，
///    因此**判定可否重试必须看 `status` 是否 5xx**，不能只看 case 名。
/// 2. `graphQLErrors` 除消息外**还携带 `data` 的原始 JSON**（部分成功不能把已有数据丢掉），
///    详见该 case 的说明。
///
/// 两条容易踩的坑（§4.3 原文照录）：
/// 1. **404 不等于不存在** —— 私有仓库无权限时 GitHub 也返回 404。
///    UI 文案必须写「仓库不存在或你没有访问权限」，**不得**断言「不存在」。
/// 2. **GraphQL 的错误在 body 里** —— 返回 `200 OK` 且 `body.errors` 有值，
///    甚至 `data` 与 `errors` 并存（部分成功）。**绝不能只看 HTTP 状态码判定成功**。
///
/// ⚠️ 所有 case 都**不得**携带令牌、授权码或 secret —— 它们会被拼进面向用户的文案，也会进日志。
public enum GitHubError: Error, @unchecked Sendable {

    /// 401 —— 令牌失效。数据层据此触发"刷新一次并重放"（§3.2 第 2 条）。
    case unauthorized

    /// 403 且**不是**配额问题 ⇒ 权限不足。`message` 来自 body，可能为空。
    case forbidden(String)

    /// 404 —— **资源不存在与无权访问被 GitHub 混同**，调用方不得替用户断定是哪一种。
    case notFound

    /// 409 —— 提交冲突（SHA 已过期）。
    case conflict

    /// 422 —— 参数校验失败，逐条列出（`field: code` 形式）。
    case validation([String])

    /// 配额耗尽。`isSecondary` 区分"二级限流（突发速率）"与"主桶耗尽"。
    case rateLimited(resetAt: Date, isSecondary: Bool)

    /// 5xx **及任何未被归类的状态码**（兜底）。重试判定必须再看 `status`。
    case serverError(status: Int)

    /// GraphQL：HTTP 200 但 `body.errors` 非空。
    ///
    /// ⚠️ **为什么还带一份 `partialData`（2026-10-06 用户拍板）**：GraphQL 会**部分成功** ——
    /// `data` 与 `errors` 同时存在（一个子字段解析失败，其余字段照常返回）。
    /// 只抛一个"错误"会让那批**已经拿到的**数据被白白丢掉，用户看到整页空白、
    /// 而其实 90% 的内容就在响应里。所以错误本身携带 `data` 的原始 JSON，
    /// 调用方可以自行解码出能用的那部分再决定怎么降级展示。
    ///
    /// - Parameters:
    ///   - messages: 逐条错误，已拼成 `path: message` 形式（无 path 时只有 message）。
    ///   - partialData: `data` 字段的**原始 JSON 字节**；`data` 缺失或为 `null` 时为 `nil`
    ///                  （即"完全失败"，没有任何可用数据）。
    ///
    /// ⚠️ 用原始字节而不是泛型：错误类型不认识各查询的 DTO，硬塞泛型参数会把它变成
    ///    一个"谁都得带着走的类型参数"。解码是调用方的事 —— 它才知道自己问了什么。
    case graphQLErrors(messages: [String], partialData: Data?)

    /// 网络层（连不上、超时、断网）。**注意与 5xx 区分**：这里是"没拿到响应"。
    case transport(URLError)

    /// 响应体解码失败。
    case decoding(any Error)
}

// MARK: - Equatable（手写）

extension GitHubError: Equatable {

    /// `decoding` 只比较 case 本身 —— 底层 `Error` 不具可比性，
    /// 而测试关心的是"错在了哪一类"，不是"底层报错的字符串长什么样"。
    public static func == (lhs: GitHubError, rhs: GitHubError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized),
             (.notFound, .notFound),
             (.conflict, .conflict),
             (.decoding, .decoding):
            return true

        case let (.forbidden(l), .forbidden(r)):
            return l == r

        case let (.validation(l), .validation(r)):
            return l == r

        case let (.rateLimited(lReset, lSecondary), .rateLimited(rReset, rSecondary)):
            return lReset == rReset && lSecondary == rSecondary

        case let (.serverError(l), .serverError(r)):
            return l == r

        case let (.graphQLErrors(lMessages, lData), .graphQLErrors(rMessages, rData)):
            return lMessages == rMessages && lData == rData

        case let (.transport(l), .transport(r)):
            return l.code == r.code

        default:
            return false
        }
    }
}

// MARK: - 由 HTTP 响应判定

extension GitHubError {

    /// 把一次 HTTP 响应归一化成错误；**返回 `nil` 表示 2xx，调用方可继续解码**。
    ///
    /// - Parameters:
    ///   - status: HTTP 状态码
    ///   - headers: 已归一化的响应头（配额与 `Retry-After` 都在这里）
    ///   - body: 响应体（403 / 422 的消息来自它）
    ///   - now: 兜底时刻。仅在"响应说配额耗尽、却没给 `reset`"时用得上；注入以便测试。
    public static func from(
        status: Int,
        headers: HTTPHeaders = HTTPHeaders([:]),
        body: Data = Data(),
        now: Date = Date()
    ) -> GitHubError? {
        if (200..<300).contains(status) { return nil }

        switch status {
        case 401:
            return .unauthorized

        case 403:
            // ⚠️ 403 有两种截然不同的含义，**只能靠响应头区分**（§4.5）：
            //    ① 二级限流 —— 带 `Retry-After`（官方明确）
            //    ② 主桶耗尽 —— `x-ratelimit-remaining == 0`
            //    ③ 权限不足 —— 上面两条都不成立
            // 混同的后果很具体：把"配额用光"报成"你没权限"，用户会去检查权限设置，
            // 而真正该做的是等一会儿（或引导登录）。
            return rateLimit(headers: headers, now: now)
                ?? .forbidden(GitHubError.message(from: body))

        case 404:
            return .notFound

        case 409:
            return .conflict

        case 422:
            return .validation(GitHubError.validationMessages(from: body))

        case 429:
            // 429 依 GitHub 文档属二级限流；若响应同时表明主桶已空，则以主桶为准。
            return rateLimit(headers: headers, now: now)
                ?? .rateLimited(resetAt: now, isSecondary: true)

        default:
            // 5xx 与其余未归类状态码（400 / 415 / 451 …）统一兜底。
            return .serverError(status: status)
        }
    }

    /// 从响应头判定是否配额耗尽；`nil` 表示**不是**配额问题。
    private static func rateLimit(headers: HTTPHeaders, now: Date) -> GitHubError? {
        let retryAfter = retryAfterDate(headers["retry-after"], now: now)
        let remaining = headers.intValue("x-ratelimit-remaining")
        let reset = headers.unixDate("x-ratelimit-reset")

        // 主桶耗尽优先：它给出的 reset 更准（二级限流的 Retry-After 只是建议值）
        if remaining == 0 {
            return .rateLimited(resetAt: reset ?? retryAfter ?? now, isSecondary: false)
        }
        if let retryAfter {
            return .rateLimited(resetAt: retryAfter, isSecondary: true)
        }
        return nil
    }

    /// `Retry-After` 有两种合法形式（RFC 9110 §10.2.3）：**秒数**或 **HTTP-date**。
    /// GitHub 两种都出现过，只认其中一种会漏判。
    private static func retryAfterDate(_ raw: String?, now: Date) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = TimeInterval(raw) {
            return now.addingTimeInterval(seconds)
        }
        return httpDateFormatter().date(from: raw)
    }

    /// RFC 1123 形式（`Wed, 21 Oct 2015 07:28:00 GMT`）。
    ///
    /// `DateFormatter` 不是 `Sendable`，故不共享实例 —— 这条路径极罕见（只在拿不到秒数形式时走），
    /// 每次新建的性能代价可以忽略，换来的是不必给全局可变状态加锁。
    private static func httpDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }

    /// 取 GitHub 错误体的 `message` 字段。
    private static func message(from body: Data) -> String {
        struct Payload: Decodable { let message: String? }
        return (try? JSONDecoder().decode(Payload.self, from: body))?.message ?? ""
    }

    /// 取 422 的 `errors[]`。GitHub 的每项形状不固定（`field` / `resource` / `code` 可有可无），
    /// 逐项拼成可读字符串；一项都取不到时回落 `message`。
    private static func validationMessages(from body: Data) -> [String] {
        struct Payload: Decodable {
            struct Item: Decodable {
                let resource: String?
                let field: String?
                let code: String?
            }
            let message: String?
            let errors: [Item]?
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: body) else { return [] }

        let items = (payload.errors ?? []).compactMap { item -> String? in
            switch (item.field, item.code, item.resource) {
            case let (field?, code?, _):
                return "\(field): \(code)"
            case let (field?, nil, _):
                return field
            case let (nil, code?, resource?):
                return "\(resource): \(code)"
            case let (nil, code?, nil):
                return code
            default:
                return nil
            }
        }

        if !items.isEmpty { return items }
        return payload.message.map { [$0] } ?? []
    }
}
