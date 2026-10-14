import Foundation
import GitDuoCore

/// 提交列表的一行（PRD §3.7、§4.4.4；原型 `SCR.repoSection` 里 `repoSeg('commits')` 那支的 `commit-row`）。
///
/// ## ⚠️ 2026-10-11：同族的 `RecentCommit` 已删
///
/// 原有一个只服务"文件树每行那一行小字"的兄弟类型（决策 #49 的逐条补请求），
/// 已随那条链路一起删除。本类型从此是**提交**这条线上唯一的行模型。
public struct CommitSummary: Sendable, Hashable, Identifiable {

    /// 完整 SHA —— 跳详情页用的键。
    public let sha: String

    /// 提交信息**首行**（拆分规则见 `CommitMessage.firstLine`）。
    public let message: String

    /// 作者登录名。**可以是 `nil`** —— 账号被删除后 GitHub 把 `author` 整段置为 `null`，
    /// 而提交本身仍然存在（`commit.author.name` 还在）。
    public let authorLogin: String?

    /// 头像地址。`authorLogin` 与它同生共死（同一个 `user` 对象里出来的两件事）。
    public let avatarURL: URL?

    /// 提交时刻（作者时间 `commit.author.date`）。
    public let authoredAt: Date

    /// 短 SHA 的位数 —— 7 位与 `git log --oneline`、GitHub 网页端一致。
    public static let shortSHALength = 7

    /// 卡片右侧那枚徽章上的短哈希。
    public var shortSHA: String { String(sha.prefix(Self.shortSHALength)) }

    /// `ForEach` 的键 —— SHA 在一个仓库内唯一。
    public var id: String { sha }

    public init(
        sha: String,
        message: String,
        authorLogin: String? = nil,
        avatarURL: URL? = nil,
        authoredAt: Date
    ) {
        self.sha = sha
        self.message = message
        self.authorLogin = authorLogin
        self.avatarURL = avatarURL
        self.authoredAt = authoredAt
    }

    /// 卡片第二行：`{作者} 提交于 {时间}`（原型 `commit-row` 的 `.t3`，逐字句式）。
    ///
    /// ⚠️ 作者为 `nil` 时**整段去掉**、只留时间 —— 原型那处会拼出 `undefined 提交于 …`
    /// （它的演示数据里每个提交都有作者，所以看不出问题）。
    /// 同 `IssueRow.metaLabel` 的处理。
    public func metaLabel(now: Date) -> String {
        let time = RelativeTime.string(from: authoredAt, now: now)
        guard let authorLogin, !authorLogin.isEmpty else { return "提交于 \(time)" }
        return "\(authorLogin) 提交于 \(time)"
    }

    // ⚠️ **没有「头像首字母」这类派生属性**，是有意的：首字母与 djb2 兜底色的算法
    // 在 `GitDuoDesign` 的 `UserAvatar`（5.3 时从 `AvatarStack` 提上来的**唯一实现**）。
    // 在这里再算一遍就是第二套算法，而两套的差异会表现为
    // "同一个用户在两个页面显示成不同颜色"。视图把 `authorLogin` 交给 `UserAvatar` 即可。
}
