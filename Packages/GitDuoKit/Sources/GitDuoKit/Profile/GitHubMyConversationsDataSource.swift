import Foundation
import GitHubAPI

/// 生产实现：`MyConversationsDataSource` 那道接缝（切片 9.2）。
///
/// ## 它只做三件事，每件都有一个"漏了不报错"的后果
///
/// 1. **按 `kind` 选限定符** —— 走 `MyConversationsQuery.qualifiers(for:)`
///    （`author:@me is:pull-request` / `author:@me is:issue`）。选错的表现不是错误，
///    而是"这一页列的是另一类东西"；
/// 2. **带上 `sort=updated&order=desc`** —— ⚠️ 这是本类型**最容易漏**的一步：
///    `sort` 是**独立查询参数**，不加**不会报错**，只会安静地按相关度排
///    （列表有内容、条数也对，只有用户会发现"顺序怪"）。PRD §4.21 把它写成了口径；
/// 3. **四个字段逐个原样带出去** —— `totalCount` / `nextCursor` / `incompleteResults`
///    一个都不能丢，症状分别是：结果标题永远 `0 个结果`、翻不了页、
///    "结果不完整"永不提示（同 `GitHubSearchDataSource.hitPage` 的说明）。
///
/// ## 行模型**复用搜索页的**
///
/// 结果行是同一个 `ConversationHit`、同一个 `SearchRowMapper.conversation`（决策 #73 的
/// 「结果行复用」）⇒ 状态胶囊、状态图标、点击去向在搜索页与这一页**不可能分叉**。
/// 本类型因此不做任何行级翻译。
///
/// ## 配额：搜索桶（30/分钟）
///
/// 由端点声明（`GitHubSearchIssuesEndpoint` 的 `.search`）。⚠️ 与搜索页**共用同一个桶** ——
/// 所以这一页也用「加载更多」按钮而不是"滚到底自动加载"（`MyConversationsCopy.loadMoreAction`
/// 的说明里记着这条理由：滚动手势一次能连发好几发，一旦触发 403，两个页面会一起瘫）。
///
/// ⚠️ 与搜索页**有意不同**的一点：这里**一次只发一条**查询（单条 part），
/// 所以每翻一页消耗 **1 格**，而不是搜索页「Issue · PR」范围的 2 格（决策 #47 的代价）。
public struct GitHubMyConversationsDataSource: MyConversationsDataSource {

    private let endpoint: any ConversationSearchEndpoint

    /// 接缝注入 —— 测试用（脚本化替身，**不碰 HTTP**）。
    ///
    /// 收协议而不是具体端点，正是因为上面那一条 ⚠️（排序漏了不报错）——
    /// 有了它，"这一页确实带了 `sort=updated&order=desc`"以及"限定符按 kind 选对"
    /// 这两件事就能在没有网络的情况下被断言。
    public init(endpoint: any ConversationSearchEndpoint) {
        self.endpoint = endpoint
    }

    /// 组合根用：直接按 `GitHubRESTClient` 装配真实端点。
    public init(client: GitHubRESTClient) {
        self.init(endpoint: GitHubSearchIssuesEndpoint(client: client))
    }

    public func search(
        kind: ConversationKind,
        perPage: Int,
        cursor: URL?
    ) async throws -> MyConversationHitPage {
        let result = try await endpoint.search(
            query: MyConversationsQuery.qualifiers(for: kind),
            perPage: perPage,
            cursor: cursor,
            // ⚠️ 这两个参数就是"最近更新降序"（PRD §4.21）。续页那一路不带它们 ——
            //    服务端给的 `nextCursor` 是完整 URL，查询串已经在里面了
            //    （`GitHubSearchIssuesEndpoint.search` 的说明记着这条依赖）。
            sort: MyConversationsQuery.sortParameter,
            order: MyConversationsQuery.sortOrder
        )

        return MyConversationHitPage(
            // 与搜索页共用同一个行映射 —— 两边各写一份必然分叉。
            hits: try result.items.map { try SearchRowMapper.conversation($0) },
            totalCount: result.totalCount,
            nextCursor: result.nextCursor,
            incompleteResults: result.incompleteResults
        )
    }
}
