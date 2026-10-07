import Foundation

/// 提交的作者签名（git 的 `author` / `committer`，**不是** GitHub 账号）。
///
/// ## ⚠️ 它与 `CommitUserDTO` 是**两件事**，别混
///
/// - 本类型（`commit.author`）来自 git 本身，只有 `name` / `email` / `date`，
///   **提交里永远有它**，即使那个邮箱压根没关联 GitHub 账号；
/// - `CommitUserDTO`（顶层 `author`）是 GitHub 侧的**账号**，可能是 `null`
///   （邮箱没关联账号、账号已删除、提交是 CLI 推送的）。
///
/// PRD §3.7 的提交行要显示**账号名**（`{作者} 提交于 {时间}`），所以真正需要的是后者；
/// 前者的用途只有一个 —— 当账号缺席时，**时间仍然拿得到**（见 `CommitInfoDTO.authoredAt`）。
public struct CommitSignatureDTO: Sendable, Equatable, Decodable {

    public let name: String?

    public let email: String?

    /// ⚠️ 声明成可选：官方 schema 里 `commit.author` 整个对象是 `nullable` 的
    /// （畸形历史、部分导入的仓库会这样返回）。
    public let date: Date?

    public init(name: String? = nil, email: String? = nil, date: Date? = nil) {
        self.name = name
        self.email = email
        self.date = date
    }
}

/// GitHub 侧的提交账号 —— 顶层 `author` / `committer`。
///
/// ⚠️ **可以是 `null`**：邮箱没关联到任何账号时 GitHub 就返回 `null`。
/// 这与 `IssueDTO.user` 同源，声明成必需会让整页打不开。
public struct CommitUserDTO: Sendable, Equatable, Decodable {

    public let login: String?

    public let avatarURL: URL?

    public init(login: String? = nil, avatarURL: URL? = nil) {
        self.login = login
        self.avatarURL = avatarURL
    }

    private enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatar_url"
    }
}

/// `commit` 子对象 —— 列表项与详情**共用**这一段（两者的字段完全一致）。
///
/// ## ⚠️ `authoredAt` 为什么是必需字段，以及它从哪来
///
/// 列表行要写 `{作者} 提交于 {时间}`，领域模型 `CommitSummary.authoredAt` 是**非可选**的
/// （`Date`）—— 没有时间就没有那一行文案，也就没有这一行。
///
/// 所以这里做一条**回落链**：`commit.author.date` ⇒（作者整个对象缺席时）`commit.committer.date`。
/// 两者的 `date` 在实测与官方 schema 里恒存在；**两条都没有**意味着这个提交的
/// committer 对象也缺席，那就只剩两种做法：
///
/// - 编一个时间（`Date()` / 纪元 0）—— **错误的值比没有值更危险**，一行写着
///   "1970 年提交"的记录比"这一条加载不出来"糟得多；
/// - 解码失败 —— 本类型选这个。它同时意味着整个列表打不开，但那种畸形提交
///   在真实仓库里并不存在（GitHub 自己的 `commits` 端点也依赖同一批字段）。
///
/// 换句话说：这条路走不通时**不是数据缺失，是响应结构变了** ——
/// 那时"整个列表报错"恰恰是我们想要的信号。
public struct CommitInfoDTO: Sendable, Equatable, Decodable {

    /// 完整提交信息（首行 + 正文），**不在这里裁剪**。
    ///
    /// 首行怎么取是展示规则（`CommitSummary.message` / `CommitDetail.headline`），
    /// 在本层裁掉的话，提交详情页要显示的那段正文就永远拿不到了。
    public let message: String

    public let author: CommitSignatureDTO?

    public let committer: CommitSignatureDTO?

    /// 作者时间 —— 提交列表行与详情页头部都用它。
    public let authoredAt: Date

    public init(
        message: String,
        author: CommitSignatureDTO? = nil,
        committer: CommitSignatureDTO? = nil,
        authoredAt: Date
    ) {
        self.message = message
        self.author = author
        self.committer = committer
        self.authoredAt = authoredAt
    }

    private enum CodingKeys: String, CodingKey {
        case message
        case author
        case committer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        author = try container.decodeIfPresent(CommitSignatureDTO.self, forKey: .author)
        committer = try container.decodeIfPresent(CommitSignatureDTO.self, forKey: .committer)

        guard let date = author?.date ?? committer?.date else {
            throw DecodingError.dataCorruptedError(
                forKey: .author,
                in: container,
                debugDescription: """
                这个提交既没有 commit.author.date 也没有 commit.committer.date。\
                代码不会再往上回落（编一个时间会产出一个"看着合理"的错值），\
                见 CommitInfoDTO 的类型说明。
                """
            )
        }
        authoredAt = date
    }
}

/// 提交列表的一行 —— `GET /repos/{owner}/{repo}/commits`（PRD §3.7、§4.4 分区四、TECH_SPEC §4.6.2）。
///
/// ## ⚠️ 列表项**不含** `files` / `stats`（2026-10-07 实测）
///
/// 增删统计只在提交详情 `commits/{sha}` 里。所以"列表页顺手把统计也拿回来"
/// 这件事**做不到** —— 想在列表行上写 `+12 −4` 就得为每一条补一次详情请求。
/// 本切片不这么做（原型列表行也只有作者/时间/短 SHA）。
public struct CommitListItemDTO: Sendable, Equatable, Decodable {

    public let sha: String

    public let commit: CommitInfoDTO

    /// GitHub 账号。**可以是 `null`**（见 `CommitUserDTO`）。
    public let author: CommitUserDTO?

    /// 作者时间（`commit.author.date`，见 `CommitInfoDTO.authoredAt`）。
    public var authoredAt: Date { commit.authoredAt }

    public init(sha: String, commit: CommitInfoDTO, author: CommitUserDTO? = nil) {
        self.sha = sha
        self.commit = commit
        self.author = author
    }

    // ⚠️ **有意不收 `parents` / `node_id` / `url` / `html_url` / `committer`：
    //     本切片没有一处界面要用它们（Revert 已定为跳网页端，§9.7.3）。
    //     网页端地址由仓库全名 + SHA 在视图层拼，不需要服务端给。
}

/// 提交详情里的**一个文件** —— `commits/{sha}` 的 `files[]`。
public struct CommitFileDTO: Sendable, Equatable, Decodable {

    public let filename: String

    public let additions: Int

    public let deletions: Int

    /// `added` / `removed` / `modified` / `renamed` / `copied` / `changed`。
    ///
    /// ⚠️ 原样保留字符串（**不枚举化**）：它是仍在演进的取值集合，
    /// 枚举化会让"某天多一个取值"表现为整页解码失败。
    /// 领域层 `FileChange.Status(rawStatus:)` 负责兜底成 `.unknown`。
    public let status: String?

    /// 该文件的 unified diff 文本。
    ///
    /// ⚠️ `nil` 有**两种**原因（二进制 / diff 太大），用户出路不同 ——
    /// 分开判定在领域层 `FileChange.isBinary`（切片 6.1），数据层原样带出去。
    public let patch: String?

    public init(
        filename: String,
        additions: Int,
        deletions: Int,
        status: String? = nil,
        patch: String? = nil
    ) {
        self.filename = filename
        self.additions = additions
        self.deletions = deletions
        self.status = status
        self.patch = patch
    }

    // ⚠️ 不收 `sha` / `blob_url` / `raw_url` / `contents_url` / `previous_filename` ——
    //    见 `FileChange` 的说明（"本期没有任何界面要显示从哪改名的"）。
}

/// 提交的增删统计 —— `stats{additions, deletions, total}`。
public struct CommitStatsDTO: Sendable, Equatable, Decodable {

    public let additions: Int

    public let deletions: Int

    /// ⚠️ **改了「多少行」的合计**，不是"多少个文件"。
    /// 领域层 `CommitDetail.statsLabel` 的 `{N} 个文件` 用的是 `files.count`，
    /// 两者都是数字，读错不会报错、只会显示一个偏大或偏小的数。
    public let total: Int

    public init(additions: Int, deletions: Int, total: Int) {
        self.additions = additions
        self.deletions = deletions
        self.total = total
    }
}

/// 提交详情 —— `GET /repos/{owner}/{repo}/commits/{sha}`（PRD §4.7、TECH_SPEC §4.6.2）。
///
/// 列表项的全部字段 + `stats` + `files[]`（含 `patch`）。把两段拆成两个类型
/// （列表项 / 详情）而不是"一个类型加一堆可选字段"，是因为**同一个类型在两种响应里
/// 语义不同**：列表项的 `files` 永远是空的（服务端不给），而详情的 `files` 是核心内容。
/// 合一之后，"列表里怎么没有 files"会变成每次都要回忆一遍的事。
public struct CommitDetailDTO: Sendable, Equatable, Decodable {

    public let sha: String

    public let commit: CommitInfoDTO

    public let author: CommitUserDTO?

    /// 增删统计。**可以是 `nil`** —— 服务端对部分提交（尤其是空提交、合并提交）
    /// 不下发 `stats`。这与 `patch` 缺席同源：那条路径上它也没算出统计。
    public let stats: CommitStatsDTO?

    /// 改动的文件。**顺序即服务端给的顺序**，不重排 ——
    /// 用户对照 GitHub 网页端时顺序一致才好对。
    public let files: [CommitFileDTO]

    public var authoredAt: Date { commit.authoredAt }

    public init(
        sha: String,
        commit: CommitInfoDTO,
        author: CommitUserDTO? = nil,
        stats: CommitStatsDTO? = nil,
        files: [CommitFileDTO] = []
    ) {
        self.sha = sha
        self.commit = commit
        self.author = author
        self.stats = stats
        self.files = files
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sha = try container.decode(String.self, forKey: .sha)
        commit = try container.decode(CommitInfoDTO.self, forKey: .commit)
        author = try container.decodeIfPresent(CommitUserDTO.self, forKey: .author)
        stats = try container.decodeIfPresent(CommitStatsDTO.self, forKey: .stats)
        // ⚠️ `files` 缺席 ⇒ 空数组（**不是**解码失败）：字段缺席意味着"这个提交没有文件改动"
        //（空提交就是这样），而不是"响应坏了"。`defaultIfPresent` 在这里比 `decode` 诚实。
        files = try container.decodeIfPresent([CommitFileDTO].self, forKey: .files) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case sha
        case commit
        case author
        case stats
        case files
    }
}
