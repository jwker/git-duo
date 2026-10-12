import Foundation
import Testing

@testable import GitDuoKit

/// markdown 里的图片（2026-10-12 新增，`REVIEW-CHECKLIST` **第 58 条**）。
///
/// ## 这批用例在守什么
///
/// 图片是**新开的一条通道**，而它每一处判据错了的样子都很像"内容本来如此"：
///
/// | 写错了的地方 | 屏幕上的表现 | 像什么 |
/// |---|---|---|
/// | 提升判据写**松** | 图文混排的一段被拆成"一张图 + 一段孤立的文字" | 像原文件排版不好 |
/// | 提升判据写**紧** | 图不出现，用户看到一串 `![](…)` 原文 | **就是这条缺陷本来的样子** |
/// | 前导 `!` 没收干净 | 屏幕上多一个感叹号 | 像用户自己打错的标点 |
/// | 空块判定漏了图片 | 引用 / 列表项里那张无 `alt` 的图消失 | 什么都没有，**不报错** |
///
/// 最后一条是本片自查时真发现的（`MarkdownBlock.isEmpty` 按"文字非空"判，
/// 而 `![](a.png)` 的 `alt` 恰好是空的）⇒ 它是这批用例里最该留着的那几条。
@Suite("Markdown 图片 · 解析 / 块级提升 / 降级")
struct MarkdownImageTests {

    private func blocks(_ markdown: String) -> [MarkdownBlock] {
        MarkdownParser.blocks(from: markdown)
    }

    private func spans(_ text: String) -> [MarkdownSpan] {
        MarkdownInline.spans(text)
    }

    // MARK: - 行内解析

    @Test("`![alt](地址)` 解析成一个图片片段 —— 前导 `!` 不残留")
    func inlineImage() throws {
        let url = try #require(URL(string: "images/x.png"))
        #expect(spans("![截图](images/x.png)") == [
            MarkdownSpan(text: "截图", style: .image(url))
        ])
    }

    @Test("`![](地址)`（`alt` 为空）**照样解析** —— 最常见的写法之一")
    func inlineImageWithoutAlt() throws {
        let url = try #require(URL(string: "../images/x.png"))
        #expect(spans("![](../images/x.png)") == [
            MarkdownSpan(text: "", style: .image(url))
        ])
    }

    @Test("`!` 与 `[文字](地址)` 互不干扰：没有 `!` 的仍是**链接**")
    func linkIsNotImage() throws {
        let url = try #require(URL(string: "a.md"))
        #expect(spans("[文字](a.md)") == [MarkdownSpan(text: "文字", style: .link(url))])
    }

    @Test("形状不完整时**不解析**，原样留成文字（宁可显示原文，不可吃字）")
    func malformedImageStaysLiteral() {
        #expect(spans("![缺括号]") == [MarkdownSpan(text: "![缺括号]")])
        // 地址里有空格 ⇒ 不是地址（同链接那条：`URL(string:)` 对空格是宽容的）。
        #expect(spans("![](有 空格.png)") == [MarkdownSpan(text: "![](有 空格.png)")])
        #expect(spans("![空地址]()") == [MarkdownSpan(text: "![空地址]()")])
    }

    // MARK: - 块级提升

    @Test("独占一段的图片被提成**图片块**（`alt` 有 / 没有都提）")
    func soleImageBecomesBlock() throws {
        let url = try #require(URL(string: "images/x.png"))
        #expect(blocks("![](images/x.png)") == [.image(url: url, alt: "")])
        #expect(blocks("![截图](images/x.png)") == [.image(url: url, alt: "截图")])
    }

    @Test("前后有空行时只提那一张图，段落不受影响")
    func soleImageBetweenParagraphs() throws {
        let url = try #require(URL(string: "images/x.png"))
        #expect(blocks("上面一段\n\n![截图](images/x.png)\n\n下面一段") == [
            .paragraph([MarkdownSpan(text: "上面一段")]),
            .image(url: url, alt: "截图"),
            .paragraph([MarkdownSpan(text: "下面一段")]),
        ])
    }

    @Test("⚠️ 图文混排**不提** —— 留在行内档，由视图降级成链接")
    func mixedContentIsNotPromoted() throws {
        let url = try #require(URL(string: "a.png"))
        #expect(blocks("看图 ![x](a.png) 这段") == [
            .paragraph([
                MarkdownSpan(text: "看图 "),
                MarkdownSpan(text: "x", style: .image(url)),
                MarkdownSpan(text: " 这段"),
            ])
        ])
    }

    @Test("⚠️ 同一段里两张图 ⇒ **两张都不提**（并排排版原型没定过，不猜）")
    func twoImagesInOneParagraphAreNotPromoted() throws {
        let first = try #require(URL(string: "a.png"))
        let second = try #require(URL(string: "b.png"))
        #expect(blocks("![A](a.png)\n![B](b.png)") == [
            .paragraph([
                MarkdownSpan(text: "A", style: .image(first)),
                MarkdownSpan(text: " "),
                MarkdownSpan(text: "B", style: .image(second)),
            ])
        ])
    }

    @Test("列表项 / 引用里的图片**不提**（那两种块是行内档）")
    func imagesInsideOtherBlocksStayInline() throws {
        let url = try #require(URL(string: "a.png"))
        #expect(blocks("- ![x](a.png)") == [
            .listItem(ordered: false, number: nil, depth: 0, checked: nil, spans: [
                MarkdownSpan(text: "x", style: .image(url))
            ])
        ])
        #expect(blocks("> ![x](a.png)") == [
            .quote([MarkdownSpan(text: "x", style: .image(url))])
        ])
    }

    // MARK: - 空块判定（本片自查发现的连带处）

    @Test("⚠️ 引用 / 列表项里的**空 `alt` 图片不算空块** —— 否则整块会被静默丢掉")
    func altlessImageIsNotAnEmptyBlock() throws {
        let url = try #require(URL(string: "a.png"))
        // `isEmpty` 若按"文字非空"判，下面两条都会变成 `[]`（图消失、且不报错）。
        #expect(blocks("> ![](a.png)") == [
            .quote([MarkdownSpan(text: "", style: .image(url))])
        ])
        #expect(blocks("- ![](a.png)") == [
            .listItem(ordered: false, number: nil, depth: 0, checked: nil, spans: [
                MarkdownSpan(text: "", style: .image(url))
            ])
        ])
    }

    @Test("真的空块仍然被丢掉（别把上面那条修成\"什么都不丢\"）")
    func genuinelyEmptyBlocksAreStillDropped() {
        #expect(blocks("> \n\n- \n\n") == [])
        #expect(blocks("").isEmpty)
    }

    // MARK: - 代码块里的图片语法是原文

    @Test("代码块里的 `![]()` 是**原文** —— 围栏在第一支就被拿走了")
    func imageSyntaxInsideCodeBlockIsLiteral() {
        #expect(blocks("```\n![](a.png)\n```") == [
            .codeBlock(language: nil, lines: ["![](a.png)"])
        ])
    }

    @Test("行内代码里的 `![]()` 同样是原文")
    func imageSyntaxInsideInlineCodeIsLiteral() {
        #expect(spans("`![](a.png)`") == [MarkdownSpan(text: "![](a.png)", style: .code)])
    }

    // MARK: - 切分（`MarkdownInline.runs`，2026-10-12 当天重做的那一处）

    /// 这一组守的是**用户报回的那条缺陷**：图与文字挤在同一行时，
    /// 上一版把整段降级成一个可点的「图片」二字（图没出来），
    /// 现在的规则是"只要这一段里有图，图就画出来"。
    ///
    /// ⚠️ 切分错的两种样子都不报错：切**少**了（图与文字黏在一格）⇒ 图又消失；
    /// 切**多**了（图与图之间那个空格也成一格）⇒ 正文里多出一行空白。
    @Test("`[图]` ⇒ 一个图片格")
    func runsOfSoleImage() throws {
        let url = try #require(URL(string: "a.png"))
        #expect(MarkdownInline.runs(of: [MarkdownSpan(text: "x", style: .image(url))]) == [
            .image(url: url, alt: "x")
        ])
    }

    @Test("⚠️ `[文字, 图, 文字]` ⇒ **三格**（图自己一格，不再降级成链接）")
    func runsOfMixedContent() throws {
        let url = try #require(URL(string: "a.png"))
        #expect(MarkdownInline.runs(of: [
            MarkdownSpan(text: "看图 "),
            MarkdownSpan(text: "x", style: .image(url)),
            MarkdownSpan(text: " 这段"),
        ]) == [
            .text([MarkdownSpan(text: "看图 ")]),
            .image(url: url, alt: "x"),
            .text([MarkdownSpan(text: " 这段")]),
        ])
    }

    @Test("⚠️ 图与图之间那段**只有空白**的文字不单独成格（否则会多画一行空白）")
    func whitespaceOnlyRunIsDropped() throws {
        let first = try #require(URL(string: "a.png"))
        let second = try #require(URL(string: "b.png"))
        #expect(MarkdownInline.runs(of: [
            MarkdownSpan(text: "x", style: .image(first)),
            MarkdownSpan(text: " "),
            MarkdownSpan(text: "y", style: .image(second)),
        ]) == [
            .image(url: first, alt: "x"),
            .image(url: second, alt: "y"),
        ])
    }

    @Test("没有图 ⇒ 只有一个 `.text`，内容**逐字不变**（这条路上与从前完全一致）")
    func runsWithoutImagesIsOneTextRun() {
        let spans = MarkdownInline.spans("**粗体** 与 [链接](a.md) 与 `代码`")
        let runs = MarkdownInline.runs(of: spans)
        #expect(runs.count == 1)
        #expect(runs.first == .text(spans))
    }

    @Test("`alt` 为空照样切得出来（`![](a.png)` 不能因为没替代文字就丢）")
    func runsCarryEmptyAlt() throws {
        let url = try #require(URL(string: "../images/x.png"))
        #expect(MarkdownInline.runs(of: spans("![](../images/x.png)")) == [
            .image(url: url, alt: "")
        ])
    }

    @Test("切分**不改动**任何片段：把各格拼回去与输入相等")
    func runsPreserveSpans() {
        let spans = MarkdownInline.spans("前 ![x](a.png) 中 ![y](b.png) 后")
        let flattened = MarkdownInline.runs(of: spans).flatMap { run -> [MarkdownSpan] in
            switch run {
            case let .text(spans): spans
            // 图片的那一格原本就是一个片段，还原时把 `alt` 放回 `text`。
            case let .image(url, alt): [MarkdownSpan(text: alt, style: .image(url))]
            }
        }
        // ⚠️ 只有"**只由空白组成**"的那些片段会被丢掉，其余必须一段不差、顺序不变。
        let expected = spans.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(flattened == expected)
    }

    // MARK: - HTML 那条路（与 `MarkdownHTML` 的分工）

    @Test("HTML 的居中段里那张 `<img>` 也变成图片块（README 最常见的开头）")
    func imagenInCenteredParagraph() throws {
        let url = try #require(URL(string: "assets/hero.png"))
        #expect(blocks("""
        <p align="center">
        <img src="assets/hero.png" alt="主图">
        </p>
        """) == [.image(url: url, alt: "主图")])
    }
}
