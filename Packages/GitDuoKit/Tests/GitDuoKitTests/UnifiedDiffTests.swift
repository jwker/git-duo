import Foundation
import Testing

@testable import GitDuoKit

/// unified diff 解析（TECH_SPEC §11.2）。
///
/// §11.2 列出的四个边界（无换行结尾标记 / 多文件分割 / 二进制 / `\r\n`）逐条覆盖 ——
/// 它们错了不报错，只是**少显示一行**或者**行号整体偏 1**。
@Suite("unified diff 解析 · 行号 / 边界 / 多文件")
struct UnifiedDiffTests {

    // MARK: - 基本

    @Test("表头解析：`@@ -40,7 +40,9 @@` ⇒ 四个数")
    func hunkHeader() {
        let parsed = UnifiedDiffParser.parseHunkHeader("@@ -40,7 +40,9 @@")
        #expect(parsed.oldStart == 40)
        #expect(parsed.oldCount == 7)
        #expect(parsed.newStart == 40)
        #expect(parsed.newCount == 9)
        #expect(parsed.section == nil)
    }

    @Test("表头可以省略数量（`-1,` 与 `-1 +1` 两种写法都要认）")
    func hunkHeaderWithoutCounts() {
        let parsed = UnifiedDiffParser.parseHunkHeader("@@ -1 +1 @@")
        #expect(parsed.oldStart == 1)
        #expect(parsed.oldCount == 1)
        #expect(parsed.newStart == 1)
        #expect(parsed.newCount == 1)
    }

    @Test("表头后面的函数上下文被单独取出来（原型 `.hunk` 整行照印，但上下文不该丢）")
    func hunkSection() {
        let parsed = UnifiedDiffParser.parseHunkHeader("@@ -12,7 +12,9 @@ func body() -> some View {")
        #expect(parsed.section == "func body() -> some View {")
    }

    @Test("⚠️ 畸形表头**不崩**、给 0（「服务端给了没见过的形状」不该让整页打不开）")
    func malformedHeaderDoesNotCrash() {
        for header in ["@@", "@@ @@", "@@ junk @@", "@@ - + @@"] {
            let parsed = UnifiedDiffParser.parseHunkHeader(header)
            #expect(parsed.oldCount >= 0)
            #expect(parsed.newCount >= 0)
        }
    }

    // MARK: - 行号（最容易错的一处）

    @Test("⚠️ 行号从**表头给的起点**开始算：上下文两边都自增、删除只动旧、新增只动新")
    func lineNumbersFollowTheHunk() {
        let patch = """
        @@ -40,7 +40,9 @@
                 PaginatedList(items: store.repos) {
        -             Button { selection = repo } label: {
        +             NavigationLink(value: repo) {
        """

        let hunks = UnifiedDiffParser.hunks(from: patch)
        #expect(hunks.count == 1)

        let lines = hunks[0].lines
        #expect(lines.count == 3)

        // 上下文：40/40
        #expect(lines[0].kind == .context)
        #expect(lines[0].oldNumber == 40)
        #expect(lines[0].newNumber == 40)
        // 删除：旧 41、新（不存在）
        #expect(lines[1].kind == .deletion)
        #expect(lines[1].oldNumber == 41)
        #expect(lines[1].newNumber == nil)
        // 新增：新 41、旧（不存在）
        #expect(lines[2].kind == .addition)
        #expect(lines[2].oldNumber == nil)
        #expect(lines[2].newNumber == 41)
    }

    @Test("⚠️ 行文字去掉行首标记（否则会显示成 `+ + 内容` —— 符号画两遍）")
    func lineTextStripsTheMarker() {
        let patch = """
        @@ -1,1 +1,1 @@
        -old
        +new
        """

        let lines = UnifiedDiffParser.hunks(from: patch)[0].lines
        #expect(lines[0].text == "old")
        #expect(lines[1].text == "new")
        #expect(!lines[0].text.hasPrefix("-"))
        #expect(!lines[1].text.hasPrefix("+"))
    }

    @Test("新增文件（`@@ -0,0 +1,28 @@`）：旧侧**一行都没有** ⇒ 旧行号整段为 `nil`")
    func brandNewFileHasNoOldNumbers() {
        let patch = """
        @@ -0,0 +1,2 @@
        +第一行
        +第二行
        """

        let lines = UnifiedDiffParser.hunks(from: patch)[0].lines
        #expect(lines.allSatisfy { $0.oldNumber == nil })
        #expect(lines[0].newNumber == 1)
        #expect(lines[1].newNumber == 2)
    }

    // MARK: - 边界

    @Test("⚠️ `\\ No newline at end of file` **不消耗行号**（算了它后面的行会整体偏 1）")
    func noNewlineMarkerDoesNotConsumeALineNumber() {
        let patch = """
        @@ -1,3 +1,3 @@
         a
        -b
        +c
        \\ No newline at end of file
         d
        """

        let lines = UnifiedDiffParser.hunks(from: patch)[0].lines

        // 顺序是：context(a) → deletion(b) → addition(c) → noNewline → context(d)。
        #expect(lines.count == 5)
        #expect(lines[3].kind == .noNewline)
        #expect(lines[3].oldNumber == nil)
        #expect(lines[3].newNumber == nil)
        // 关键：它后面那一行（上下文 `d`）的旧行号是 3，不是 4。
        #expect(lines[4].kind == .context)
        #expect(lines[4].oldNumber == 3)
        #expect(lines[4].newNumber == 3)
    }

    @Test("⚠️ `\\r\\n` 归一（Windows 检出的文件很常见；留着 `\\r` 会在行尾显示一个方块）")
    func normalisesCarriageReturns() {
        let patch = "@@ -1,1 +1,1 @@\r\n-old\r\n+new\r\n"

        let lines = UnifiedDiffParser.hunks(from: patch)[0].lines
        #expect(lines[0].text == "old")
        #expect(lines[1].text == "new")
        #expect(!lines[0].text.contains("\r"))
    }

    @Test("二进制文件：`Binary files … differ` ⇒ 没有 hunk，但有明确的二进制标记")
    func binaryFile() {
        let diff = """
        diff --git a/logo.png b/logo.png
        index 111..222 100644
        Binary files a/logo.png and b/logo.png differ
        """

        let files = UnifiedDiffParser.files(from: diff)
        #expect(files.count == 1)
        #expect(files[0].isBinary)
        #expect(files[0].hunks.isEmpty)
        #expect(files[0].displayPath == "logo.png")
    }

    @Test("⚠️ 多文件分割（`diff --git`）：三段各归各家，不串行")
    func multipleFiles() {
        let diff = """
        diff --git a/a.swift b/a.swift
        --- a/a.swift
        +++ b/a.swift
        @@ -1,1 +1,1 @@
        -old
        +new
        diff --git a/b.swift b/b.swift
        --- a/b.swift
        +++ b/b.swift
        @@ -5,1 +5,1 @@
        -x
        +y
        """

        let files = UnifiedDiffParser.files(from: diff)
        #expect(files.count == 2)
        #expect(files[0].displayPath == "a.swift")
        #expect(files[1].displayPath == "b.swift")
        // 第二个文件的 hunk 起点是 5，不是接着第一个文件往下数。
        #expect(files[1].hunks[0].lines[0].oldNumber == 5)
    }

    @Test("路径前缀 `a/` / `b/` 被剥掉；`/dev/null` 表示「这一侧不存在」")
    func pathPrefixes() {
        #expect(UnifiedDiffParser.stripPrefix("a/docs/x.md") == "docs/x.md")
        #expect(UnifiedDiffParser.stripPrefix("b/docs/x.md") == "docs/x.md")
        #expect(UnifiedDiffParser.stripPrefix("/dev/null") == nil)
        // 没有前缀的（某些工具的写法）原样保留。
        #expect(UnifiedDiffParser.stripPrefix("docs/x.md") == "docs/x.md")

        let newFile = """
        diff --git a/x.swift b/x.swift
        --- /dev/null
        +++ b/x.swift
        @@ -0,0 +1,1 @@
        +let x = 1
        """
        let files = UnifiedDiffParser.files(from: newFile)
        #expect(files[0].oldPath == nil)
        #expect(files[0].newPath == "x.swift")
        // 显示时退到存在的那一侧。
        #expect(files[0].displayPath == "x.swift")
    }

    @Test("空 / `nil` patch ⇒ 空数组（调用方不用先判空）")
    func emptyPatch() {
        #expect(UnifiedDiffParser.hunks(from: nil).isEmpty)
        #expect(UnifiedDiffParser.hunks(from: "").isEmpty)
        #expect(UnifiedDiffParser.hunks(from: "   \n  ").isEmpty)
    }

    @Test("认不出来的行归 `unknown` 并**原样保留**（丢掉它会让 diff 少一行，而没有任何迹象）")
    func unknownLinesAreKept() {
        let patch = """
        @@ -1,1 +1,1 @@
         context
        这行什么都没有
        """

        let lines = UnifiedDiffParser.hunks(from: patch)[0].lines
        #expect(lines.count == 2)
        #expect(lines[1].kind == .unknown)
        #expect(lines[1].text == "这行什么都没有")
    }

    @Test("⚠️ 空行（既不是 `+` 也不是 `-`）算**上下文**，不吃掉行号")
    func emptyLineIsContext() {
        let patch = """
        @@ -1,3 +1,3 @@
         a

         c
        """

        let lines = UnifiedDiffParser.hunks(from: patch)[0].lines
        #expect(lines.count == 3)
        #expect(lines[1].kind == .context)
        #expect(lines[1].text.isEmpty)
        #expect(lines[1].oldNumber == 2)
    }
}
