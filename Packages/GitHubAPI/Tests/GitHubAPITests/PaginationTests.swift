import Foundation
import Testing

@testable import GitHubAPI

@Suite("分页（§4.4）")
struct PaginationTests {

    private let issuesNext = "https://api.github.com/repositories/1300192/issues?page=2"
    private let issuesLast = "https://api.github.com/repositories/1300192/issues?page=4"

    // MARK: - Link 头

    @Test("标准两段：next 与 last 各自解析正确")
    func standardTwoRelations() {
        let raw = #"<https://api.github.com/repositories/1300192/issues?page=2>; rel="next", <https://api.github.com/repositories/1300192/issues?page=4>; rel="last""#

        let link = LinkHeader(raw)

        #expect(link.next?.absoluteString == issuesNext)
        #expect(link.last?.absoluteString == issuesLast)
        #expect(link.prev == nil)
        #expect(link.first == nil)
    }

    @Test("⚠️ URL 内部含逗号也要切对（用 split(\",\") 会静默少一页）")
    func commaInsideURL() {
        let raw = #"<https://api.github.com/search/issues?q=swift,ios&page=2>; rel="next", <https://api.github.com/search/issues?q=swift,ios&page=9>; rel="last""#

        let link = LinkHeader(raw)

        #expect(link.next?.absoluteString == "https://api.github.com/search/issues?q=swift,ios&page=2")
        #expect(link.last?.absoluteString == "https://api.github.com/search/issues?q=swift,ios&page=9")
    }

    @Test("只有 next（最后一页时不返回 next 的对照）")
    func onlyNext() {
        let link = LinkHeader(#"<https://api.github.com/user/repos?page=3>; rel="next""#)

        #expect(link.next?.absoluteString == "https://api.github.com/user/repos?page=3")
        #expect(link.isEmpty == false)
    }

    @Test("四个 rel 齐全时逐个取到")
    func allRelations() {
        let raw = #"<https://a.test/1>; rel="prev", <https://a.test/3>; rel="next", <https://a.test/1>; rel="first", <https://a.test/9>; rel="last""#

        let link = LinkHeader(raw)

        #expect(link.prev?.absoluteString == "https://a.test/1")
        #expect(link.next?.absoluteString == "https://a.test/3")
        #expect(link.first?.absoluteString == "https://a.test/1")
        #expect(link.last?.absoluteString == "https://a.test/9")
    }

    @Test("rel 无引号也认（宽松解析）")
    func unquotedRelation() {
        let link = LinkHeader("<https://a.test/2>; rel=next")

        #expect(link.next?.absoluteString == "https://a.test/2")
    }

    @Test("rel 大小写不敏感，值也按小写归一")
    func caseInsensitiveRelation() {
        let link = LinkHeader(#"<https://a.test/2>; REL="NEXT""#)

        #expect(link.next?.absoluteString == "https://a.test/2")
    }

    @Test("未知 rel 落 other，不丢也不报错")
    func unknownRelation() {
        let link = LinkHeader(#"<https://a.test/s>; rel="service-desc""#)

        #expect(link[.other("service-desc")]?.absoluteString == "https://a.test/s")
        #expect(link.next == nil)
    }

    @Test("同一 rel 重复出现 ⇒ 保留第一个")
    func duplicateRelationKeepsFirst() {
        let link = LinkHeader(#"<https://a.test/2>; rel="next", <https://a.test/3>; rel="next""#)

        #expect(link.next?.absoluteString == "https://a.test/2")
    }

    @Test("畸形头一律不崩：空串 / 无尖括号 / 只有半个尖括号 / URL 非法")
    func malformedHeadersDoNotCrash() {
        #expect(LinkHeader("").isEmpty)
        #expect(LinkHeader("garbage").isEmpty)
        #expect(LinkHeader("<https://a.test/1").isEmpty)
        #expect(LinkHeader(#">; rel="next""#).isEmpty)
        // 缺 rel 的段被跳过，但同一头里的合法段仍要保住
        let mixed = LinkHeader(#"<https://a.test/1>, <https://a.test/2>; rel="next""#)
        #expect(mixed.next?.absoluteString == "https://a.test/2")
    }

    @Test("相对链接（URL 合法即可，不强求绝对）")
    func relativeURL() {
        let link = LinkHeader(#"</repos?page=2>; rel="next""#)

        #expect(link.next?.absoluteString == "/repos?page=2")
    }

    // MARK: - Page

    @Test("由响应头推出 nextCursor")
    func pageDerivesNextCursorFromHeaders() {
        let headers = HTTPHeaders([
            "Link": #"<https://api.github.com/user/repos?page=2>; rel="next""#,
        ])

        let page = Page<Int>(items: [1, 2, 3], headers: headers)

        #expect(page.items == [1, 2, 3])
        #expect(page.nextCursor?.absoluteString == "https://api.github.com/user/repos?page=2")
        #expect(page.hasMore)
    }

    @Test("没有 Link 头 ⇒ 到底了（hasMore false）")
    func pageWithoutLinkIsLast() {
        let page = Page<Int>(items: [1], headers: HTTPHeaders([:]))

        #expect(page.nextCursor == nil)
        #expect(!page.hasMore)
    }

    @Test("Link 头里只有 prev（第一页之后的回退）⇒ 不算有下一页")
    func pageWithOnlyPrevIsLast() {
        let headers = HTTPHeaders(["Link": #"<https://api.github.com/user/repos?page=1>; rel="prev""#])

        let page = Page<Int>(items: [1], headers: headers)

        #expect(page.nextCursor == nil)
        #expect(!page.hasMore)
    }

    @Test("空页：items 为空但 nextCursor 仍在（列表可能返回空的一页）")
    func emptyPageStillCarriesCursor() {
        let headers = HTTPHeaders(["Link": #"<https://a.test/2>; rel="next""#])

        let page = Page<Int>(items: [], headers: headers)

        #expect(page.isEmpty)
        #expect(page.hasMore)
    }

    @Test("配额快照由头派生（没有配额头则为 nil，不是「清零的快照」）")
    func pageExposesRateLimitSnapshot() {
        let withLimit = HTTPHeaders([
            "x-ratelimit-limit": "5000",
            "x-ratelimit-remaining": "4999",
            "x-ratelimit-reset": "1700003600",
            "x-ratelimit-resource": "core",
        ])
        let page = Page<Int>(items: [1], headers: withLimit)

        #expect(page.rateLimit?.remaining == 4999)
        #expect(page.rateLimit?.resource == .core)

        #expect(Page<Int>(items: [1], headers: HTTPHeaders([:])).rateLimit == nil)
    }

    @Test("map 保留分页信息，只换元素类型")
    func mapPreservesPagination() {
        let headers = HTTPHeaders(["Link": #"<https://a.test/2>; rel="next""#])
        let page = Page<Int>(items: [1, 2], headers: headers)

        let mapped = page.map { "n\($0)" }

        #expect(mapped.items == ["n1", "n2"])
        #expect(mapped.nextCursor?.absoluteString == "https://a.test/2")
        #expect(mapped.hasMore)
    }

    @Test("nextCursor(from:) 可独立使用，不必组装 Page")
    func nextCursorHelper() {
        let headers = HTTPHeaders(["Link": #"<https://a.test/7>; rel="next""#])

        #expect(Page<Int>.nextCursor(from: headers)?.absoluteString == "https://a.test/7")
        #expect(Page<Int>.nextCursor(from: HTTPHeaders([:])) == nil)
    }
}
