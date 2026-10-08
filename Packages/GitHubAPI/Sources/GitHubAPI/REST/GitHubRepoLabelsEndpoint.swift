import Foundation

/// 仓库标签库 —— `GET/POST /repos/{owner}/{repo}/labels`
/// （TECH_SPEC §9.8、PRD §5.2 标签选择 / 新建、决策 #56）。
///
/// ## 为什么单独成一个类型
///
/// 标签是**仓库级**资源（同一仓库内名字唯一），不是 Issue 的子资源 ——
/// `GET /labels` 拿回来的是整份标签库，用来填 §5.2 那个选择器的上段；
/// 而 Issue 只用其中若干个（`IssueDTO.labels` / 新建时的 `labels[]`）。
/// 挂在 `GitHubRepoIssuesEndpoint` 上会让"标签与 Issue 是两件事"这件事看不出来。
///
/// ## 本片只做两件事：**列出**与**新建**
///
/// 重命名 / 删除 / 改色都不在 PRD 里（§5.2 只有"选择"与"新建标签"），
/// 所以 `PATCH` / `DELETE /labels/{name}` 不声明 —— 端点表里有它 ≠ 产品范围里有它
/// （与决策 #62 对 `PATCH …/issues/{n}` 的判据同源）。
public struct GitHubRepoLabelsEndpoint: Sendable {

    /// 标签库页大小 —— 取端点上限 **100**。
    ///
    /// §5.2 的选择器要列出**本仓库全部标签**（原型 `REPO_LABELS` 是 5 个，
    /// 但真实仓库常有几十个），而一页 30 条会让"标签列表只显示了一部分"
    /// 变成屏幕上完全看不出来的事。100 条覆盖绝大多数仓库；
    /// 出现下一页时由 `nextCursor` 兜住（调用方`LabelCatalog` 会继续取）。
    public static let pageSize = 100

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    // MARK: - 读：标签库

    /// 仓库的全部标签 —— `GET /repos/{o}/{r}/labels`。
    ///
    /// ⚠️ 服务端**按字母序**返回（`sort=name`、`direction=asc` 是它的默认值，
    /// 这里显式写出来 —— 隐式默认值一旦被服务端改掉，表现是"缓存莫名换了一份"）。
    /// 界面上的顺序因此是稳定且可预期的，不需要客户端再排一次
    /// （再排一次反而可能与用户对照的网页端顺序不一致）。
    public func labels(
        owner: String,
        repo: String,
        cursor: URL? = nil
    ) async throws -> Page<LabelDTO> {
        if let cursor {
            return try await client.page(at: cursor, as: LabelDTO.self)
        }
        return try await client.page(
            "repos/\(owner)/\(repo)/labels",
            query: [
                URLQueryItem(name: "per_page", value: String(Self.pageSize)),
                URLQueryItem(name: "sort", value: "name"),
                URLQueryItem(name: "direction", value: "asc")
            ],
            as: LabelDTO.self
        )
    }

    // MARK: - 写：新建标签

    /// 新建标签 —— `POST /repos/{o}/{r}/labels`（PRD §5.2 下段「新建标签」）。
    ///
    /// - Parameters:
    ///   - name: 标签名。**调用方保证非空且未重名** —— §5.2 的校验
    ///     （空名提示先填写 / 重名自动选中）是**产品口径**，属领域层 `LabelCatalog`。
    ///     ⚠️ 重名时服务端回 **422**，而那条 422 的文案是机器话术
    ///     （用户读成"服务器坏了"）⇒ 领域层**提前本地去重**、不发那次必败的请求
    ///     （§9.8 写明了这一点）。本方法不代替那层校验。
    ///   - color: **六位十六进制、不带 `#`**（`"d73a4a"`）。
    ///     ⚠️ 顺手的"补一个 `#`"会被服务端拒掉 —— `LabelDTO` 的说明里两个方向都写了。
    ///     本方法**不做美化也不做剥除**：静默改写参数会把调用方的 bug 藏起来，
    ///     而这条 422 的成因恰好是"客户端自己拼错了"，藏起来下次还会犯。
    ///
    /// - Returns: 服务端回的那条标签（**201**）—— 用它的 `name` 追加并选中，
    ///   而不是拿本地输入造一条（那样 `name` 的裁剪规则就与服务端分叉了）。
    public func createLabel(
        owner: String,
        repo: String,
        name: String,
        color: String
    ) async throws -> LabelDTO {
        let body = try JSONSerialization.data(
            withJSONObject: ["name": name, "color": color],
            options: [.sortedKeys]
        )
        let response = try await client.send(
            .sending(
                .post,
                to: client.url("repos/\(owner)/\(repo)/labels"),
                body: body,
                // 标签库变了 ⇒ 不失效的话"新建完打开选择器看不到它"
                //（下拉刷新绕缓存，看不出问题）。
                invalidating: [Self.labelsPrefix(owner: owner, repo: repo)]
            )
        )
        return try response.decode(LabelDTO.self)
    }

    // MARK: - 缓存前缀

    private static func labelsPrefix(owner: String, repo: String) -> String {
        "/repos/\(owner)/\(repo)/labels"
    }
}
