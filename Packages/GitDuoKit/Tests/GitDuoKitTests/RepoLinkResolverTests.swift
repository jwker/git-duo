import Foundation
import Testing

@testable import GitDuoKit

/// `RepoLinkResolver` —— README 里一个链接该去哪儿。
///
/// ## 这批用例在守什么
///
/// `[中文](README_zh.md)` 点下去没反应，是本条链路上**唯一能被用户看见**的症状；
/// 而它背后的规则有九条互相独立的判定（锚点 / 协议 / 站点根 / 相对路径 / `..` /
/// 同仓库 blob / 同仓库 tree / 别的仓库 / 别的 host），每一条写错了都**不会报错** ——
/// 只会把人送到另一个地方，或者什么都不做。
///
/// ## ⚠️ 地址一律先在断言**外面**取好
///
/// `#expect` 的表达式被包在一个**不是 `throws` 的自动闭包**里（Swift Testing 的规定），
/// 所以 `try #require(…)` / `try url(…)` 直接写在 `#expect(…)` 里面编译不过。
/// 这不是风格问题，是编译错误 —— 见 `Makefile` 那条"`make test-<包>` 只编本包"的提醒。
@Suite("RepoLinkResolver")
struct RepoLinkResolverTests {

    private let repo = "anywhere-labs/dsh-desktop"

    /// 从 href 造一个 `URL`（`MarkdownInline` 也只做这一步）。
    ///
    /// ⚠️ 用 `#require` 而不是 `!`：地址造不出来时**这一条应该失败**，
    /// 而不是让整个进程崩掉（崩掉之后后面所有用例都不报结果）。
    private func url(_ href: String) throws -> URL {
        try #require(URL(string: href), "造不出 URL：\(href)")
    }

    // MARK: - 相对路径（本次目视报的就是这一档）

    @Test("根目录下的相对文件链接 ⇒ 仓库内文件")
    func relativeFileFromRoot() throws {
        let target = RepoLinkResolver.target(for: try url("README_zh.md"), fullName: repo)
        #expect(target == .file(RepoPath(path: "README_zh.md")))
    }

    @Test("带子目录的相对链接 ⇒ 拼成完整仓库内路径")
    func relativeFileWithSubdirectory() throws {
        let target = RepoLinkResolver.target(for: try url("docs/user-guide.md"), fullName: repo)
        #expect(target == .file(RepoPath(path: "docs/user-guide.md")))
    }

    @Test("显式 `./` 前缀不参与路径")
    func explicitCurrentDirectory() throws {
        let target = RepoLinkResolver.target(for: try url("./docs/faq.md"), fullName: repo)
        #expect(target == .file(RepoPath(path: "docs/faq.md")))
    }

    @Test("文档在子目录时，相对地址以**文档所在目录**为基准")
    func relativeToBaseDirectory() throws {
        let base = RepoPath(path: "docs")

        let sibling = RepoLinkResolver.target(
            for: try url("faq.md"), fullName: repo, baseDirectory: base
        )
        #expect(sibling == .file(RepoPath(path: "docs/faq.md")))

        // `..` 退回上一级（拼出的是仓库内的另一条路径，不是"上一层的 faq.md"）。
        let parent = RepoLinkResolver.target(
            for: try url("../README.md"), fullName: repo, baseDirectory: base
        )
        #expect(parent == .file(RepoPath(path: "README.md")))
    }

    @Test("`..` 退到仓库根之上 ⇒ 解析不出来（不瞎跳）")
    func escapingRepositoryRoot() throws {
        let shallow = RepoLinkResolver.target(for: try url("../outside.md"), fullName: repo)
        #expect(shallow == .unresolved)

        let deeper = RepoLinkResolver.target(
            for: try url("../../outside.md"),
            fullName: repo,
            baseDirectory: RepoPath(path: "docs")
        )
        #expect(deeper == .unresolved)
    }

    @Test("结尾带 `/` 的相对地址是目录，不是文件")
    func trailingSlashIsDirectory() throws {
        let target = RepoLinkResolver.target(for: try url("docs/"), fullName: repo)
        #expect(target == .directory(RepoPath(path: "docs")))
    }

    @Test("`?query` 与 `#fragment` 不参与路径解析")
    func queryAndFragmentAreStripped() throws {
        let withFragment = RepoLinkResolver.target(for: try url("docs/faq.md#安装"), fullName: repo)
        #expect(withFragment == .file(RepoPath(path: "docs/faq.md")))

        let withQuery = RepoLinkResolver.target(for: try url("docs/faq.md?v=2"), fullName: repo)
        #expect(withQuery == .file(RepoPath(path: "docs/faq.md")))
    }

    @Test("百分号转义要还原成真实路径")
    func percentDecoding() throws {
        let target = RepoLinkResolver.target(for: try url("docs/%E7%94%A8%E6%88%B7.md"), fullName: repo)
        #expect(target == .file(RepoPath(path: "docs/用户.md")))
    }

    // MARK: - 锚点

    @Test("纯锚点是 `.anchor`，不是 `.unresolved`")
    func anchors() throws {
        // 两者在界面上的表现可能一样（都跳不了），但含义完全不同：
        // 一个是"地址没问题、这一版不做井内跳转"，一个是"这个地址看不懂"。
        let named = RepoLinkResolver.target(for: try url("#run"), fullName: repo)
        let bare = RepoLinkResolver.target(for: try url("#"), fullName: repo)
        let onlyQuery = RepoLinkResolver.target(for: try url("?a=1"), fullName: repo)

        #expect(named == .anchor)
        #expect(bare == .anchor)
        #expect(onlyQuery == .anchor)
    }

    // MARK: - 外部地址

    @Test("别的 host ⇒ 交给系统")
    func otherHost() throws {
        let href = "https://dshdesktop.cn/download"
        let external = try url(href)
        #expect(RepoLinkResolver.target(for: external, fullName: repo) == .external(external))
    }

    @Test("非 http(s) 协议交给系统（`mailto:` 等）")
    func mailto() throws {
        let href = "mailto:t4wefan@qq.com"
        let external = try url(href)
        #expect(RepoLinkResolver.target(for: external, fullName: repo) == .external(external))
    }

    @Test("**别的仓库**的 blob 地址不进 App（收进来会以当前仓库身份取数 ⇒ 404）")
    func otherRepositoryBlob() throws {
        let href = "https://github.com/deepseek-ai/deepseek-harness/blob/main/README.md"
        let external = try url(href)
        #expect(RepoLinkResolver.target(for: external, fullName: repo) == .external(external))
    }

    @Test("本仓库的非 blob / tree 页面（issues / releases）交给系统")
    func sameRepositoryNonGitPaths() throws {
        let href = "https://github.com/\(repo)/releases/latest"
        let external = try url(href)
        #expect(RepoLinkResolver.target(for: external, fullName: repo) == .external(external))
    }

    // MARK: - 本仓库的 github.com 地址

    @Test("本仓库的 blob 地址 ⇒ 仓库内文件（顺带把 percent 转义还原）")
    func sameRepositoryBlob() throws {
        let target = RepoLinkResolver.target(
            for: try url("https://github.com/\(repo)/blob/master/docs/%E7%94%A8%E6%88%B7.md"),
            fullName: repo
        )
        #expect(target == .file(RepoPath(path: "docs/用户.md")))
    }

    @Test("本仓库的 tree 地址 ⇒ 仓库内目录")
    func sameRepositoryTree() throws {
        let target = RepoLinkResolver.target(
            for: try url("https://github.com/\(repo)/tree/master/dsh-plugin-desktop"),
            fullName: repo
        )
        #expect(target == .directory(RepoPath(path: "dsh-plugin-desktop")))
    }

    @Test("仓库全名大小写不影响判定（GitHub 本身不区分）")
    func repositoryNameIsCaseInsensitive() throws {
        let target = RepoLinkResolver.target(
            for: try url("https://github.com/ANYWHERE-LABS/DSH-Desktop/blob/master/a.md"),
            fullName: repo
        )
        #expect(target == .file(RepoPath(path: "a.md")))
    }

    @Test("以 `/` 开头的是**站点根**，不是仓库根")
    func leadingSlashMeansSiteRoot() throws {
        // 按文件系统直觉会解析成仓库内的 `anywhere-labs/...` —— 那是错的。
        let sameRepo = RepoLinkResolver.target(
            for: try url("/\(repo)/blob/master/a.md"), fullName: repo
        )
        #expect(sameRepo == .file(RepoPath(path: "a.md")))

        // 指向另一个仓库时照旧交给系统。
        let otherURL = try url("https://github.com/other/repo/blob/main/x.md")
        let other = RepoLinkResolver.target(for: try url("/other/repo/blob/main/x.md"), fullName: repo)
        #expect(other == .external(otherURL))
    }

    @Test("协议相对地址按 https 补全")
    func protocolRelative() throws {
        let target = RepoLinkResolver.target(
            for: try url("//github.com/\(repo)/blob/master/a.md"), fullName: repo
        )
        #expect(target == .file(RepoPath(path: "a.md")))
    }
}
