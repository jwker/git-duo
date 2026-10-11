import Foundation
import GitDuoCore

/// 提交详情里的一个文件（PRD §4.7 / §4.11、TECH_SPEC §9.7）。
///
/// ## `patch` 为 `nil` 的**两种**原因，不要混成一句
///
/// `GET /repos/{o}/{r}/commits/{sha}` 的 `files[]` 里，`patch` 会在两种情况下缺席：
///
/// 1. **二进制文件** —— 服务端无法给出文本 diff；
/// 2. **diff 太大** —— GitHub 会省略 patch（大文件或大改动）。
///
/// 两者的**用户出路不同**：二进制是"这里看不了，去网页端"；
/// 太大是"这个 diff 太长，去网页端看"。所以 `isBinary` 把它分开判断 ——
/// 判据复用 `FilePreviewKind` 的扩展名白名单（不引入第二套"什么是二进制"的规则）。
public struct FileChange: Sendable, Hashable, Identifiable {

    /// 仓库内完整路径（`GitDuo/App/AppTabs.swift`）。
    ///
    /// ⚠️ 重命名时 GitHub 还会给 `previous_filename`，本类型**不收**：
    /// 本期没有任何界面要显示"从哪改名的"，收了就是死字段。
    public let filename: String

    public let additions: Int

    public let deletions: Int

    public let status: Status

    /// 该文件的 unified diff 文本（未解析）。`nil` ⇒ 见类型说明。
    public let patch: String?

    /// `ForEach` 的键 —— 一个提交里同名文件只会出现一次。
    public var id: String { filename }

    public init(
        filename: String,
        additions: Int,
        deletions: Int,
        status: Status,
        patch: String? = nil
    ) {
        self.filename = filename
        self.additions = additions
        self.deletions = deletions
        self.status = status
        self.patch = patch
    }

    /// 无 `patch` 时是不是二进制。
    ///
    /// ⚠️ 这是**推断**，不是服务端给的事实（GitHub 不标注 `binary`）。
    /// 判据复用 `FilePreviewKind` 的扩展名白名单 —— 只有文本（含大文本）才不算二进制；
    /// **图片也算二进制**：它虽然能在文件查看页里画出来，但**没有可读的文本 diff**
    /// （GitHub 正因如此不给它 `patch`），在提交详情里说它"二进制"是准确的。
    ///
    /// 这个推断会误判一种情形：扩展名不在白名单里的**文本**文件
    /// （某种自定义的无扩展名文件）会被说成"二进制文件"。
    /// 那比反过来（把二进制当文本、渲染出一屏乱码）轻，故取这一侧。
    public var isBinary: Bool {
        guard patch == nil else { return false }
        switch FilePreviewKind.decide(name: filename, size: nil) {
        case .text, .largeText: return false
        case .image, .unsupported: return true
        }
    }

    /// `files[].status` 的领域化形态。
    ///
    /// ⚠️ 取值集合照官方文档列全（`added` / `removed` / `modified` / `renamed` /
    /// `copied` / `changed`）并留 `unknown` 兜底 —— 它是字符串枚举，
    /// 将来多一个取值时"整页解码失败"是不可接受的（同 `IssueDTO.state` 的处理）。
    public enum Status: String, Sendable, Hashable {
        case added
        case removed
        case modified
        case renamed
        case copied
        case changed
        case unknown

        /// 认不出来的取值 ⇒ `.unknown`。
        public init(rawStatus: String?) {
            self = Status(rawValue: rawStatus ?? "") ?? .unknown
        }
    }
}

/// 提交详情（PRD §4.7、原型 `SCR.commitDetail`）。
///
/// 头部那一行是**逐字**的（原型）：
/// `${作者} 提交于 2 天前 · <span class="sha">${短SHA}</span> · 1 个文件 · +12 −4`。
/// 由于 SHA 是一个**徽章**（等宽 + 蓝底，`.sha`）而不是普通文字，
/// 这里把它拆成三段属性，让视图能分别排版 —— 拼成一个字符串就没法只给 SHA 上样式。
public struct CommitDetail: Sendable, Hashable, Identifiable {

    /// 完整 SHA。
    public let sha: String

    /// 完整提交信息（首行 + 正文）。详情页显示整段。
    public let message: String

    public let authorLogin: String?

    /// 作者时间（`commit.author.date`）。
    public let authoredAt: Date

    /// 增删统计。**可以是 `nil`** —— 服务端对部分提交不下发 `stats`
    /// （与 `patch` 缺席同源：那条路径上它也没算出统计）。
    public let stats: Stats?

    /// 改动的文件。**顺序即服务端给的顺序**（`files[]`），不重排 ——
    /// 用户对照 GitHub 网页端时顺序一致才好对。
    public let files: [FileChange]

    public var id: String { sha }

    public init(
        sha: String,
        message: String,
        authorLogin: String? = nil,
        authoredAt: Date,
        stats: Stats? = nil,
        files: [FileChange] = []
    ) {
        self.sha = sha
        self.message = message
        self.authorLogin = authorLogin
        self.authoredAt = authoredAt
        self.stats = stats
        self.files = files
    }

    public struct Stats: Sendable, Hashable {
        public let additions: Int
        public let deletions: Int

        /// ⚠️ 服务端给的 `total`。用它的理由与 §9.5 的"只读计数不数数组"同源：
        /// **`files[]` 会被服务端截断**，拿数组重算出来的数会小于真实值。
        public let total: Int

        public init(additions: Int, deletions: Int, total: Int) {
            self.additions = additions
            self.deletions = deletions
            self.total = total
        }
    }

    /// 头部第一段：`{作者} 提交于 {时间}`。作者为 `nil` 时只留时间（同 `CommitSummary`）。
    public func authorLine(now: Date) -> String {
        let time = RelativeTime.string(from: authoredAt, now: now)
        guard let authorLogin, !authorLogin.isEmpty else { return "提交于 \(time)" }
        return "\(authorLogin) 提交于 \(time)"
    }

    /// 头部第三段：`{N} 个文件 · +{增} −{删}`；`stats` 缺席时只留 `{N} 个文件`。
    ///
    /// ⚠️ `N` 用 **`files.count`** 而不是 `stats.total`：这两个数说的是不同东西 ——
    /// `stats.total` 是"改了**多少行**的合计"，`files.count` 才是"多少个文件"。
    /// 而 PRD §4.7 那句 `{N} 个文件` 指的是后者。两者都是数字，
    /// 读错不会报错、只会显示一个偏大或偏小的数（大改动里 `total` 动辄上千）。
    public var statsLabel: String {
        let count = "\(files.count) 个文件"
        guard let stats else { return count }
        return "\(count) · +\(stats.additions) −\(stats.deletions)"
    }

    /// 短 SHA 徽章（与 `CommitSummary.shortSHA` 同位）。
    public var shortSHA: String { String(sha.prefix(CommitSummary.shortSHALength)) }

    /// 提交信息的首行（详情页标题）。
    ///
    /// ⚠️ 空白信息（少见的空 message）回落到完整 SHA —— 与提交列表行同规矩：
    /// 空白标题与"还没加载出来"在界面上是同一种样子。
    public var headline: String {
        // 与提交列表行共用同一个实现，见 `CommitMessage`
        CommitMessage.firstLine(message, fallback: sha)
    }

    /// 提交信息的**正文**（首行之后的全部内容）。没有正文时为 `nil`。
    ///
    /// 详情页在标题下面显示它；为 `nil` 时那一块整个不渲染（不画一片空白）。
    public var body: String? {
        CommitMessage.body(message)
    }
}
