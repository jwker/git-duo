import Foundation

/// 分支管理 —— 列表 / 单分支 / 比较 / 建 / 删 / 合并
/// （TECH_SPEC §9.7.1、PRD §4.8 与 §5.7 切换分支弹层、决策 #52 / #53）。
///
/// ## 这个类型里同时有读与写，是有意的
///
/// 切片 4 的 `GitHubStarEndpoint` 单独成类型，因为它是那条链路上**唯一**的写操作。
/// 这里不同：分支的每一次写都紧挨着一次相关的读（删前要 `compare` 校验未合并、
/// 建分支要取当前 HEAD 的 `sha`），把它们分到两个文件里会让
/// "删分支前到底该校验什么"分散在两处。**同一屏的读写放在一起**更好核对。
///
/// ## ⚠️ 写操作**一律不自动重试**
///
/// `HTTPMethod.isSafelyRetryable` 只认 GET（见它的说明：带过期 `sha` 的重复 PUT
/// 会回 409，自动重试会让用户看到"提交失败"而其实第一次已经成功）。
/// `POST /git/refs` 与 `POST /merges` **都不幂等** ——
/// 建分支重放会得到"引用已存在"的 422；合并重放会真的产生第二个合并提交。
/// 所以本节所有写方法都走 `.sending(...)`，不碰重试路径。
public struct GitHubRepoBranchEndpoint: Sendable {

    /// 分支列表页大小 —— 取**端点上限 100**。
    ///
    /// 理由与 `contributors` 相同（决策 #40 的口径）：PRD §4.8 要显示分支**总数**，
    /// 而 `GET /branches` **不返回总数**。一页 100 条覆盖绝大多数仓库 ⇒
    /// 没有下一页时 `items.count` **就是**精确总数；出现下一页才退化成"100 条以上"。
    public static let pageSize = 100

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    // MARK: - 读：列表

    /// 分支列表 —— `GET /repos/{o}/{r}/branches?per_page=100`。
    ///
    /// ⚠️ 每一项**带 `protected`**（2026-10-07 实测）—— 删除入口的判据要用它（决策 #53）。
    ///
    /// - Returns: `Page`，`hasMore` 用来判断 `items.count` 是不是精确总数（见 `pageSize`）。
    ///
    /// ⚠️ **只请求第一页，不做"加载更多"**：§9.7.1 定的是"一页取回"，
    /// 而且这一页还兼着"记忆分支是否仍存在"的校验（§9.4.1 明写"校验不额外消耗请求"）。
    /// 分支超过 100 条的仓库在这个页面上只能说"100 条以上"。
    public func branches(owner: String, repo: String) async throws -> Page<BranchDTO> {
        try await client.page(
            "repos/\(owner)/\(repo)/branches",
            query: [URLQueryItem(name: "per_page", value: String(Self.pageSize))],
            as: BranchDTO.self,
            rateLimitResource: .core
        )
    }

    // MARK: - 读：单分支

    /// 单个分支 —— `GET /repos/{o}/{r}/branches/{branch}`。
    ///
    /// ## 只在"列表里没有它"时才该调用
    ///
    /// §9.7.1 给的取法：新建分支要 `sha`，**优先用分支列表里那一项的 `commit.sha`**，
    /// 取不到才补这一次请求。列表已加载的情况下再打一次就是白白多一个主桶请求。
    /// 真正用得上它的场景是：用户刚输入的新分支名（不在已加载的那一页里）
    /// 或列表因分页没覆盖到它。
    ///
    /// ⚠️ 返回同一个 `BranchDTO`（不是另一个类型）：单分支响应比列表项多出
    /// `_links` / `protection` / `protection_url`，那些本切片都不用（判据只是一个布尔值）。
    public func branch(owner: String, repo: String, name: String) async throws -> BranchDTO {
        try await client.get(
            "repos/\(owner)/\(repo)/branches/\(name)",
            as: BranchDTO.self,
            rateLimitResource: .core
        )
    }

    // MARK: - 读：比较（删除前的未合并校验）

    /// 比较两条分支 —— `GET /repos/{o}/{r}/compare/{base}...{head}`。
    ///
    /// 删除分支前的调用形状是 `compare/{branch}...{defaultBranch}`，即"**这条分支**
    /// 相对默认分支多出了什么"，`aheadBy` 就是那些多出来的提交数（决策 #53）。
    ///
    /// ⚠️ **只解四个标量**（见 `CompareDTO`）：`commits` / `files` 两个数组
    /// 会被服务端**截断**，数它们的长度得到的数本身就是错的。
    ///
    /// ⚠️ `...` 三个点**不能**被百分号编码 —— 它是这个路由的字面语法。
    /// `appendingPathComponent` 不编码 `.`（它是 URL 的 unreserved 字符），
    /// 所以直接拼即可；分支名里的 `/` 也照常当路径分隔符（服务端就是这么设计的）。
    /// 有一条测试专门钉住这一点：`/compare/main...feature/x` 原样发出。
    public func compare(
        owner: String,
        repo: String,
        base: String,
        head: String
    ) async throws -> CompareDTO {
        try await client.get(
            "repos/\(owner)/\(repo)/compare/\(base)...\(head)",
            as: CompareDTO.self,
            rateLimitResource: .core
        )
    }

    // MARK: - 写：建分支

    /// 建分支 —— `POST /repos/{o}/{r}/git/refs`。
    ///
    /// - Parameters:
    ///   - name: **分支名，不含 `refs/heads/`**。本方法负责加前缀。
    ///     ⚠️ 服务端对不合法的名字回 **422**，而那条 422 的文案不是表单校验
    ///     （用户会读成"服务器坏了"）⇒ 名字**必须先过领域层的 `BranchName.validate`**
    ///     （§9.7.1 的八条规则，纯函数、有单测）。本方法不做校验也不代替它。
    ///   - sha: 新分支指向的提交。取法见 `branch(owner:repo:name:)` 的说明。
    ///
    /// - Returns: 服务端回的引用对象；`shortName` 能取回 `name`。
    ///
    /// ⚠️ **请求体的形状与响应不同**（`GitReferenceDTO` 的说明里写了）：
    /// 请求是 `{"ref": "refs/heads/x", "sha": "…"}`，响应把 sha 包在 `object` 里。
    /// 这里用 `JSONSerialization` 手写 —— 用 `Encodable` 会诱使人为请求与响应
    /// 共用一个类型，而那正是这个不对称最容易出错的地方。
    @discardableResult
    public func createBranch(
        owner: String,
        repo: String,
        name: String,
        sha: String
    ) async throws -> GitReferenceDTO {
        let body = try JSONSerialization.data(
            withJSONObject: ["ref": "refs/heads/\(name)", "sha": sha],
            // 键的顺序无所谓（JSON 对象无序），这是给"万一有人拿它做别的事"留的稳定性
            options: [.sortedKeys]
        )

        let response = try await client.send(
            .sending(
                .post,
                to: client.url("repos/\(owner)/\(repo)/git/refs"),
                body: body,
                // 分支列表变了 —— 不失效的话，切回分支页看不到刚建的那条
                //（而下拉刷新会走 `forcesReload` 绕过缓存，看不出问题，所以这个 bug 只在
                //  "建完分支直接返回列表"这条路上显形）。
                invalidating: [Self.branchesPrefix(owner: owner, repo: repo)]
            )
        )
        return try response.decode(GitReferenceDTO.self)
    }

    // MARK: - 写：删分支

    /// 删分支 —— `DELETE /repos/{o}/{r}/git/refs/heads/{branch}`。
    ///
    /// ## ⚠️ 调用方必须先做完两件事，本方法一件都不做
    ///
    /// 1. **判能不能删** —— 默认分支与受保护分支都不可删（决策 #53，
    ///    领域层 `BranchSummary.canDelete(defaultBranch:)` 是唯一判据）。
    ///    ⚠️ 服务端**不替你拦默认分支**：`DELETE …/heads/main` 是一次真实的、
    ///    会成功的删除请求（GitHub 网页端不给入口纯属它的 UI 决定）。
    ///    受保护分支则回 **422**。
    /// 2. **判有没有未合并提交** —— 先 `compare` 看 `aheadBy > 0`，有就阻止并提示。
    ///
    /// 两者都在数据层之外，因为它们是**产品口径**（要弹什么文案、要不要二次确认）。
    /// 本方法只负责把那一次 DELETE 发对。
    ///
    /// ## ⚠️ 删除当前分支后，缓存必须一起失效
    ///
    /// `invalidating` 里的三条对应 §9.7.1 那条要求："若删除的正是该仓库当前分支，
    /// 删除成功后按 §9.4.1 回落 `defaultBranch`，并**失效该仓库的 contents/commits 缓存**
    /// （否则会继续按已不存在的 `ref` 请求而 404）"。
    ///
    /// ⚠️ 缓存失效按**路径前缀**匹配、不看查询串，所以这会把**所有分支**的
    /// contents / commits 缓存一起清掉。这是有意的粗粒度：分清 `?ref=main` 与
    /// `?ref=feature` 需要把查询串纳入键的语义，而"多几个请求"比
    /// "删完分支后一直 404"轻得多。
    ///
    /// - Returns: 无返回值 —— 成功是 **204 No Content**，**没有响应体**。
    public func deleteBranch(owner: String, repo: String, name: String) async throws {
        _ = try await client.send(
            .sending(
                .delete,
                to: client.url("repos/\(owner)/\(repo)/git/refs/heads/\(name)"),
                invalidating: [
                    Self.branchesPrefix(owner: owner, repo: repo),
                    Self.contentsPrefix(owner: owner, repo: repo),
                    Self.commitsPrefix(owner: owner, repo: repo),
                ]
            )
        )
    }

    // MARK: - 写：合并

    /// 合并分支 —— `POST /repos/{o}/{r}/merges`（决策 #52）。
    ///
    /// - Parameters:
    ///   - base: **合进哪条**（目标）。UI 上就是"当前分支"。
    ///   - head: **从哪条来**（源）。这是那个新弹层里用户唯一要做的选择 ——
    ///     决策 #52 说"原型的源分支是自动挑的、用户选不了"，而"哪条合进哪条"
    ///     恰恰是合并唯一的输入。
    ///   - message: 可选的合并提交信息。
    ///
    /// - Returns: `.merged(…)` 或 **`.nothingToMerge`**（后者**不是失败**，
    ///   见 `MergeResultDTO` 的三种结局表）。
    ///
    /// ⚠️ **冲突回 409 ⇒ 抛 `GitHubError.conflict`**。客户端解决不了冲突
    /// （需要的是一份可以编辑的工作区），按 PRD 的文案引导用户去网页端处理。
    /// 注意 409 在本包还有另一个来源 —— 文件保存时 `sha` 已过期（§9.6）——
    /// 所以**文案要按调用点给**，不能在一处把 409 一律说成"合并冲突"。
    public func merge(
        owner: String,
        repo: String,
        base: String,
        head: String,
        message: String? = nil
    ) async throws -> MergeOutcome {
        var payload: [String: String] = ["base": base, "head": head]
        if let message, !message.isEmpty {
            payload["commit_message"] = message
        }
        let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        let response = try await client.send(
            .sending(
                .post,
                to: client.url("repos/\(owner)/\(repo)/merges"),
                body: body,
                invalidating: [
                    // base 分支的 HEAD 动了 ⇒ 三条都要清。
                    Self.branchesPrefix(owner: owner, repo: repo),
                    Self.commitsPrefix(owner: owner, repo: repo),
                    Self.contentsPrefix(owner: owner, repo: repo),
                ]
            )
        )

        // ⚠️ **204 不是错误**（见 MergeResultDTO 的三种结局表）：`head` 已经合进 `base`，
        //    没有任何东西可合 —— 用户想要的结果本来就成立。把它当失败会让用户反复点，
        //    而每次都是 204。
        if response.statusCode == 204 { return .nothingToMerge }

        return .merged(try response.decode(MergeResultDTO.self))
    }

    // MARK: - 缓存前缀

    private static func branchesPrefix(owner: String, repo: String) -> String {
        "/repos/\(owner)/\(repo)/branches"
    }

    private static func contentsPrefix(owner: String, repo: String) -> String {
        "/repos/\(owner)/\(repo)/contents"
    }

    private static func commitsPrefix(owner: String, repo: String) -> String {
        "/repos/\(owner)/\(repo)/commits"
    }
}
