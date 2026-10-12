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

    /// ⚠️ `raw` 与 `displayName` 是**两样东西**，谁也不能顶替谁。
    ///
    /// 2026-10-12 加的那两个复制通道各取一个：`FileViewModel.copyPath()` 取 `raw`、
    /// `copyFileName()` 取 `displayName`。两者要是一样，那颗「⋯」菜单的第二项
    /// 就成了第一项的重复 —— 而这件事在**界面上看不出来**（两项都叫"复制"）。
    @Test("⚠️ `raw` 是整条路径、`displayName` 只有最后一段 —— 不可互相顶替")
    func rawAndDisplayNameAreDifferentThings() {
        let file = RepoPath(path: "Packages/GitDuoKit/Sources/RepoPath.swift")

        #expect(file.raw == "Packages/GitDuoKit/Sources/RepoPath.swift")
        #expect(file.displayName == "RepoPath.swift")
        #expect(file.raw != file.displayName)

        // ⚠️ 单段的这一档两者恰好相等 —— 所以那条断言写在**有目录**的那一档上。
        //    拿 `README.md` 当例子是钉不出任何东西的。
        #expect(RepoPath(path: "README.md").raw == "README.md")
        #expect(RepoPath(path: "README.md").displayName == "README.md")
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

    // MARK: - 上传出口的落点（§5.8，2026-10-12）

    /// 用户报回的原话：「添加或者上传文件的时候都是直接上传到了根目录，
    /// 而不是上传到我打开的对应目录下」⇒ 这几条钉的就是"落点在当前目录"。
    @Test("⚠️ 上传落点是**当前目录 + 文件名**（不是在仓库根）")
    func uploadLandsInCurrentDirectory() {
        let cases: [(RepoPath, String, String)] = [
            (RepoPath.root, "IMG_1234.jpg", "IMG_1234.jpg"),
            (RepoPath(path: "docs"), "IMG_1234.jpg", "docs/IMG_1234.jpg"),
            (RepoPath(path: "docs/api"), "photo-20261012-083000.jpg", "docs/api/photo-20261012-083000.jpg"),
            // trim 仍然生效（`normalizeUserInput` 那一份判据，与新建 / 重命名同源）。
            (RepoPath(path: "docs"), " IMG_1234.jpg ", "docs/IMG_1234.jpg"),
            // `.` 开头的隐藏文件是**合法条目**（同 `isValidComponent` 那条"不禁 `.` 开头"）。
            (RepoPath(path: "docs"), ".gitignore", "docs/.gitignore"),
        ]

        for (directory, fileName, expected) in cases {
            guard case let .acceptable(path) = RepoPath.resolveUpload(
                directory: directory, fileName: fileName
            ) else {
                Issue.record("\(directory.raw) + \(fileName) 不该被拒")
                continue
            }
            #expect(path.raw == expected)
        }
    }

    @Test("⚠️ 上传那一格的 `fileName` **必须是一段**：`a/b.jpg` 不是文件名，宁可失败")
    func uploadRejectsMultiLevelFileName() {
        let docs = RepoPath(path: "docs")

        // 正常路到不了这几档（文件 App 给的是 `lastPathComponent`、相册那条由
        // `UploadFileName` 生成）—— 留着是因为"上游一定给对"是一句**假设**，
        // 而它失效的方式（悄悄多建一层目录）正是那种看不出来的错。
        #expect(RepoPath.resolveUpload(directory: docs, fileName: "") == .rejected(.empty))
        #expect(RepoPath.resolveUpload(directory: docs, fileName: "  ") == .rejected(.empty))
        #expect(RepoPath.resolveUpload(directory: docs, fileName: ".") == .rejected(.invalidComponent(".")))
        #expect(RepoPath.resolveUpload(directory: docs, fileName: "..") == .rejected(.invalidComponent("..")))
        // 多段报的是**整串**（问题出在"它不是一个名字"，不是其中哪一段）。
        #expect(
            RepoPath.resolveUpload(directory: docs, fileName: "a/b.jpg")
                == .rejected(.invalidComponent("a/b.jpg"))
        )
        // 根目录下也一样拒（这条与"目录是哪一层"无关）。
        #expect(
            RepoPath.resolveUpload(directory: .root, fileName: "a/b.jpg")
                == .rejected(.invalidComponent("a/b.jpg"))
        )
    }
}
