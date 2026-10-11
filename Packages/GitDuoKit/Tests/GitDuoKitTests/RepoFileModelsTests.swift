import Foundation
import Testing

@testable import GitDuoKit

/// 文件树条目 · 提交列表行 · 提交详情 · 分区枚举（PRD §3.2 / §3.7 / §4.4 / §4.7）。
@Suite("仓库文件模型 · 条目 / 提交 / 分区")
struct RepoFileModelsTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func ago(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(-seconds) }
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - TreeEntry

    private func entry(
        _ name: String,
        path: String? = nil,
        kind: TreeEntry.Kind = .file,
        size: Int = 10
    ) -> TreeEntry {
        TreeEntry(
            name: name,
            path: RepoPath(path: path ?? name),
            kind: kind,
            size: size,
            sha: "sha"
        )
    }

    @Test("⚠️ 目录读 `size` 恒为 0；可进入性由 `Kind` 决定（`unsupported` 不可进入）")
    func kindDecidesNavigability() {
        #expect(TreeEntry.Kind.directory.isNavigable)
        #expect(TreeEntry.Kind.file.isNavigable)
        // symlink / submodule 归这一档：当普通文件打开会显示出一行链接目标，
        // 而当目录打开只会 404。
        #expect(TreeEntry.Kind.unsupported.isNavigable == false)
    }

    @Test("`id` 用**完整路径**：只用文件名会让子目录里的同名文件互相顶掉")
    func idUsesFullPath() {
        let root = entry("README.md", path: "README.md")
        let nested = entry("README.md", path: "docs/README.md")

        #expect(root.id != nested.id)
        #expect(root.id == "README.md")
        #expect(nested.id == "docs/README.md")
    }

    // MARK: - CommitSummary

    private func summary(_ message: String, author: String? = "dev", at date: Date? = nil) -> CommitSummary {
        CommitSummary(
            sha: "0123456789abcdef",
            message: message,
            authorLogin: author,
            authoredAt: date ?? ago(7200)
        )
    }

    @Test("提交行的第二行是 `{作者} 提交于 {时间}`（原型逐字句式）")
    func commitMetaLabel() {
        let label = summary("feat: 首页").metaLabel(now: now)

        #expect(label.hasPrefix("dev 提交于 "))
        #expect(label.contains("小时前"))
    }

    @Test("⚠️ 作者为 `nil` 时**整段去掉**，不会拼出 `undefined 提交于 …`")
    func commitMetaLabelWithoutAuthor() {
        let label = summary("feat: 首页", author: nil).metaLabel(now: now)

        #expect(!label.contains("undefined"))
        #expect(label.hasPrefix("提交于 "))
    }

    @Test("短 SHA 取 7 位（与 `git log --oneline`、GitHub 网页端一致）")
    func shortSHA() {
        #expect(summary("x").shortSHA == "0123456")
        #expect(summary("x").shortSHA.count == CommitSummary.shortSHALength)
    }

    // MARK: - CommitDetail

    private func detail(
        message: String = "feat: 首页",
        author: String? = "dev",
        stats: CommitDetail.Stats? = CommitDetail.Stats(additions: 12, deletions: 4, total: 16),
        files: [FileChange] = [
            FileChange(filename: "GitDuo/App.swift", additions: 12, deletions: 4, status: .modified, patch: "@@"),
        ]
    ) -> CommitDetail {
        CommitDetail(
            sha: "0123456789abcdef",
            message: message,
            authorLogin: author,
            authoredAt: ago(7200),
            stats: stats,
            files: files
        )
    }

    @Test("头部第三段：`{N} 个文件 · +{增} −{删}`（原型逐字：`1 个文件 · +12 −4`）")
    func statsLabelMatchesPrototype() {
        #expect(detail().statsLabel == "1 个文件 · +12 −4")
    }

    @Test("⚠️ `N` 取 `files.count` 而**不是** `stats.total` —— 后者是「改了多少行」，不是「几个文件」")
    func fileCountComesFromFilesNotStats() {
        let many = detail(
            stats: CommitDetail.Stats(additions: 500, deletions: 300, total: 800),
            files: (1...3).map {
                FileChange(filename: "f\($0).swift", additions: 1, deletions: 0, status: .modified, patch: "@@")
            }
        )

        #expect(many.statsLabel.hasPrefix("3 个文件"))
        // 读错字段不会报错 —— 只会显示成 `800 个文件`。
        #expect(!many.statsLabel.contains("800 个文件"))
    }

    @Test("`stats` 缺席时只留 `{N} 个文件`（不编一个 `+0 −0`）")
    func statsLabelWithoutStats() {
        #expect(detail(stats: nil).statsLabel == "1 个文件")
    }

    @Test("`headline` 是首行、`body` 是其余；没有正文时 `body` 为 `nil`（那一块整个不渲染）")
    func headlineAndBody() {
        #expect(detail(message: "fix: 标题").headline == "fix: 标题")
        #expect(detail(message: "fix: 标题").body == nil)

        let withBody = detail(message: "fix: 标题\n\n正文第一段\n正文第二段")
        #expect(withBody.headline == "fix: 标题")
        #expect(withBody.body == "正文第一段\n正文第二段")

        // 只有换行的"空正文"不算正文。
        #expect(detail(message: "fix: 标题\n\n\n").body == nil)
    }

    @Test("空提交信息时标题回落到完整 SHA（不留下一个空白标题）")
    func emptyMessageHeadlineFallsBackToSHA() {
        #expect(detail(message: "").headline == "0123456789abcdef")
    }

    // MARK: - FileChange

    @Test("⚠️ `patch == nil` 的两种原因要分开：二进制 vs diff 过大（用户的下一步不同）")
    func missingPatchHasTwoReasons() {
        let binary = FileChange(filename: "logo.png", additions: 0, deletions: 0, status: .modified, patch: nil)
        let oversized = FileChange(
            filename: "huge.swift", additions: 900, deletions: 200, status: .modified, patch: nil
        )

        #expect(binary.isBinary)
        #expect(oversized.isBinary == false)
        #expect(CommitCopy.binaryDiffNotice != CommitCopy.oversizedDiffNotice)
    }

    @Test("有 `patch` 时当然不是二进制（哪怕文件名看着像二进制）")
    func patchPresentIsNeverBinary() {
        let weird = FileChange(filename: "x.bin", additions: 1, deletions: 0, status: .modified, patch: "@@ -1 +1 @@")
        #expect(weird.isBinary == false)
    }

    @Test("`status` 认不出来的取值兜底成 `.unknown`（字符串枚举，多一个取值不该让整页解码失败）")
    func unknownStatusFallsBack() {
        #expect(FileChange.Status(rawStatus: "added") == .added)
        #expect(FileChange.Status(rawStatus: "removed") == .removed)
        #expect(FileChange.Status(rawStatus: "something-new") == .unknown)
        #expect(FileChange.Status(rawStatus: nil) == .unknown)
    }

    // MARK: - RepoSection

    @Test("四个分区的**顺序就是声明顺序**（分段条直接遍历 `allCases`，不要另写数组）")
    func sectionOrderAndTitles() {
        #expect(RepoSection.allCases == [.code, .issues, .pullRequests, .commits])
        #expect(RepoSection.allCases.map(\.title) == ["代码", "Issues", "Pull Requests", "Commits"])
        #expect(RepoSection.initial == .code)
    }
}
