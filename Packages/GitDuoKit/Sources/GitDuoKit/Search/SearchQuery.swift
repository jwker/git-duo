import Foundation

/// 一次搜索要发出去的**一组**查询（PRD §4.2、TECH_SPEC §9.2）。
///
/// ## 为什么是「一组」而不是「一条」
///
/// 「Issue · PR」这个范围**必须**拆成两条。官方限制（`docs.github.com/rest/search/search`）：
///
/// > For requests made by **GitHub Apps with a user access token**, you can't retrieve a
/// > combination of issues and pull requests in a single query. Requests that don't include
/// > the `is:issue` or `is:pull-request` qualifier will receive an **HTTP 422 Unprocessable
/// > Entity** response. To get results for both issues and pull requests, you must send
/// > **separate queries**.
///
/// 本项目用的正是 GitHub App 用户令牌（`ghu_`）⇒ 不带 `is:` 直接 422，且**只能分两次**问。
/// 代价是这一范围每翻一页消耗 **2 格**搜索配额（30/min 的桶）。
/// 其余三个范围各只有一条 part。
///
/// ## 它只**拼**，不发
///
/// 发请求是 `GitHubAPI` 的事（与 `ExploreQuery` 同分工）。这样"范围自带的限定符拼错了"
/// 能在没有网络的情况下被单测抓住 —— 而这一条错了的代价是**每翻一页白烧两格配额**，
/// 且症状是"这个范围永远没有结果"，看起来像服务端的问题。
public struct SearchQuery: Sendable, Hashable {

    public let scope: SearchScope

    /// 用户输入的**去空白**原文。
    ///
    /// 原样保留大小写与内部结构（引号、限定符、连字符否定）：GitHub 搜索本身不区分大小写，
    /// 而我们做任何"归一化"都有把用户粘进来的整串改坏的风险，
    /// 而改坏的表现是"输入框里明明是这样，结果却不是"。
    public let keyword: String

    public let perPage: Int

    /// 要依次发出的查询。**顺序即结果顺序**（Issue 在前、PR 在后，与原型 `ISSUES.concat(PRS)` 一致）。
    public let parts: [SearchQueryPart]

    /// 这一范围一次要发几条请求 —— 「Issue · PR」是 **2**，其余是 1。
    ///
    /// 缓存与配额提示都读它，而不是各自去数 `parts.count`（那会让"两处各数一遍"变成常态）。
    public var requestCount: Int { parts.count }
}

/// `SearchQuery` 里的一条查询 —— **要发出去的一次请求**。
public struct SearchQueryPart: Sendable, Hashable {

    /// 这条查询属于哪个范围。
    ///
    /// ## 为什么每条 part 都带着它（明明同属一个范围）
    ///
    /// 一条查询的所有 part 确实同属 `SearchQuery.scope`，但取数的**接缝**
    /// （`SearchDataSource.search(_:perPage:cursor:)`）只收到 part ——
    /// 没有它就不知道该打哪个端点，也不知道该占哪个配额桶
    /// （代码搜索那一档约 10 次/分钟，与其余的 30 差三倍）。
    /// 把范围放进 part，接缝就不必再多一个"范围"参数，调用方也就没机会传错。
    public let scope: SearchScope

    /// 完整的 `q=` 值（用户关键词 + 该条自带的限定符）。
    public let qualifiers: String

    public init(scope: SearchScope, qualifiers: String) {
        self.scope = scope
        self.qualifiers = qualifiers
    }
}

/// 「这一下够不够格发请求」的判定结果（TECH_SPEC §9.2）。
///
/// ## 它是防配额浪费的**唯一**关口
///
/// 两条浪费路径都在这里堵住：
/// 1. **关键词为空** ⇒ 服务端 422，而那次失败**照样扣配额**
///    （同 `GitHubSearchRepositoriesEndpoint.search` 的 `guard`）；
/// 2. **代码范围只有限定符**（如 `language:go`）⇒ 官方明写"必须含至少一个检索词"
///    （见 `SearchScope.requiresBareTerm`），同样 422，而那一档只有 10 次/分钟。
///
/// ## 为什么用类型表达，而不是让调用方 `if`
///
/// `SearchQuery` **只能**从 `.ready` 里拿到 ⇒「没准备好也发出去」这件事在编译期就不成立。
/// 若改成一个 `isReady: Bool`，那么"某条新加的调用路径忘了判断"就是一个纯粹的疏漏，
/// 而它的症状是**用户每输入一次就白烧一格搜不到的配额**。
public enum SearchQueryReadiness: Equatable, Sendable {

    /// 可以发。
    case ready(SearchQuery)

    /// 关键词为空（或只有空白）—— 此时页面显示的是**空闲态**（最近搜索 + 热门词），不是错误。
    case emptyKeyword

    /// 代码范围：有输入，但**一个检索词都没有**（全是 `language:` 这类限定符）。
    case needsBareTerm

    /// 可发的查询；`nil` = 还不能发。
    public var query: SearchQuery? {
        if case let .ready(query) = self { return query }
        return nil
    }

    /// 该在结果区说哪一句；`nil` = 不用说话。
    ///
    /// `.emptyKeyword` 也返回 `nil`：那种情况下该显示的是空闲态，
    /// 而"先说一句'先输入关键词'"会让刚进页面的用户以为自己做错了什么。
    public var noticeText: String? {
        switch self {
        case .ready, .emptyKeyword: nil
        case .needsBareTerm: SearchCopy.needsKeyword
        }
    }
}

/// 搜索查询的拼装与门槛判定（TECH_SPEC §9.2）。
public enum SearchQueryBuilder {

    /// 首屏页大小。与其余列表一致（§4.4）。
    ///
    /// 上限 100，超过会被服务端**静默**夹到 100（分页步长因此变了而不报错），所以别传大数。
    public static let pageSize = 30

    /// 「Issue · PR」拆成两条时各自带的限定符。
    ///
    /// ⚠️ 取值来自官方文档原文（见 `SearchQuery` 的类型说明），**两个词一个都不能少**：
    /// 少了它们不是"结果变多"，而是**整条请求 422**。
    public static let issueQualifier = "is:issue"
    public static let pullRequestQualifier = "is:pull-request"

    /// 判定这一下能不能发；能发就把该发的查询拼好。
    ///
    /// - Parameter keyword: 用户输入的**原文**（本方法自己去空白；调用方不必先去一次，
    ///   否则"谁负责 trim"会变成两处都做或两处都不做）。
    public static func readiness(scope: SearchScope, keyword: String) -> SearchQueryReadiness {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return .emptyKeyword }

        if scope.requiresBareTerm, !hasBareTerm(trimmed) { return .needsBareTerm }

        return .ready(
            SearchQuery(
                scope: scope,
                keyword: trimmed,
                perPage: pageSize,
                parts: parts(scope: scope, keyword: trimmed)
            )
        )
    }

    /// 该范围实际要发的查询。
    ///
    /// 「Issue · PR」是**两条**（官方限制，见 `SearchQuery`），其余范围是**一条**。
    /// 顺序固定为 Issue 在前 —— 原型就是 `ISSUES.map(…).concat(PRS.map(…))`。
    ///
    /// ⚠️ 这里**不**为每条 part 标注"Issue / PR"：那件事由**响应**决定
    /// （`SearchConversationDTO.isPullRequest`，判据是 `pull_request` 字段的存在性）。
    /// 按我们发出的查询去贴标签也行，但一旦服务端把一条 PR 混进 `is:issue` 的结果里，
    /// 就会把它画成 Issue —— 而响应里本来就有现成的答案，没有理由去猜。
    private static func parts(scope: SearchScope, keyword: String) -> [SearchQueryPart] {
        guard scope == .issues else {
            return [SearchQueryPart(scope: scope, qualifiers: keyword)]
        }
        return [
            SearchQueryPart(scope: scope, qualifiers: "\(keyword) \(issueQualifier)"),
            SearchQueryPart(scope: scope, qualifiers: "\(keyword) \(pullRequestQualifier)")
        ]
    }

    /// 输入里有没有**至少一个检索词**（非限定符）。
    ///
    /// 判定办法：按空白切词，凡「形如 `name:` 且 `name` 在已知限定符表里」的算限定符，
    /// 其余都算检索词。连字符否定写法（`-language:swift`）也算限定符。
    ///
    /// ## 为什么用**已知表**，而不是"含冒号就是限定符"
    ///
    /// 后者会把 `https://example.com` 里的 `https:` 也当成限定符 ⇒ 一条合法查询被我们
    /// **拦下来不发**，用户看到的是"什么也没发生"，而他并没有做错什么。
    /// 反过来（表里没有的 `foo:bar` 当成检索词）最坏结果是**多发一次请求**，代价小得多。
    /// 两侧不对称，就往代价小的那侧靠。
    public static func hasBareTerm(_ input: String) -> Bool {
        input.split(whereSeparator: \.isWhitespace).contains { token in
            var name = token.lowercased()
            // GitHub 的否定写法：`-language:swift`。
            if name.hasPrefix("-") { name.removeFirst() }
            guard let colon = name.firstIndex(of: ":") else { return true }
            return !knownQualifiers.contains(String(name[name.startIndex..<colon]))
        }
    }

    /// 已知的搜索限定符名（**不含冒号**）。
    ///
    /// 它只服务"有没有检索词"这一件事，**不必穷尽** GitHub 的全部限定符 ——
    /// 正是上面那条不对称：漏一个的后果是"多发一次请求"，多一个假名的后果才是
    /// "把合法查询拦死"。所以宁可漏，不可滥。
    static let knownQualifiers: Set<String> = [
        "language", "repo", "user", "org", "path", "filename", "extension", "in",
        "size", "is", "type", "state", "label", "author", "assignee", "mentions",
        "commenter", "involves", "team", "created", "updated", "closed", "merged",
        "stars", "forks", "topic", "license", "archived", "fork", "mirror", "template",
        "followers", "reactions", "review", "reviewed-by", "review-requested",
        "hash", "committer", "merge", "status", "head", "base", "linked", "no", "draft"
    ]
}
