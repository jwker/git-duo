import Foundation

/// 文件树的一行（PRD §3.2、TECH_SPEC §9.5）。
///
/// ## ⚠️ 副标题是**分两趟来的**（决策 #49）
///
/// PRD §3.2 要求每行写一条「最近提交信息」，原型每行也都画着它（`f.msg`）。
/// 但目录清单接口 `GET /repos/{o}/{r}/contents/{path}` 的返回项里
/// **一个提交字段都没有**（2026-10-07 实测，只有 `name`/`path`/`sha`/`size`/`type`
/// 与几个 URL）；`git/trees` 同样没有 —— GitHub **没有**任何批量接口能把它带出来。
///
/// 于是它是"逐条补一次 `GET …/commits?path={p}&per_page=1`"换来的
/// ⇒ 模型里它必须是 **`Optional`**，且**允许在列表已经显示之后才填上**：
/// 30 项的目录若等 30 个请求全回来才渲染，用户会盯着骨架屏看很久，
/// 而那条副标题其实谁也等不来。
///
/// ## ⚠️ `nil` 同时意味着"还没回来"与"取不到"
///
/// 这是**有意**的取舍：视图对两者的处理完全一样（不渲染副标题那一行），
/// 而区分它们需要给每一行维护一个小状态机，收益只是"日志里能看出区别"。
/// 代价是"取失败"会静默表现为空白 —— 已登记为已知偏差，见 `REVIEW-CHECKLIST`。
public struct TreeEntry: Sendable, Hashable, Identifiable {

    /// 条目名（不含路径）。⚠️ 面包屑与目录行显示的都是它，不是 `path`。
    public let name: String

    /// 仓库内**完整**路径（`docs/guide.md`）—— 进下一级、打开文件都用它。
    ///
    /// 与 `name` 分开存是有意的：只用 `name` 的话，在**子目录里**点一个文件时
    /// 得先知道"现在在哪一层"，而那个信息在导航栈里、不在这一行上；
    /// 结果是"点文件打开的却是根目录里的同名文件"。
    public let path: RepoPath

    public let kind: Kind

    /// 字节数。**目录为 0**（`contents` 对目录不下发 `size`）。
    public let size: Int

    /// 该条目的 blob / tree SHA。⚠️ 编辑器保存时要用它（§9.6 的 `PUT …/contents/{path}`
    /// 以 `sha` 表示"更新"），所以不能因为本页只读就丢掉。
    public let sha: String

    /// 最近一次改动这个条目的提交（决策 #49）。
    public let recentCommit: RecentCommit?

    /// `ForEach` 的键 —— 路径在仓库内唯一。
    public var id: String { path.raw }

    public init(
        name: String,
        path: RepoPath,
        kind: Kind,
        size: Int,
        sha: String,
        recentCommit: RecentCommit? = nil
    ) {
        self.name = name
        self.path = path
        self.kind = kind
        self.size = size
        self.sha = sha
        self.recentCommit = recentCommit
    }

    /// 目录行的副标题。取不到时为 `nil` ⇒ **视图整行不渲染**（不写占位文字）。
    ///
    /// ⚠️ 为什么不给一个占位（如 `—` 或 `读取中…`）：决策 #49 明写
    /// "副标题随请求陆续填充、不阻塞列表先出"，而一行里的 `读取中…` 会在
    /// 请求回来后被替换成真内容 —— 30 行同时跳一次文字，比它晚一点出现更刺眼。
    public var subtitle: String? { recentCommit?.summary }

    public enum Kind: Sendable, Hashable {

        /// 目录 —— 点击进下一级。
        case directory

        /// 普通文件 —— 点击进文件查看页（§4.5）。
        case file

        /// ⚠️ **原型没有这一档**（PRD §3.2 只写 `dir` / `file`），但 `contents` 的
        /// `type` 还会是 `symlink` / `submodule`：
        ///
        /// - `symlink` 的 `content` 是**链接目标那串文本**，不是文件内容 ——
        ///   当普通文件打开会显示出一行 `../foo/bar` 并让用户以为文件内容就是这个；
        /// - `submodule` 的 `size` 是 0、`sha` 是**另一个仓库的提交**，
        ///   点进去请求 contents 只会 404。
        ///
        /// 两者都归到这一档：行**照常显示**（形态与目录/文件一致），
        /// 但不可进入，点按给出一个跳网页端的出口。少列一档的代价是
        /// "这类条目在 App 里点不动、也没有解释"，而那正是原型不覆盖时不该编的东西。
        case unsupported

        /// 能不能点进去（目录进下一级；文件开文件页）。
        public var isNavigable: Bool {
            switch self {
            case .directory, .file: true
            case .unsupported: false
            }
        }
    }
}

/// 「最近提交信息」—— `GET …/commits?path={p}&per_page=1` 取回的**第一条**。
///
/// 列在这里而不是复用 `CommitSummary`（提交列表行）的原因：本类型只承载
/// 目录行那一行小字所需的三样东西（信息首行、SHA、时间），
/// 而 `CommitSummary` 还要管作者头像与跳详情页。两者字段集互有出入，
/// 与 `Repository` / `RepositoryDetail` 不合并同源。
public struct RecentCommit: Sendable, Hashable {

    /// 提交信息的**首行**。
    ///
    /// ⚠️ 只取首行不是裁剪展示，是语义：一条 commit message 的首行是它的标题
    /// （git 的约定），后面那些段落属于正文。整段塞进 11.5pt 的一行里，
    /// 会被省略号截在一个随机位置。
    public let message: String

    public let sha: String

    /// 作者登录名。**可以是 `nil`** —— 账号被删除后 GitHub 把 `author` 整段置为 `null`
    /// （同 `IssueRow.authorLogin` 的处理）。
    public let authorLogin: String?

    public let authoredAt: Date

    public init(message: String, sha: String, authorLogin: String? = nil, authoredAt: Date) {
        self.message = message
        self.sha = sha
        self.authorLogin = authorLogin
        self.authoredAt = authoredAt
    }

    /// 目录行副标题：提交信息的首行（原型 `f.msg` 逐字就是这个）。
    ///
    /// 空信息（有些提交的 message 是空串）回落到短 SHA —— 否则那一行会是**空白**，
    /// 而空白与"还没加载出来"（`nil`）在界面上是同一种样子，
    /// 会让用户以为这条一直没加载完。
    public var summary: String {
        let firstLine = message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if firstLine.isEmpty { return String(sha.prefix(7)) }
        return firstLine
    }
}
