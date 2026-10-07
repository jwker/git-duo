import Foundation
import Testing

@testable import GitDuoKit

/// 查询拼装与「够不够格发」的门槛（TECH_SPEC §9.2）。
///
/// ## 这两件事为什么必须被测住
///
/// 门槛漏了 ⇒ **每一次输入都白烧一格搜不到的配额**（代码那档只有 10 次/分钟），
/// 而症状是"这个范围永远没结果"，看起来像服务端的问题；
/// 限定符拼错 ⇒ 不是"结果变多"，而是整条请求 **422**（官方原文见 `SearchQuery` 的说明）。
@Suite("SearchQuery · 门槛 / 拆分 / 限定符")
struct SearchQueryTests {

    private func readiness(
        _ scope: SearchScope,
        _ keyword: String
    ) -> SearchQueryReadiness {
        SearchQueryBuilder.readiness(scope: scope, keyword: keyword)
    }

    private func query(_ scope: SearchScope, _ keyword: String) throws -> SearchQuery {
        try #require(readiness(scope, keyword).query)
    }

    // MARK: - 门槛

    @Test("空输入 ⇒ `.emptyKeyword`（此时该显示空闲态，不是错误）")
    func emptyKeywordIsNotReady() {
        #expect(readiness(.repositories, "") == .emptyKeyword)
        #expect(readiness(.repositories, "   ") == .emptyKeyword)
        #expect(readiness(.repositories, "\n\t ") == .emptyKeyword)
        // 代码范围也一样：空输入先撞的就是这一条，而不是"缺检索词"。
        #expect(readiness(.code, "  ") == .emptyKeyword)
    }

    @Test("⚠️ 代码范围只填限定符 ⇒ `.needsBareTerm`（官方：`language:go` 不合法，`amazing language:go` 合法）")
    func codeNeedsBareTerm() {
        #expect(readiness(.code, "language:go") == .needsBareTerm)
        #expect(readiness(.code, "in:file language:js repo:jquery/jquery") == .needsBareTerm)
        #expect(readiness(.code, "-language:swift") == .needsBareTerm)
    }

    @Test("代码范围带了检索词 ⇒ 可发")
    func codeWithBareTermIsReady() throws {
        let built = try query(.code, "amazing language:go")
        #expect(built.keyword == "amazing language:go")
        #expect(built.parts.count == 1)
    }

    @Test("其余三个范围**不**受「必须有检索词」限制 —— 只填限定符在它们那里是合法查询")
    func otherScopesAllowQualifierOnly() throws {
        for scope in [SearchScope.repositories, .users, .issues] {
            let built = try query(scope, "language:swift")
            #expect(built.keyword == "language:swift")
        }
    }

    @Test("`.needsBareTerm` 该说哪一句：复用原型已有的 `先输入关键词`（用户 2026-10-07 拍板，零新增文案）")
    func needsBareTermNotice() {
        #expect(readiness(.code, "language:go").noticeText == "先输入关键词")
        #expect(readiness(.code, "language:go").noticeText == SearchCopy.needsKeyword)
        // `.ready` 不用说话；`.emptyKeyword` 也不用 —— 那时显示的是空闲态，
        // 先说一句「先输入关键词」会让刚进页面的用户以为自己做错了什么。
        #expect(readiness(.code, "amazing").noticeText == nil)
        #expect(readiness(.code, "").noticeText == nil)
    }

    // MARK: - `hasBareTerm` 的判据

    @Test("含冒号但**名字不在已知表里** ⇒ 算检索词（往代价小的那侧靠：最坏是多发一次请求）")
    func unknownQualifierCountsAsTerm() {
        // `https://github.com/...` 里的 `https:` 若被误判成限定符，
        // 一条合法查询会被我们**拦下来不发** —— 用户看到的是"什么也没发生"。
        #expect(SearchQueryBuilder.hasBareTerm("https://github.com/foo/bar"))
        #expect(SearchQueryBuilder.hasBareTerm("foo:bar"))
        #expect(SearchQueryBuilder.hasBareTerm("10:30"))
    }

    @Test("已知限定符（含否定写法与引号短语）逐个判")
    func knownQualifierMatrix() {
        #expect(!SearchQueryBuilder.hasBareTerm("language:swift"))
        #expect(!SearchQueryBuilder.hasBareTerm("-language:swift"))
        #expect(!SearchQueryBuilder.hasBareTerm("is:pr"))
        #expect(SearchQueryBuilder.hasBareTerm("amazing language:go"))
        // 引号短语按空白切开后每一片都没有限定符形状 ⇒ 算检索词。
        #expect(SearchQueryBuilder.hasBareTerm("\"hello world\""))
        // 大小写不敏感：`Language:Swift` 也是限定符。
        #expect(!SearchQueryBuilder.hasBareTerm("Language:Swift"))
    }

    // MARK: - 拆分

    @Test("⚠️「Issue · PR」拆成**两条**查询，且限定符逐字是官方的 `is:issue` / `is:pull-request`")
    func issuesScopeSplitsInTwo() throws {
        let built = try query(.issues, "登录")

        #expect(built.requestCount == 2)
        #expect(built.parts.map(\.conversationKind) == [.issue, .pullRequest])
        #expect(built.parts.map(\.qualifiers) == ["登录 is:issue", "登录 is:pull-request"])
        #expect(built.parts[0].qualifiers.contains(SearchQueryBuilder.issueQualifier))
        #expect(built.parts[1].qualifiers.contains(SearchQueryBuilder.pullRequestQualifier))
    }

    @Test("其余三个范围各**只有一条**，且 `conversationKind` 为 `nil`（它们不分类型）")
    func otherScopesHaveOnePart() throws {
        for scope in [SearchScope.repositories, .users, .code] {
            let built = try query(scope, "swiftui")
            #expect(built.requestCount == 1)
            #expect(built.parts.map(\.conversationKind) == [ConversationKind?.none])
            #expect(built.parts[0].qualifiers == "swiftui")
        }
    }

    @Test("关键词两端去空白；**内部原样保留**（引号 / 限定符 / 连字符不许被我们改坏）")
    func keywordIsTrimmedButNotReshaped() throws {
        #expect(try query(.repositories, "  swiftui  ").keyword == "swiftui")
        #expect(try query(.repositories, " \"exact phrase\" language:Swift ").keyword == "\"exact phrase\" language:Swift")
        #expect(try query(.issues, " 登录 ").parts[0].qualifiers == "登录 is:issue")
    }

    @Test("首屏页大小是 30（与其余列表一致）")
    func pageSizeIsThirty() throws {
        #expect(SearchQueryBuilder.pageSize == 30)
        #expect(try query(.repositories, "swiftui").perPage == 30)
    }
}
