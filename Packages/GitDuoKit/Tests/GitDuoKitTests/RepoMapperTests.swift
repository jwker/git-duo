import Foundation
import Testing

import GitHubAPI
@testable import GitDuoKit

/// 代码浏览 / 提交 / 分支的 DTO → 领域模型映射（切片 6.2 数据层）。
///
/// 这一层的靶心是**几条错了不会报错、只会显示成别的东西**的翻译规则：
/// `type` 的四取值落到三档 `Kind`、`message` 的首行 / 正文拆分、
/// `protected` 必须原样带过去（丢一个字面量就会多出一个必然失败的删除按钮）。
@Suite("切片 6 数据层 · DTO → 领域模型映射")
struct RepoMapperTests {

    /// 2026-10-05T08:00:00Z。
    ///
    /// ⚠️ 用 epoch 而不是 `ISO8601DateFormatter` 或者 `GitHubAPI` 里的 `GitHubDate`：
    /// 后者的 `GitHubDate` 是 **internal** 的，而**跨包没有 `@testable`**
    /// （`@testable` 只对同一个 module 的测试 target 生效）—— 这正是本包测试
    /// 看不见 `GitHubAPI` 内部类型的原因。
    private let authoredAt = Date(timeIntervalSince1970: 1_791_187_200)

    // MARK: - 目录条目 → TreeEntry

    @Test("四种 type 落到三档 Kind：只有 file / dir 可进入，其余全部不可进入")
    func mapsContentTypeToKind() {
        let cases: [(RepoContentType, TreeEntry.Kind)] = [
            (.file, .file),
            (.directory, .directory),
            // symlink 的 content 是链接目标那串文本；submodule 的 sha 是另一个仓库的提交
            (.symlink, .unsupported),
            (.submodule, .unsupported),
            // 认不出的取值也必须落在"点不动"那一档，而不是当文件打开
            (.unknown, .unsupported),
        ]

        for (type, expected) in cases {
            #expect(RepoFileMapper.kind(of: type) == expected, "\(type) 应当映射成 \(expected)")
            #expect(
                RepoFileMapper.kind(of: type).isNavigable == (type == .file || type == .directory),
                "\(type) 的可进入性错了"
            )
        }
    }

    @Test("treeEntry：路径按服务端给的整串解析，size 缺席 ⇒ 0")
    func mapsDirectoryEntry() {
        let dto = ContentEntryDTO(
            name: "guide.md",
            path: "docs/guide.md",
            sha: "blob-sha",
            size: nil,
            type: .file
        )

        let entry = RepoFileMapper.treeEntry(dto)

        #expect(entry.name == "guide.md")
        #expect(entry.path.raw == "docs/guide.md")
        #expect(entry.path.components == ["docs", "guide.md"])
        #expect(entry.size == 0)
        #expect(entry.sha == "blob-sha")
        // ⚠️ 副标题是决策 #49 那一次补请求换来的，目录清单里没有 ⇒ 映射后必须是 nil
        //    （视图据此"整行不渲染"，而不是显示一个占位）
        #expect(entry.recentCommit == nil)
        #expect(entry.subtitle == nil)
    }

    // MARK: - 最近提交 → RecentCommit

    @Test("recentCommit：信息带正文时，副标题只取**首行**")
    func recentCommitUsesFirstLine() {
        let dto = CommitListItemDTO(
            sha: "abc1234567",
            commit: CommitInfoDTO(
                message: "fix: 面包屑跳级\n\n正文一段，不该出现在 11.5pt 的一行里。",
                authoredAt: authoredAt
            ),
            author: CommitUserDTO(login: "dev-j")
        )

        let recent = RepoFileMapper.recentCommit(dto)

        #expect(recent.summary == "fix: 面包屑跳级")
        #expect(recent.authorLogin == "dev-j")
        #expect(recent.authoredAt == authoredAt)
    }

    @Test("recentCommit：信息为空 ⇒ 副标题回落短 SHA（**不能是空白** —— 空白与「没加载完」同相）")
    func recentCommitFallsBackToShortSHA() {
        let dto = CommitListItemDTO(
            sha: "0123456789abcdef",
            commit: CommitInfoDTO(message: "   ", authoredAt: authoredAt)
        )

        #expect(RepoFileMapper.recentCommit(dto).summary == "0123456")
    }

    // MARK: - 文件正文（决策 #54）

    @Test("fileContent：文本通道 ⇒ .text，size 用**服务端**那个数")
    func mapsTextFile() {
        let dto = RepoFileDTO(
            name: "README.md",
            path: "README.md",
            sha: "s",
            size: 42,
            encoding: "base64",
            content: nil
        )

        let content = RepoFileMapper.fileContent(dto, bytes: Data("# hi\n".utf8))

        #expect(content?.text == "# hi\n")
        #expect(content?.size == 42)
        #expect(content?.blobSHA == "s")
        if case .text = content?.preview {} else {
            Issue.record("README.md ≤1MB 应当是 .text，实际是 \(String(describing: content?.preview))")
        }
    }

    @Test("fileContent：图片 ⇒ .image(字节)")
    func mapsImageFile() {
        let dto = RepoFileDTO(
            name: "logo.png",
            path: "Assets/logo.png",
            sha: "s",
            size: 6,
            encoding: nil,
            content: nil
        )
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])

        let content = RepoFileMapper.fileContent(dto, bytes: bytes)

        guard case .image(let data) = content?.body else {
            Issue.record("png 应当是 .image，实际是 \(String(describing: content?.body))")
            return
        }
        #expect(data == bytes)
        #expect(content?.text == nil, "图片没有「原文可复制」⇒ 那个按钮不该出现")
    }

    @Test("⚠️ fileContent：二进制 ⇒ nil（调用方走「不支持预览 + 网页端」）")
    func unsupportedBinaryReturnsNil() {
        let dto = RepoFileDTO(name: "app.bin", path: "app.bin", sha: "s", size: 10)

        #expect(RepoFileMapper.fileContent(dto, bytes: Data([0x00, 0x01])) == nil)
    }

    @Test("⚠️ fileContent：文本通道但字节不是 UTF-8 ⇒ nil（**不是空串** —— 空串会被读成「文件是空的」）")
    func nonUTF8BytesReturnNil() {
        let dto = RepoFileDTO(
            name: "gbk.md",
            path: "gbk.md",
            sha: "s",
            size: 4,
            encoding: "base64"
        )

        #expect(RepoFileMapper.fileContent(dto, bytes: Data([0xC4, 0xE3, 0xBA, 0xC3])) == nil)
    }

    // MARK: - 提交列表行

    @Test("summary：只留首行；作者为 null 时登录名与头像都为 nil（不做「全名兜底」）")
    func mapsCommitSummary() {
        let dto = CommitListItemDTO(
            sha: "deadbeefcafe",
            commit: CommitInfoDTO(
                message: "feat: 仓库详情\n\n正文",
                authoredAt: authoredAt
            ),
            author: nil
        )

        let summary = RepoCommitMapper.summary(dto)

        #expect(summary.message == "feat: 仓库详情")
        #expect(summary.shortSHA == "deadbee")
        #expect(summary.authorLogin == nil)
        #expect(summary.avatarURL == nil)
        // 作者为 nil ⇒ 整段去掉，只留时间（原型那处会拼出 `undefined 提交于 …`）
        #expect(summary.metaLabel(now: authoredAt).hasPrefix("提交于 "))
    }

    @Test("summary：空信息 ⇒ 标题回落短 SHA（与目录行副标题同一规矩）")
    func summaryFallsBackToShortSHA() {
        let dto = CommitListItemDTO(
            sha: "0123456789",
            commit: CommitInfoDTO(message: "", authoredAt: authoredAt)
        )

        #expect(RepoCommitMapper.summary(dto).message == "0123456")
    }

    // MARK: - 提交详情

    @Test("detail：message 保留**完整**信息（首行/正文由详情页现算）")
    func detailKeepsFullMessage() {
        let dto = CommitDetailDTO(
            sha: "s1",
            commit: CommitInfoDTO(message: "fix: 标题\n\n正文一段。", authoredAt: authoredAt),
            author: CommitUserDTO(login: "dev-j"),
            stats: CommitStatsDTO(additions: 12, deletions: 4, total: 16),
            files: [
                CommitFileDTO(
                    filename: "A.swift",
                    additions: 12,
                    deletions: 4,
                    status: "modified",
                    patch: "@@ -1 +1 @@"
                )
            ]
        )

        let detail = RepoCommitMapper.detail(dto)

        #expect(detail.message == "fix: 标题\n\n正文一段。")
        #expect(detail.headline == "fix: 标题")
        #expect(detail.body == "正文一段。")
        #expect(detail.stats == CommitDetail.Stats(additions: 12, deletions: 4, total: 16))
        // ⚠️ `{N} 个文件` 用 files.count，不是 stats.total（后者是"改了多少行"）
        #expect(detail.statsLabel == "1 个文件 · +12 −4")
    }

    @Test("detail：认不出的 status ⇒ .unknown（不让一个新取值把整页变成解码失败）")
    func detailUnknownStatusFallsBack() {
        let dto = CommitDetailDTO(
            sha: "s1",
            commit: CommitInfoDTO(message: "m", authoredAt: authoredAt),
            files: [CommitFileDTO(filename: "x", additions: 0, deletions: 0, status: "submodule_moved")]
        )

        #expect(RepoCommitMapper.detail(dto).files.first?.status == .unknown)
    }

    @Test("detail：patch 缺席 ⇒ nil（二进制 / diff 太大，两种原因都不在这里分）")
    func detailMissingPatchStaysNil() {
        let dto = CommitDetailDTO(
            sha: "s1",
            commit: CommitInfoDTO(message: "m", authoredAt: authoredAt),
            files: [CommitFileDTO(filename: "logo.png", additions: 0, deletions: 0, status: "added")]
        )

        let change = RepoCommitMapper.detail(dto).files.first
        #expect(change?.patch == nil)
        // 分开判是领域层的事（决策 #54 的判据复用）：图片没有可读的**文本** diff
        #expect(change?.isBinary == true)
    }

    // MARK: - 分支

    @Test("⚠️ branch：protected 原样带过去 —— 丢了它就会给出一个必然 422 的删除入口")
    func mapsBranchKeepingProtected() {
        let protectedBranch = RepoBranchMapper.branch(
            BranchDTO(name: "main", commitSHA: "head", protected: true)
        )
        let featureBranch = RepoBranchMapper.branch(
            BranchDTO(name: "feature/x", commitSHA: "f", protected: false)
        )

        #expect(protectedBranch.isProtected)
        #expect(protectedBranch.canDelete(defaultBranch: "dev") == false)
        #expect(protectedBranch.deleteBlockReason(defaultBranch: "dev") == .protected)

        #expect(featureBranch.canDelete(defaultBranch: "main"))
        #expect(featureBranch.deleteBlockReason(defaultBranch: "main") == nil)
    }

    @Test("comparison：四个 status 逐个映射，认不出的 ⇒ .unknown")
    func mapsComparisonStatus() {
        let cases: [(String?, RepoComparison.Status)] = [
            ("identical", .identical),
            ("ahead", .ahead),
            ("behind", .behind),
            ("diverged", .diverged),
            // 官方将来多一个取值时不能让整页解码失败
            ("squashed", .unknown),
            (nil, .unknown),
        ]

        for (raw, expected) in cases {
            let comparison = RepoBranchMapper.comparison(
                CompareDTO(status: raw, aheadBy: 0, behindBy: 0, totalCommits: 0)
            )
            #expect(comparison.status == expected, "status=\(raw ?? "nil") 应当映射成 \(expected)")
        }
    }

    @Test("⚠️ comparison：未合并判定只看 aheadBy —— 不数 commits 数组（服务端会截断）")
    func comparisonUnmergedJudgeUsesAheadBy() {
        let comparison = RepoBranchMapper.comparison(
            CompareDTO(status: "ahead", aheadBy: 3, behindBy: 0, totalCommits: 3)
        )

        #expect(comparison.hasUnmergedCommits)
        #expect(
            RepoBranchMapper.comparison(
                CompareDTO(status: "identical", aheadBy: 0, behindBy: 0, totalCommits: 0)
            ).hasUnmergedCommits == false
        )
    }

    // MARK: - 三处显示必须用同一套拆分规则

    @Test("⚠️ 同一条提交信息在**三处**显示成同一个标题（首行规则只有一份实现）")
    func firstLineRuleIsShared() {
        let message = "fix: 面包屑跳级\r\n\r\n正文"

        let directoryLine = RepoFileMapper.recentCommit(
            CommitListItemDTO(
                sha: "s1",
                commit: CommitInfoDTO(message: message, authoredAt: authoredAt)
            )
        ).summary

        let listRow = RepoCommitMapper.summary(
            CommitListItemDTO(
                sha: "s1",
                commit: CommitInfoDTO(message: message, authoredAt: authoredAt)
            )
        ).message

        let detail = RepoCommitMapper.detail(
            CommitDetailDTO(
                sha: "s1",
                commit: CommitInfoDTO(message: message, authoredAt: authoredAt)
            )
        )

        // CRLF 检出的仓库很常见：`\r` 留在标题末尾会表现为看不见的空位
        #expect(directoryLine == "fix: 面包屑跳级")
        #expect(listRow == directoryLine)
        #expect(detail.headline == directoryLine)
        #expect(detail.body == "正文")
    }
}
