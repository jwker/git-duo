import Foundation
import Testing

@testable import GitHubAPI

@Suite("错误模型（§4.3）")
struct GitHubErrorTests {

    /// 固定"现在"，让所有与 `Retry-After` 相关的断言是确定性的。
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func body(_ raw: String) -> Data { Data(raw.utf8) }

    // MARK: - 成功路径

    @Test("2xx 一律返回 nil（调用方继续解码）")
    func successIsNil() {
        for status in [200, 201, 204, 299] {
            #expect(GitHubError.from(status: status, now: now) == nil)
        }
    }

    // MARK: - 逐状态码

    @Test("401 → unauthorized（触发刷新重放的信号）")
    func unauthorized() {
        #expect(GitHubError.from(status: 401, now: now) == .unauthorized)
    }

    @Test("404 → notFound（⚠️ 不得据此断言「不存在」——GitHub 与无权访问混同）")
    func notFound() {
        #expect(GitHubError.from(status: 404, now: now) == .notFound)
    }

    @Test("409 → conflict（提交时 SHA 已过期）")
    func conflict() {
        #expect(GitHubError.from(status: 409, now: now) == .conflict)
    }

    @Test("500 / 502 / 503 → serverError（重试策略的触发条件）")
    func serverErrors() {
        for status in [500, 502, 503, 504] {
            #expect(GitHubError.from(status: status, now: now) == .serverError(status: status))
        }
    }

    @Test("未归类的状态码也落 serverError 兜底（400 / 415 / 451）")
    func unclassifiedStatusFallsBack() {
        // 兜底是**有意**的：宁可让调用方拿到一个带 status 的通用错误，
        // 也不要让它收到一个语义错误的"更具体"的 case。
        for status in [400, 415, 451] {
            #expect(GitHubError.from(status: status, now: now) == .serverError(status: status))
        }
    }

    // MARK: - 403 的三种含义（靠响应头区分）

    @Test("403 无限流头 → forbidden，消息取自 body")
    func forbiddenWithMessage() {
        let error = GitHubError.from(
            status: 403,
            body: body(#"{"message":"Resource not accessible by integration"}"#),
            now: now
        )

        #expect(error == .forbidden("Resource not accessible by integration"))
    }

    @Test("403 无 body → forbidden(空串)，不崩")
    func forbiddenWithoutBody() {
        #expect(GitHubError.from(status: 403, now: now) == .forbidden(""))
    }

    @Test("403 + Retry-After（秒数）→ 二级限流")
    func secondaryRateLimitBySeconds() {
        let headers = HTTPHeaders(["Retry-After": "30"])

        let error = GitHubError.from(status: 403, headers: headers, now: now)

        guard case let .rateLimited(resetAt, isSecondary) = error else {
            Issue.record("期望 rateLimited，实际 \(String(describing: error))")
            return
        }
        #expect(isSecondary)
        #expect(resetAt == now.addingTimeInterval(30))
    }

    @Test("403 + Retry-After（HTTP-date）→ 二级限流（只认秒数形式会漏判）")
    func secondaryRateLimitByHTTPDate() {
        let headers = HTTPHeaders(["Retry-After": "Wed, 15 Nov 2023 06:14:00 GMT"])

        let error = GitHubError.from(status: 403, headers: headers, now: now)

        guard case let .rateLimited(resetAt, isSecondary) = error else {
            Issue.record("期望 rateLimited，实际 \(String(describing: error))")
            return
        }
        #expect(isSecondary)
        #expect(resetAt == Date(timeIntervalSince1970: 1_700_028_840))
    }

    @Test("403 + remaining=0 → 主桶耗尽（不是二级限流，两者处置不同）")
    func primaryRateLimitExhausted() {
        let reset = Date(timeIntervalSince1970: 1_700_003_600)
        let headers = HTTPHeaders([
            "x-ratelimit-remaining": "0",
            "x-ratelimit-reset": "1700003600",
        ])

        let error = GitHubError.from(status: 403, headers: headers, now: now)

        guard case let .rateLimited(resetAt, isSecondary) = error else {
            Issue.record("期望 rateLimited，实际 \(String(describing: error))")
            return
        }
        #expect(!isSecondary)
        #expect(resetAt == reset)
    }

    @Test("403 + remaining=0 且同时有 Retry-After → 仍按主桶算（reset 比建议值准）")
    func primaryWinsOverRetryAfter() {
        let headers = HTTPHeaders([
            "x-ratelimit-remaining": "0",
            "x-ratelimit-reset": "1700003600",
            "Retry-After": "30",
        ])

        let error = GitHubError.from(status: 403, headers: headers, now: now)

        guard case let .rateLimited(resetAt, isSecondary) = error else {
            Issue.record("期望 rateLimited，实际 \(String(describing: error))")
            return
        }
        #expect(!isSecondary)
        #expect(resetAt == Date(timeIntervalSince1970: 1_700_003_600))
    }

    @Test("403 + remaining=0 但无 reset → 回落 now（而不是崩或给 1970）")
    func primaryWithoutResetFallsBack() {
        let headers = HTTPHeaders(["x-ratelimit-remaining": "0"])

        let error = GitHubError.from(status: 403, headers: headers, now: now)

        #expect(error == .rateLimited(resetAt: now, isSecondary: false))
    }

    @Test("403 + remaining>0 → 仍然是 forbidden（额度还有，就不是配额问题）")
    func nonZeroRemainingIsForbidden() {
        let headers = HTTPHeaders([
            "x-ratelimit-remaining": "4999",
            "x-ratelimit-limit": "5000",
        ])

        let error = GitHubError.from(status: 403, headers: headers, now: now)

        #expect(error == .forbidden(""))
    }

    @Test("429 → 二级限流")
    func tooManyRequests() {
        let error = GitHubError.from(status: 429, headers: HTTPHeaders(["Retry-After": "60"]), now: now)

        #expect(error == .rateLimited(resetAt: now.addingTimeInterval(60), isSecondary: true))
    }

    // MARK: - 422 校验失败

    @Test("422 → validation，逐条拼成 field: code")
    func validationWithFields() {
        let payload = #"""
        {"message":"Validation Failed","errors":[
            {"resource":"Issue","field":"title","code":"missing_field"},
            {"resource":"Release","field":"tag_name","code":"already_exists"}
        ]}
        """#

        let error = GitHubError.from(status: 422, body: body(payload), now: now)

        #expect(error == .validation(["title: missing_field", "tag_name: already_exists"]))
    }

    @Test("422 只有 code 与 resource → 拼成 resource: code")
    func validationWithResourceOnly() {
        let payload = #"{"message":"Validation Failed","errors":[{"resource":"PullRequest","code":"custom"}]}"#

        let error = GitHubError.from(status: 422, body: body(payload), now: now)

        #expect(error == .validation(["PullRequest: custom"]))
    }

    @Test("422 无 errors 数组 → 回落 message")
    func validationFallsBackToMessage() {
        let payload = #"{"message":"Validation Failed"}"#

        let error = GitHubError.from(status: 422, body: body(payload), now: now)

        #expect(error == .validation(["Validation Failed"]))
    }

    @Test("422 body 不是 JSON → validation([])，不崩")
    func validationWithGarbageBody() {
        let error = GitHubError.from(status: 422, body: body("<html>nope</html>"), now: now)

        #expect(error == .validation([]))
    }

    // MARK: - Equatable 语义

    @Test("Equatable：decoding 只比较 case，不比底层错误（底层 Error 不可比）")
    func decodingEquatableIgnoresUnderlying() {
        struct Boom: Error {}
        let a = GitHubError.decoding(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x")))
        let b = GitHubError.decoding(Boom())

        #expect(a == b)
    }

    @Test("Equatable：transport 比较 URLError.code")
    func transportComparesCode() {
        #expect(GitHubError.transport(URLError(.timedOut)) == .transport(URLError(.timedOut)))
        #expect(GitHubError.transport(URLError(.timedOut)) != .transport(URLError(.notConnectedToInternet)))
    }

    @Test("Equatable：不同 case 恒不相等")
    func differentCasesNotEqual() {
        #expect(GitHubError.unauthorized != .notFound)
        #expect(GitHubError.forbidden("a") != .forbidden("b"))
        #expect(GitHubError.serverError(status: 500) != .serverError(status: 502))
        #expect(GitHubError.rateLimited(resetAt: now, isSecondary: true)
                != .rateLimited(resetAt: now, isSecondary: false))
    }

    @Test("Equatable：graphQLErrors 的消息与部分数据**都**参与比较")
    func graphQLErrorsComparesMessagesAndPartialData() {
        let data = Data(#"{"viewer":{"login":"octocat"}}"#.utf8)

        #expect(GitHubError.graphQLErrors(messages: ["a"], partialData: data)
                == .graphQLErrors(messages: ["a"], partialData: data))
        #expect(GitHubError.graphQLErrors(messages: ["a"], partialData: data)
                != .graphQLErrors(messages: ["b"], partialData: data))
        // ⚠️ "完全失败"与"部分成功"是**两种**结局，绝不能相等 ——
        //    否则测试里"有没有拿到部分数据"这条断言会静默失效
        #expect(GitHubError.graphQLErrors(messages: ["a"], partialData: data)
                != .graphQLErrors(messages: ["a"], partialData: nil))
    }
}
