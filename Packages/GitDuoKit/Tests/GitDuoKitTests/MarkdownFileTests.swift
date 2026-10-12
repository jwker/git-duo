import Foundation
import Testing

@testable import GitDuoKit

/// 文件页的 markdown 判据与装配（2026-10-12 新增，按用户要求 —— 走查第 57 条）。
///
/// ⚠️ **钉住的是"哪种文件走 markdown"** —— 这一条写错了**不会报错**：
/// 少认一个后缀只会让一批 `.md` 继续以代码块出现，看起来像"这个 App 没做这个功能"，
/// 与 `FilePreviewKind.decide` 是同一类"错了只是显示成别的东西"的规则，
/// 所以它落在领域层、有一条单测（App target 没有测试 target，判据 #34）。
@Suite("文件页：哪些文件渲染成 markdown（走查第 57 条）")
struct MarkdownFileTests {

    // MARK: - 判据

    @Test("`.md` / `.markdown` 渲染 —— 含子目录、大写扩展名")
    func recognisesMarkdownExtensions() {
        #expect(MarkdownFile.rendersAsMarkdown(path: RepoPath(path: "README.md")))
        #expect(MarkdownFile.rendersAsMarkdown(path: RepoPath(path: "docs/guide.md")))
        #expect(MarkdownFile.rendersAsMarkdown(path: RepoPath(path: "notes.markdown")))
        // ⚠️ 大写：`FilePreviewKind.extensionOf` 内部 `lowercased()`，
        //    别在 `MarkdownFile` 里再写一遍（两处各写一份就会有一处漏 `.MD`）。
        #expect(MarkdownFile.rendersAsMarkdown(path: RepoPath(path: "README.MD")))
    }

    @Test("⚠️ 只有这两个后缀 —— 其余文本、无扩展名、图片一律**不**渲染")
    func leavesOtherFilesAlone() {
        #expect(!MarkdownFile.rendersAsMarkdown(path: RepoPath(path: "a.swift")))
        #expect(!MarkdownFile.rendersAsMarkdown(path: RepoPath(path: "notes.txt")))
        #expect(!MarkdownFile.rendersAsMarkdown(path: RepoPath(path: "doc.rst")))
        #expect(!MarkdownFile.rendersAsMarkdown(path: RepoPath(path: "Makefile")))
        // `.gitignore` 的 `pathExtension` 是空串（前导点属于隐藏文件名）
        #expect(!MarkdownFile.rendersAsMarkdown(path: RepoPath(path: ".gitignore")))
        #expect(!MarkdownFile.rendersAsMarkdown(path: RepoPath(path: "logo.png")))
        // ⚠️ 目录名里带 `.md` 不能把最后一段的扩展名带歪。
        #expect(!MarkdownFile.rendersAsMarkdown(path: RepoPath(path: "docs.md/guide.txt")))
    }

    // MARK: - 装配

    @Test("md → 一份带块的文档；非 md → `nil`（视图据此在代码块与 markdown 之间分流）")
    func buildsDocumentOnlyForMarkdown() throws {
        let source = "# 标题\n\n正文一段。"
        let document = try #require(MarkdownFile.document(path: RepoPath(path: "README.md"), text: source))

        #expect(!document.isEmpty)
        #expect(document.source == source, "原文与块同一来源 —— `Raw` 之外复制内容时要用它")
        #expect(!document.blocks.isEmpty)

        #expect(MarkdownFile.document(path: RepoPath(path: "a.swift"), text: source) == nil)
    }

    @Test("⚠️ 空 md 也给 `nil` —— 回落成代码块，不画白底空白卡片（同 README 那条）")
    func emptyMarkdownFallsBack() {
        #expect(MarkdownFile.document(path: RepoPath(path: "empty.md"), text: "") == nil)
        // 只有空行与空白 ⇒ 解析器不产块（`MarkdownParser`：空行不产生块）。
        #expect(MarkdownFile.document(path: RepoPath(path: "blank.md"), text: "\n\n   \n") == nil)
    }
}
