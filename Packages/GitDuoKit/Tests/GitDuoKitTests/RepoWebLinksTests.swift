import Foundation
import Testing

@testable import GitDuoKit

/// 「跳网页端」三处出口的地址拼装（§4.5 / §4.4 / §4.7）。
///
/// 这一组看起来是"拼字符串，没什么好测的" —— 恰恰相反：
/// 拼错的**唯一表现**是用户在浏览器里看到 GitHub 的 404 页，
/// 而他会据此判定"这个文件被删了 / 这个提交不见了"。
/// 少写一段引用名（`blob/{ref}/{path}` 里的 `ref`）在 `URL(string:)` 那一步
/// 既不失败、也不报警，只是落空。所以形状必须被钉住。
@Suite("网页端出口 · 地址形状")
struct RepoWebLinksTests {

    // MARK: - blob

    @Test("文件地址：`{仓库}/blob/{引用名}/{路径}` —— 三段都在")
    func blobShape() throws {
        let url = try #require(
            RepoWebLinks.blob(
                fullName: "octocat/hello-world",
                ref: "main",
                path: RepoPath(path: "docs/guide.md")
            )
        )

        #expect(url.absoluteString == "https://github.com/octocat/hello-world/blob/main/docs/guide.md")
    }

    @Test("⚠️ 用 `blob` 而不是 `tree` —— `blob` 指目录会自动跳，`tree` 指文件不会")
    func blobNotTree() throws {
        let url = try #require(
            RepoWebLinks.blob(fullName: "octocat/hello-world", ref: "main", path: RepoPath(path: "Sources"))
        )

        #expect(url.absoluteString.contains("/blob/"))
        #expect(!url.absoluteString.contains("/tree/"))
    }

    @Test("⚠️ 引用名**不能省** —— 省掉之后那串在浏览器里能用，是因为网页端替我们补了一次跳转")
    func blobKeepsRef() throws {
        let url = try #require(
            RepoWebLinks.blob(fullName: "octocat/hello-world", ref: "release/2.0", path: RepoPath(path: "a.md"))
        )
        let withoutRef = "https://github.com/octocat/hello-world/blob/a.md"

        #expect(url.absoluteString != withoutRef)
        #expect(url.absoluteString == "https://github.com/octocat/hello-world/blob/release/2.0/a.md")
    }

    @Test("拿不到分支时用字面 `HEAD`（GitHub 认它就是默认分支）")
    func blobAcceptsHead() throws {
        let url = try #require(
            RepoWebLinks.blob(fullName: "octocat/hello-world", ref: "HEAD", path: RepoPath(path: "README.md"))
        )

        #expect(url.absoluteString == "https://github.com/octocat/hello-world/blob/HEAD/README.md")
    }

    @Test("仓库全名或路径为空 ⇒ `nil`（宁可不出这个按钮，也不要一个必然 404 的地址）")
    func blobRejectsEmptyParts() {
        #expect(RepoWebLinks.blob(fullName: "", ref: "main", path: RepoPath(path: "a.md")) == nil)
        #expect(RepoWebLinks.blob(fullName: "octocat/hello-world", ref: "main", path: .root) == nil)
    }

    // MARK: - commit

    @Test("提交地址：`{仓库}/commit/{sha}`")
    func commitShape() throws {
        let url = try #require(
            RepoWebLinks.commit(fullName: "octocat/hello-world", sha: "0123456789abcdef")
        )

        #expect(url.absoluteString == "https://github.com/octocat/hello-world/commit/0123456789abcdef")
    }

    @Test("⚠️ 它**不是** Revert 的直达地址 —— GitHub 的 revert 只是提交页上的一个按钮，没有直达 URL")
    func commitIsNotRevertDeepLink() throws {
        let url = try #require(
            RepoWebLinks.commit(fullName: "octocat/hello-world", sha: "abc123")
        )

        #expect(!url.absoluteString.contains("revert"))
        #expect(url.pathComponents.suffix(2) == ["commit", "abc123"])
    }

    @Test("仓库全名或 sha 为空 ⇒ `nil`")
    func commitRejectsEmptyParts() {
        #expect(RepoWebLinks.commit(fullName: "", sha: "abc123") == nil)
        #expect(RepoWebLinks.commit(fullName: "octocat/hello-world", sha: "") == nil)
    }

    // MARK: - compare（切片 8：「PR 未创建」的出口）

    @Test("⚠️ 比较页地址带 `?expand=1`（少了它用户到了比较页还得自己找建 PR 的按钮）")
    func compareShape() throws {
        let url = try #require(
            RepoWebLinks.compare(fullName: "octocat/hello-world", base: "main", head: "gitduo/x")
        )

        #expect(url.absoluteString
            == "https://github.com/octocat/hello-world/compare/main...gitduo/x?expand=1")
    }

    @Test("⚠️ 分隔符是**三个点** —— 两个点是「比较两个提交」那个完全不同的页面，不报错也不明显")
    func compareUsesTripleDot() throws {
        let url = try #require(
            RepoWebLinks.compare(fullName: "octocat/hello-world", base: "main", head: "feature")
        )

        #expect(url.absoluteString.contains("main...feature"))
        #expect(!url.absoluteString.contains("main..feature?"))
    }

    @Test("三段任一为空 ⇒ `nil`（宁可不出这个按钮，也不要一个落空的地址）")
    func compareRejectsEmptyParts() {
        #expect(RepoWebLinks.compare(fullName: "", base: "main", head: "x") == nil)
        #expect(RepoWebLinks.compare(fullName: "octocat/hello-world", base: "", head: "x") == nil)
        #expect(RepoWebLinks.compare(fullName: "octocat/hello-world", base: "main", head: "") == nil)
    }
}
