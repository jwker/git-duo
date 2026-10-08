import Foundation

/// 仓库的 **Issue 读写** —— 列表 / 详情 / 评论 / 新建
/// （TECH_SPEC §4.6.2、§4.14、§9.8）。
///
/// ## 切片 7 起它不再是"只读"的了
///
/// 切片 4 建这个类型时只用得上列表，类说明写的是"本类型只提供读"。切片 7 加进来了
/// 两条写（新建 Issue、发评论）—— 与 `GitHubRepoBranchEndpoint` 同一个理由：
/// **同一屏的读写放在一起**更好核对（Issue 详情页的"读评论 + 发评论"就是同一屏）。
///
/// ## ⚠️ 关闭 / 重新打开 Issue **不在这里**
///
/// 决策 #62：PRD §4.9 与原型都没有这个入口，`PATCH …/issues/{n}` 虽在 §4.6.2 的端点表里，
/// 但那只是端点清单、不等于产品范围 ⇒ 本期不做。**不是遗漏。**
public struct GitHubRepoIssuesEndpoint: Sendable {

    /// 列表页大小（与其余列表一致，§4.4）。
    public static let pageSize = 30

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    /// 取一页 Issue（**按状态，可选按标签筛**）。
    ///
    /// - Parameter state: `open` / `closed` —— 切片 7 的两档（决策 #56）。
    ///   原方法名是 `openIssues`（只取开放，即探索页 §4.14 那一档），当时就写明
    ///   "切片 7 的「我的仓库」四分区确实需要『已关闭』，**那时再加参数**"。
    /// - Parameter labels: 标签名列表。**逗号分隔即多选，服务端按 AND 语义**
    ///   （要同时带上这些标签）。空数组 ⇒ **不带该参数**（不筛）。
    /// - Parameter cursor: 上一页的 `nextCursor`。`nil` 取第一页。
    ///    续页用 `client.page(at:)`（完整 URL）—— 自己拼 `?page=n` 会漏掉
    ///    服务端带的其它参数（§4.4）。
    ///
    /// - Returns: 一页条目。⚠️ **里面混着 PR**，调用方必须按 `isPullRequest` 过滤
    ///   （见 `IssueDTO` 的类型说明）。
    ///
    /// ⚠️ **服务端也会混入 PR，所以分页步长不是"每页 30 个 Issue"** ——
    /// 一页 30 条里可能只有 9 个 Issue。这不是 bug，是 `GET /issues` 的固有行为；
    /// 也因此界面上的计数用**过滤后的已加载条数**（2026-10-06 用户拍板）。
    public func issues(
        owner: String,
        repo: String,
        state: String,
        labels: [String] = [],
        cursor: URL? = nil
    ) async throws -> Page<IssueDTO> {
        if let cursor {
            return try await client.page(at: cursor, as: IssueDTO.self)
        }
        var query = [
            URLQueryItem(name: "state", value: state),
            // 显式写 sort / direction / per_page：不依赖服务端默认值（§4.6.2 的同类口径）。
            // 它们也决定缓存键 —— 隐式默认值会让"服务端改了默认"表现为缓存莫名换了一份。
            URLQueryItem(name: "sort", value: "created"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "per_page", value: String(Self.pageSize))
        ]
        // ⚠️ **只在非空时加 `labels`**：发一个空串会被服务端当成"筛一个名字为空的标签"，
        //    结果是空列表 —— 一个不报错、只是永远没数据的坑。
        if !labels.isEmpty {
            query.append(URLQueryItem(name: "labels", value: labels.joined(separator: ",")))
        }
        return try await client.page(
            "repos/\(owner)/\(repo)/issues",
            query: query,
            as: IssueDTO.self
        )
    }

    // MARK: - 读：详情

    /// 单个 Issue —— `GET /repos/{o}/{r}/issues/{n}`（PRD §4.9、决策 #57）。
    ///
    /// ## 为什么详情是**两次请求**而不是一次聚合
    ///
    /// §9.8 原先并列了"REST 两次（issue + comments）"与"GraphQL 一次聚合"两个方案。
    /// 2026-10-08 拍板取前者（决策 #57）：
    /// - 与「REST 为骨架」（决策 #6）这条主线一致；
    /// - 两次**可分别缓存、分别重试** —— 评论拉失败不该让正文也消失。
    ///   （这正是没选 GraphQL 聚合的实质理由，省下的那一次往返换不来什么。）
    ///
    /// ⚠️ **本方法与 `issueComments` 是有意分开的两个调用**，别在调用方把它们的失败
    /// 合并成一个 —— 那样"评论加载失败"会把整页拖成错误态。
    public func issue(owner: String, repo: String, number: Int) async throws -> IssueDetailDTO {
        try await client.get(
            "repos/\(owner)/\(repo)/issues/\(number)",
            as: IssueDetailDTO.self,
            rateLimitResource: .core
        )
    }

    // MARK: - 读：评论

    /// Issue 的评论 —— `GET /repos/{o}/{r}/issues/{n}/comments`。
    ///
    /// ⚠️ **PR 的会话评论也走这里**（GitHub 把 PR 当作一种 Issue，§9.9 写明了）——
    /// PR 详情的"对话"分区用的是同一个方法，不是 `/pulls/{n}/comments`
    /// （那是**行内评论**，两回事，见 `PullReviewDTO` 的对照表）。
    ///
    /// - Parameter perPage: 一页大小。默认取端点上限 **100**（不是其余列表的 30）：
    ///   讨论是**这一页的内容本身**，只取 30 条会让"点进来只看到一半讨论"
    ///   变成一件屏幕上完全看不出来的事。缺口由 `nextCursor` 兜住。
    public func issueComments(
        owner: String,
        repo: String,
        number: Int,
        perPage: Int = 100,
        cursor: URL? = nil
    ) async throws -> Page<IssueCommentDTO> {
        if let cursor {
            return try await client.page(at: cursor, as: IssueCommentDTO.self)
        }
        return try await client.page(
            "repos/\(owner)/\(repo)/issues/\(number)/comments",
            query: [
                URLQueryItem(name: "per_page", value: String(perPage)),
                URLQueryItem(name: "sort", value: "created"),
                URLQueryItem(name: "direction", value: "asc")
            ],
            as: IssueCommentDTO.self
        )
    }

    // MARK: - 写：新建 Issue

    /// 新建 Issue —— `POST /repos/{o}/{r}/issues`（PRD §4.10）。
    ///
    /// - Parameters:
    ///   - title: **调用方保证非空** —— 领域层 `CreateIssue` 在标题为空时用占位标题
    ///     （PRD §4.10 明写"标题为空时使用占位标题"），那条规则**不在这里**：
    ///     数据层不该有产品文案。
    ///   - body: 可空（只写标题是允许的）。
    ///   - labels: 标签**名**列表（不是 id）。空数组 ⇒ **不带该字段**（见下方说明）。
    ///
    /// ⚠️ **标签按「名字」传**：本片只支持仓库已有标签 + 新建标签（§5.2），
    /// 两者都以名字为唯一键（`LabelDTO` 的说明）。传 `labels: []` 与"不带这个字段"
    /// 在服务端是两件事 —— 前者会清空标签（这次是新建，无标签可清）；
    /// 仍然**只在非空时带**，因为一个恒存在的空数组会诱导下一个人以为"必须带"。
    public func createIssue(
        owner: String,
        repo: String,
        title: String,
        body: String? = nil,
        labels: [String] = []
    ) async throws -> IssueDetailDTO {
        var payload: [String: Any] = ["title": title]
        if let body, !body.isEmpty { payload["body"] = body }
        if !labels.isEmpty { payload["labels"] = labels }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        let response = try await client.send(
            .sending(
                .post,
                to: client.url("repos/\(owner)/\(repo)/issues"),
                body: data,
                // 列表多了一条 ⇒ 不失效的话"建完返回列表看不到它"（下拉刷新绕缓存，看不出问题）。
                invalidating: [Self.issuesPrefix(owner: owner, repo: repo)]
            )
        )
        return try response.decode(IssueDetailDTO.self)
    }

    // MARK: - 写：发评论

    /// 发一条评论 —— `POST /repos/{o}/{r}/issues/{n}/comments`（PRD §4.9 / §4.11）。
    ///
    /// ⚠️ **PR 的评论也用这个方法**（同 `issueComments` 的理由）。
    ///
    /// - Returns: 服务端回的那条评论（**201**）—— 用它的 `id` / `createdAt`
    ///   追加到本地列表，而不是自己造一条"刚刚"。
    ///
    /// ⚠️ **失败时草稿怎么办**是调用方的事：PRD §4.9 的提示条逐字承诺
    /// 「草稿已保留，可重试」⇒ 草稿落 `UserDefaults`（决策 #59），
    /// 那条路在领域层/组合根，**不在这里**（本方法失败就是抛错，不吞）。
    public func createIssueComment(
        owner: String,
        repo: String,
        number: Int,
        body: String
    ) async throws -> IssueCommentDTO {
        let data = try JSONSerialization.data(
            withJSONObject: ["body": body],
            options: [.sortedKeys]
        )
        let response = try await client.send(
            .sending(
                .post,
                to: client.url("repos/\(owner)/\(repo)/issues/\(number)/comments"),
                body: data,
                invalidating: [Self.issuesPrefix(owner: owner, repo: repo)]
            )
        )
        return try response.decode(IssueCommentDTO.self)
    }

    // MARK: - 缓存前缀

    /// Issue 的**整棵子树**：列表 / 详情 / 评论都在 `/issues` 下面。
    ///
    /// 一条前缀就够，是因为缓存失效按**路径前缀**匹配、不看查询串
    /// （同 `GitHubRepoBranchEndpoint` 的粗粒度做法）。代价是发一条评论会把
    /// 该仓库所有 Issue 的列表缓存一起清掉 —— 那是刻意的：
    /// 分清 `/issues` 与 `/issues/42` 需要把"路径段数"纳入匹配语义，
    /// 而"多几个请求"比"发完评论回去看不到它"轻得多。
    private static func issuesPrefix(owner: String, repo: String) -> String {
        "/repos/\(owner)/\(repo)/issues"
    }
}
