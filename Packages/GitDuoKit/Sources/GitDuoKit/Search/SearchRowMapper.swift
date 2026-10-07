import Foundation
import GitHubAPI

/// `SearchRow` 的映射 —— 四个范围的 DTO → 结果行（PRD §4.2、TECH_SPEC §9.2）。
///
/// ## 为什么单独一层、而且是**纯函数**
///
/// 四范围的结果字段各不相同，而"哪些字段有、哪些没有"的翻译正是**业务判断**：
///
/// - 代码行的所属仓库要从 `repository_url` 解出来（解错了那一行的 `id` 与去向全错）；
/// - 会话行的"已合并"要由 `merged_at` 算出来（GitHub 没有独立的 `merged` 状态）；
/// - 语言 / 人数 / 摘要缺失时，副标题该整段去掉而不是显示 `undefined` 或 `0`。
///
/// 这些规则必须能被单测钉住。放进 `GitHubSearchDataSource` 里也能测，但要**先起一套 HTTP 桩件**
/// —— 而它们与网络毫无关系（这一层只看 DTO）。收在这里 ⇒ 本包的单测直接喂 DTO
/// （同 `RepositoryMapper` / `RepoSummaryMapper` 的分工）。
public enum SearchRowMapper {

    // MARK: - 四种行

    /// 仓库行。
    ///
    /// `owner` / `name` 的拆分交给 `RepositoryHit` 自己（它走 `RepositoryMapper.splitFullName`
    /// 那一个实现，形状不符时不猜）—— 这里**不重复拆一遍**。
    public static func repository(_ dto: SearchRepositoryDTO) -> RepositoryHit {
        RepositoryHit(
            fullName: dto.fullName,
            description: dto.description,
            language: dto.language,
            starCount: dto.starCount
        )
    }

    /// 用户行。
    ///
    /// 三个可选字段原样带过去（`nil` = 不知道，见 `SearchUserDTO`），**不填默认值**。
    public static func user(_ dto: SearchUserDTO) -> UserHit {
        UserHit(
            login: dto.login,
            name: dto.name,
            bio: dto.bio,
            publicRepoCount: dto.publicRepos,
            followerCount: dto.followers
        )
    }

    /// 代码行。
    ///
    /// - Throws: `RepositoryMappingError.malformedFullName` —— 响应里的仓库全名不是
    ///   `owner/name`（**校验契约，不是容错**：猜一个 owner 会让这一行的去向指向不存在的仓库）。
    public static func code(_ dto: SearchCodeDTO) throws -> CodeHit {
        // 只为**校验**：`CodeHit` 存的是整串 `repoFullName`，拆分的唯一实现在 `RepositoryMapper`。
        _ = try RepositoryMapper.splitFullName(dto.repository.fullName)

        return CodeHit(
            path: dto.path,
            repoFullName: dto.repository.fullName,
            language: dto.language,
            snippet: snippet(from: dto.textMatches)
        )
    }

    /// 会话行。
    ///
    /// - Throws: `RepositoryMappingError.malformedFullName` —— `repository_url` 不是
    ///   `…/repos/{owner}/{repo}` 的形状。
    ///
    /// ⚠️ **类型取自响应**（`dto.isPullRequest`，判据是 `pull_request` 字段的存在性），
    /// 不取自我们发出的那条查询 —— 理由见 `SearchQueryBuilder.parts` 的说明。
    /// **状态取自 `state` + `merged_at`**，判定收在 `PullRequestState(state:mergedAt:)`
    /// 那一个初始化器里（Issue 没有 `merged_at` ⇒ 只会取到 `.open` / `.closed`）。
    public static func conversation(_ dto: SearchConversationDTO) throws -> ConversationHit {
        ConversationHit(
            kind: dto.isPullRequest ? .pullRequest : .issue,
            number: dto.number,
            title: dto.title,
            repoFullName: try repositoryFullName(fromRepositoryURL: dto.repositoryURL),
            state: PullRequestState(state: dto.state, mergedAt: dto.pullRequest?.mergedAt),
            updatedAt: dto.updatedAt
        )
    }

    // MARK: - 两处需要解释的解析

    /// 从 `repository_url` 解出 `owner/repo`。
    ///
    /// 搜索是**跨仓库**的，而 `/search/issues` 的条目里只有两个能定位仓库的东西：
    /// `repository_url`（**必需**，形如 `https://api.github.com/repos/{owner}/{repo}`）
    /// 与 `repository`（**可选**的整个仓库对象）。取必需的那个。
    ///
    /// ## 为什么不是"容错解析"
    ///
    /// 与 `RepositoryMapper.splitFullName` 同一条纪律：这是在**校验一条契约**，
    /// 不成立就说明响应的含义变了，此时必须响亮地失败 ——
    /// 猜一个仓库出来会让这一行的 `id` 与点击去向都指向别处（用户看到的是一个 404）。
    ///
    /// 解出来的两段仍走 `splitFullName` 校验一次（`owner/name` 恰好两段且都非空），
    /// 免得这里放行一个 `repos/a%2Fb/c` 之类的怪形状。
    public static func repositoryFullName(fromRepositoryURL url: URL) throws -> String {
        // `URL.pathComponents` 的首项是 `"/"`，过滤掉它再判形状。
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 3, parts[0] == "repos" else {
            throw RepositoryMappingError.malformedFullName(url.absoluteString)
        }

        let fullName = "\(parts[1])/\(parts[2])"
        _ = try RepositoryMapper.splitFullName(fullName)
        return fullName
    }

    /// 代码预览行：取**第一处**命中的 `fragment`，并折成一行。
    ///
    /// ## 为什么要折成一行
    ///
    /// 服务端返回的 `fragment` 是多行原文（命中上下文的整段）。卡片是一行 `.sr-code`，
    /// 直接塞多行会把行高撑开、并把**命中那一行**挤出可见范围。
    /// 折法是"把连续空白（含换行）压成一个空格再修两端" —— 不改字符内容，只改排版，
    /// 于是"这一行命中了什么"仍然看得见。
    ///
    /// - Returns: 没有任何可用片段时返回 `nil`（卡片**不渲染**这一行，而不是显示空框）。
    public static func snippet(from matches: [SearchCodeDTO.TextMatch]?) -> String? {
        guard let matches else { return nil }
        for match in matches {
            guard let fragment = match.fragment else { continue }
            let line = singleLine(fragment)
            if !line.isEmpty { return line }
        }
        return nil
    }

    /// 连续空白（含换行）压成一个空格，并去掉两端。
    static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
