import Foundation
import GitHubAPI

/// 提交的 DTO → 领域模型映射（PRD §3.7 / §4.4 分区四 / §4.7、TECH_SPEC §4.6.2）。
public enum RepoCommitMapper {

    // MARK: - 列表行

    /// 提交列表项 → 列表行。
    ///
    /// ⚠️ **`message` 只留首行**（`CommitMessage.firstLine`）：`CommitSummary` 是**列表行**
    /// 的模型，它的标题就是提交信息的首行。整段塞进一行会被省略号截在随机位置 ——
    /// 而完整信息在 `CommitDetail.message` 里，一点就进。
    ///
    /// ⚠️ 首行回落到**短 SHA**：一条空信息的提交若显示成空白标题，
    /// 用户会以为"这一条没加载完"。
    public static func summary(_ dto: CommitListItemDTO) -> CommitSummary {
        CommitSummary(
            sha: dto.sha,
            message: CommitMessage.firstLine(
                dto.commit.message,
                fallback: String(dto.sha.prefix(CommitSummary.shortSHALength))
            ),
            authorLogin: dto.author?.login,
            avatarURL: dto.author?.avatarURL,
            authoredAt: dto.authoredAt
        )
    }

    // MARK: - 详情

    /// 提交详情 → 详情页模型。
    ///
    /// ⚠️ **`message` 是完整信息**（不裁首行）：详情页要显示标题**和正文**，
    /// 首行怎么取由 `CommitDetail.headline` 现算 —— 在这里裁掉的话正文就永远拿不到了。
    ///
    /// ⚠️ `files[]` 的**顺序原样保留**（不按增删排序）：用户对照 GitHub 网页端时
    /// 顺序一致才好对。
    public static func detail(_ dto: CommitDetailDTO) -> CommitDetail {
        CommitDetail(
            sha: dto.sha,
            message: dto.commit.message,
            authorLogin: dto.author?.login,
            authoredAt: dto.authoredAt,
            stats: dto.stats.map {
                // ⚠️ `total` 原样带过去，**不用 `additions + deletions` 重算**：
                //    它是服务端给的"改了**多少行**的合计"（含重复计数口径），
                //    与两个分量相加并不总是相等，而界面上那两个数必须与服务端一致。
                CommitDetail.Stats(additions: $0.additions, deletions: $0.deletions, total: $0.total)
            },
            files: dto.files.map { file in
                FileChange(
                    filename: file.filename,
                    additions: file.additions,
                    deletions: file.deletions,
                    // 认不出的 status ⇒ `.unknown`（`FileChange.Status(rawStatus:)` 兜底），
                    // 不让一个新增取值把整页变成解码失败
                    status: FileChange.Status(rawStatus: file.status),
                    patch: file.patch
                )
            }
        )
    }
}
