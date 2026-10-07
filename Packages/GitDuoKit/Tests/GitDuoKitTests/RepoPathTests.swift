import Foundation
import Testing

@testable import GitDuoKit

/// 仓库内路径的拼接与校验（TECH_SPEC §9.5 末条）。
///
/// ## 为什么这一套必须存在
///
/// 面包屑的每一级都是**用户可点的**，依次拼出 `a/b/c`。三种拼错的方式都不会报错：
/// 空段拼出 `a//c`、段里含 `/` 让一次点击跨两级、`..` 让"往下走"变成"往上走"。
/// 它们全都表现为"界面正常、行为不对" —— 只有单测能拦住。
@Suite("仓库路径 · 拼接与校验")
struct RepoPathTests {

    // MARK: - 拼接

    @Test("逐级拼接与 `raw` 的形态")
    func buildsPaths() {
        guard let docs = RepoPath.root.appending("docs"),
              let guide = docs.appending("guide.md") else {
            Issue.record("合法的两段拼接不该失败")
            return
        }

        #expect(docs.raw == "docs")
        #expect(guide.raw == "docs/guide.md")
        #expect(guide.components == ["docs", "guide.md"])
        #expect(guide.lastComponent == "guide.md")
    }

    @Test("根路径：`components` 为空、`lastComponent` 为 `nil`")
    func rootIsEmpty() {
        #expect(RepoPath.root.isRoot)
        #expect(RepoPath.root.components.isEmpty)
        #expect(RepoPath.root.lastComponent == nil)
        #expect(RepoPath.root.raw.isEmpty)
    }

    @Test("⚠️ 空段 / 含 `/` 的段 / `.` / `..` 一律拒绝（返回 `nil`，不是拼出一个怪路径）")
    func rejectsBadComponents() {
        #expect(RepoPath.root.appending("") == nil)
        #expect(RepoPath.root.appending("a/b") == nil)
        #expect(RepoPath.root.appending(".") == nil)
        #expect(RepoPath.root.appending("..") == nil)
        // 顶层那个组合不成立：`.gitignore` 是**合法**条目名（`.` 开头不等于 `.`）。
        #expect(RepoPath.root.appending(".gitignore") != nil)
        #expect(RepoPath.root.appending(".github") != nil)
    }

    @Test("回到上一级；根再往上还是根（不会变成 `nil` 或空串之外的怪东西）")
    func deletingLastComponent() {
        let guide = RepoPath(path: "docs/api/guide.md")

        #expect(guide.deletingLastComponent().raw == "docs/api")
        #expect(guide.deletingLastComponent().deletingLastComponent().raw == "docs")
        #expect(RepoPath.root.deletingLastComponent().isRoot)
        #expect(RepoPath(path: "single").deletingLastComponent().isRoot)
    }

    // MARK: - 解析既有路径

    @Test("从服务端给的路径解析：前导 `/` 被吃掉、空串即根")
    func parsesServerPaths() {
        #expect(RepoPath(path: "/docs/guide.md").raw == "docs/guide.md")
        #expect(RepoPath(path: "").isRoot)
        #expect(RepoPath(path: "/").isRoot)
        #expect(RepoPath(path: "docs/guide.md").components == ["docs", "guide.md"])
    }

    @Test("⚠️ 解析既有路径**不校验**（服务端给什么就是什么，异常条目照原样显示）")
    func parsingDoesNotValidate() {
        // 一个"含 .. 的条目名"在真实仓库里不该出现，但如果服务端真的给了，
        // 渲染它是**如实显示**；拒绝解析会让那一行整条不见（更糟）。
        #expect(RepoPath(path: "weird/../name").components == ["weird", "..", "name"])
    }

    @Test("`appending` 的结果能继续拼接（链式不丢前缀）")
    func chainingKeepsPrefix() {
        guard let a = RepoPath.root.appending("a"),
              let b = a.appending("b"),
              let c = b.appending("c") else {
            Issue.record("链式拼接不该失败")
            return
        }

        #expect(c.raw == "a/b/c")
    }
}
