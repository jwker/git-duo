import Foundation
import Testing

@testable import GitHubAPI

@Suite("HTTP 头包装")
struct HTTPHeadersTests {

    @Test("大小写不敏感：ETag / Etag / etag 取到同一个值")
    func caseInsensitiveLookup() {
        let headers = HTTPHeaders(["ETag": "W/\"abc\""])

        #expect(headers["etag"] == "W/\"abc\"")
        #expect(headers["ETag"] == "W/\"abc\"")
        #expect(headers["eTaG"] == "W/\"abc\"")
    }

    @Test("大小写不敏感：GitHub 实际混用过的限流头写法都能查到")
    func mixedCaseRateLimitHeaders() {
        // GitHub 在不同链路上返回过这两种拼写，只认一种就会间歇性漏判
        let upper = HTTPHeaders(["X-RateLimit-Remaining": "0"])
        let lower = HTTPHeaders(["x-ratelimit-remaining": "0"])

        #expect(upper.intValue("x-ratelimit-remaining") == 0)
        #expect(lower.intValue("X-RateLimit-Remaining") == 0)
    }

    @Test("大小写不同的同名字段归一化成一项（值取哪个不作承诺）")
    func duplicateKeysCollapse() {
        let headers = HTTPHeaders(["etag": "first", "ETag": "second"])

        // ⚠️ 只断言"归一化了" —— 入参是无序字典，`for (name, value) in raw` 的顺序
        //    取决于哈希种子（每次进程启动都不同）。若断言具体值，这个用例会**间歇性失败**，
        //    而且症状看起来像实现有 bug。（第一版就是这么写的，跑第二遍才暴露。）
        #expect(headers.count == 1)
        let value = headers["etag"]
        #expect(value == "first" || value == "second")
    }

    @Test("缺失的头返回 nil（而不是空串）")
    func missingHeaderIsNil() {
        let headers = HTTPHeaders(["ETag": "abc"])

        #expect(headers["Link"] == nil)
        #expect(headers.intValue("x-ratelimit-limit") == nil)
        #expect(headers.unixDate("x-ratelimit-reset") == nil)
    }

    @Test("整数头不可解析时返回 nil（不静默当 0）")
    func nonNumericIntHeader() {
        let headers = HTTPHeaders(["x-ratelimit-remaining": "not-a-number"])

        #expect(headers.intValue("x-ratelimit-remaining") == nil)
    }

    @Test("Unix 秒时间戳头换算成 Date")
    func unixDateHeader() {
        let headers = HTTPHeaders(["x-ratelimit-reset": "1700000000"])

        #expect(headers.unixDate("x-ratelimit-reset") == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("从 HTTPURLResponse 构造：字段完整带过来")
    func fromHTTPURLResponse() {
        let url = URL(string: "https://api.github.com/user")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["ETag": "W/\"xyz\"", "X-RateLimit-Remaining": "4999"]
        )!

        let headers = HTTPHeaders(response: response)

        #expect(headers["etag"] == "W/\"xyz\"")
        #expect(headers.intValue("x-ratelimit-remaining") == 4999)
    }

    @Test("空头集合：isEmpty 为真、任何取值都是 nil")
    func emptyHeaders() {
        let headers = HTTPHeaders([:])

        #expect(headers.isEmpty)
        #expect(headers["etag"] == nil)
    }
}
