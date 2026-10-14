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
/// | 链接 label 不数嵌套 | `[![a](b)](c)` 散成一串原文 | 像作者写错了 markdown |
///
/// 最后两条是本片自查 / 用户报回时真发现的 ⇒ 它们是这批用例里最该留着的那几条。
@Suite("Markdown 图片 · 解析 / 块级提升 / 降级")
struct MarkdownImageTests {

    private func blocks(_ markdown: String) -> [MarkdownBlock] {
        MarkdownParser.blocks(from: markdown)
    }

    private func spans(_ text: String) -> [MarkdownSpan] {
        MarkdownInline.spans(text)
    }

    /// 直接把 shields.io 徽章解出来 —— 并排那几条判据关心的是"并没并"，
    /// 不是徽章解析本身（那个在 `MarkdownBadgeTests` 里单独守）。
    private func badge(_ path: String) -> MarkdownBadge? {
        guard let url = URL(string: "https://img.shields.io/badge/\(path)") else { return nil }
        return MarkdownBadge.parse(url: url, alt: "")
    }

    // MARK: - 行内解析

    @Test("`![alt](地址)` 解析成一个图片片段 —— 前导 `!` 不残留")
    func inlineImage() throws {
        let url = try #require(URL(string: "images/x.png"))
        #expect(spans("![截图](images/x.png)") == [
            MarkdownSpan(text: "截图", style: .image(url, size: nil))
        ])
    }

    @Test("`![](地址)`（`alt` 为空）**照样解析** —— 最常见的写法之一")
    func inlineImageWithoutAlt() throws {
        let url = try #require(URL(string: "../images/x.png"))
        #expect(spans("![](../images/x.png)") == [
            MarkdownSpan(text: "", style: .image(url, size: nil))
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

    // MARK: - 链接 label 里的嵌套（2026-10-14 新增）

    /// 这一组守的是**用户第二张截图右下角那串原文**：`<a><img></a>` 被
    /// `MarkdownHTML` 改写成 `[![alt](src)](href)`，而旧的 `parseLink`
    /// 只认"第一个 `]`" ⇒ 切在 `src` 那个 `]` 上，label 连 `!` 一起当文字、
    /// 尾巴 `](href)` 漏成正文（屏幕上就是"一串没渲染的原文"）。
    @Test("⚠️ `[![alt](图)](外链)` 取到**图**，外链丢掉（`<a><img></a>` 的改写结果）")
    func linkedImageBecomesImage() throws {
        let badge = try #require(URL(string: "https://img.shields.io/badge/Rust-100%25-orange"))
        #expect(spans("[![100% Rust](https://img.shields.io/badge/Rust-100%25-orange)](https://crates.io)") == [
            MarkdownSpan(text: "100% Rust", style: .image(badge, size: nil))
        ])
    }

    @Test("⚠️ 它独占一段时被提成**图片块**（README 里的徽章绝大多数是这种形状）")
    func linkedImageBecomesImageBlock() throws {
        let badge = try #require(URL(string: "https://img.shields.io/badge/x-y-z"))
        #expect(blocks(
            "<a href=\"https://crates.io\"><img src=\"https://img.shields.io/badge/x-y-z\" alt=\"Rust\"></a>"
        ) == [
            .image(url: badge, alt: "Rust", size: nil)
        ])
    }

    @Test("链接 label 里**含方括号**时，闭合的那个 `]` 按层数配")
    func linkLabelWithBrackets() throws {
        let url = try #require(URL(string: "d.md"))
        // label = `a[b]c`：若取"第一个 `]`"会得到 label `a[b`、地址 `c](d.md`（那个地址
        // 含 `]` 且末尾多了东西）⇒ 整条不解析、原样显示。
        #expect(spans("[a[b]c](d.md)") == [MarkdownSpan(text: "a[b]c", style: .link(url))])
    }

    @Test("⚠️ 登记：label 里**图文混排**时原样保留（不递归解析 label 内部）")
    func mixedLabelStaysLiteral() throws {
        let url = try #require(URL(string: "b.md"))
        // `MarkdownSpan` 是**平铺**的（见它的类型说明"有意不嵌套"）⇒ 只有
        // "label 整段就是一张图"才取图（`soleImageLabel`）。混排这一档回落成
        // 普通链接，label 按原文显示 —— 它**看得见、不吞字**，这是有意的取法。
        #expect(spans("[看 ![x](a.png) 这里](b.md)") == [
            MarkdownSpan(text: "看 ![x](a.png) 这里", style: .link(url))
        ])
    }

    // MARK: - 块级提升

    @Test("独占一段的图片被提成**图片块**（`alt` 有 / 没有都提）")
    func soleImageBecomesBlock() throws {
        let url = try #require(URL(string: "images/x.png"))
        #expect(blocks("![](images/x.png)") == [.image(url: url, alt: "", size: nil)])
        #expect(blocks("![截图](images/x.png)") == [.image(url: url, alt: "截图", size: nil)])
    }

    @Test("前后有空行时只提那一张图，段落不受影响")
    func soleImageBetweenParagraphs() throws {
        let url = try #require(URL(string: "images/x.png"))
        #expect(blocks("上面一段\n\n![截图](images/x.png)\n\n下面一段") == [
            .paragraph([MarkdownSpan(text: "上面一段")]),
            .image(url: url, alt: "截图", size: nil),
            .paragraph([MarkdownSpan(text: "下面一段")]),
        ])
    }

    @Test("⚠️ 图文混排**不提** —— 留在行内档，由视图降级成链接")
    func mixedContentIsNotPromoted() throws {
        let url = try #require(URL(string: "a.png"))
        #expect(blocks("看图 ![x](a.png) 这段") == [
            .paragraph([
                MarkdownSpan(text: "看图 "),
                MarkdownSpan(text: "x", style: .image(url, size: nil)),
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
                MarkdownSpan(text: "A", style: .image(first, size: nil)),
                MarkdownSpan(text: " "),
                MarkdownSpan(text: "B", style: .image(second, size: nil)),
            ])
        ])
    }

    @Test("列表项 / 引用里的图片**不提**（那两种块是行内档）")
    func imagesInsideOtherBlocksStayInline() throws {
        let url = try #require(URL(string: "a.png"))
        #expect(blocks("- ![x](a.png)") == [
            .listItem(ordered: false, number: nil, depth: 0, checked: nil, spans: [
                MarkdownSpan(text: "x", style: .image(url, size: nil))
            ])
        ])
        #expect(blocks("> ![x](a.png)") == [
            .quote([MarkdownSpan(text: "x", style: .image(url, size: nil))])
        ])
    }

    // MARK: - 空块判定（本片自查发现的连带处）

    @Test("⚠️ 引用 / 列表项里的**空 `alt` 图片不算空块** —— 否则整块会被静默丢掉")
    func altlessImageIsNotAnEmptyBlock() throws {
        let url = try #require(URL(string: "a.png"))
        // `isEmpty` 若按"文字非空"判，下面两条都会变成 `[]`（图消失、且不报错）。
        #expect(blocks("> ![](a.png)") == [
            .quote([MarkdownSpan(text: "", style: .image(url, size: nil))])
        ])
        #expect(blocks("- ![](a.png)") == [
            .listItem(ordered: false, number: nil, depth: 0, checked: nil, spans: [
                MarkdownSpan(text: "", style: .image(url, size: nil))
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

    // MARK: - 分行（`MarkdownInline.rows`，2026-10-12 重做、2026-10-14 加"并排"）

    /// 这一组守的是**用户报回的那条缺陷**：图与文字挤在同一行时，
    /// 上一版把整段降级成一个可点的「图片」二字（图没出来），
    /// 现在的规则是"只要这一段里有图，图就画出来"。
    ///
    /// ⚠️ 切分错的两种样子都不报错：切**少**了（图与文字黏在一格）⇒ 图又消失；
    /// 切**多**了（图与图之间那个空格也成一格）⇒ 正文里多出一行空白。
    @Test("`[图]` ⇒ 一个图片格")
    func rowsOfSoleImage() throws {
        let url = try #require(URL(string: "a.png"))
        #expect(MarkdownInline.rows(of: [MarkdownSpan(text: "x", style: .image(url, size: nil))]) == [
            .item(.image(url: url, alt: "x", size: nil))
        ])
    }

    @Test("⚠️ `[文字, 图, 文字]` ⇒ **三行**（图自己一行，不再降级成链接）")
    func rowsOfMixedContent() throws {
        let url = try #require(URL(string: "a.png"))
        #expect(MarkdownInline.rows(of: [
            MarkdownSpan(text: "看图 "),
            MarkdownSpan(text: "x", style: .image(url, size: nil)),
            MarkdownSpan(text: " 这段"),
        ]) == [
            .text([MarkdownSpan(text: "看图 ")]),
            .item(.image(url: url, alt: "x", size: nil)),
            .text([MarkdownSpan(text: " 这段")]),
        ])
    }

    @Test("⚠️ 图与图之间那段**只有空白**的文字不单独成行（否则会多画一行空白）")
    func whitespaceOnlyRunIsDropped() throws {
        let first = try #require(URL(string: "a.png"))
        let second = try #require(URL(string: "b.png"))
        #expect(MarkdownInline.rows(of: [
            MarkdownSpan(text: "x", style: .image(first, size: nil)),
            MarkdownSpan(text: " "),
            MarkdownSpan(text: "y", style: .image(second, size: nil)),
        ]) == [
            .item(.image(url: first, alt: "x", size: nil)),
            .item(.image(url: second, alt: "y", size: nil)),
        ])
    }

    @Test("⚠️ 尺寸**穿过**切分那一层（视图靠它决定占位块多高、能不能并排）")
    func rowsCarryImageSize() throws {
        let url = try #require(URL(string: "a.png"))
        let size = MarkdownImageSize(width: 16, height: 16)
        #expect(MarkdownInline.rows(of: [
            MarkdownSpan(text: "x", style: .image(url, size: size))
        ]) == [
            .item(.image(url: url, alt: "x", size: size))
        ])
    }

    @Test("没有图 ⇒ 只有一个 `.text`，内容**逐字不变**（这条路上与从前完全一致）")
    func rowsWithoutImagesIsOneTextRun() {
        let spans = MarkdownInline.spans("**粗体** 与 [链接](a.md) 与 `代码`")
        let rows = MarkdownInline.rows(of: spans)
        #expect(rows.count == 1)
        #expect(rows.first == .text(spans))
    }

    @Test("`alt` 为空照样切得出来（`![](a.png)` 不能因为没替代文字就丢）")
    func rowsCarryEmptyAlt() throws {
        let url = try #require(URL(string: "../images/x.png"))
        #expect(MarkdownInline.rows(of: spans("![](../images/x.png)")) == [
            .item(.image(url: url, alt: "", size: nil))
        ])
    }

    @Test("切分**不改动**任何片段：把各行拼回去与输入相等")
    func rowsPreserveSpans() {
        let spans = MarkdownInline.spans("前 ![x](a.png) 中 ![y](b.png) 后")
        let flattened = MarkdownInline.rows(of: spans).flatMap { row -> [MarkdownSpan] in
            switch row {
            case let .text(spans): spans
            // 图片的那一格原本就是一个片段，还原时把 `alt` 放回 `text`。
            case let .item(.image(url, alt, size)): [MarkdownSpan(text: alt, style: .image(url, size: size))]
            case let .item(.badge(badge)): [MarkdownSpan(text: badge.message)]
            // 并排的那一行按格拆回来，顺序不变。
            case let .row(items): items.flatMap { item -> [MarkdownSpan] in
                switch item {
                case let .image(url, alt, size): [MarkdownSpan(text: alt, style: .image(url, size: size))]
                case let .badge(badge): [MarkdownSpan(text: badge.message)]
                }
            }
            }
        }
        // ⚠️ 只有"**只由空白组成**"的那些片段会被丢掉，其余必须一段不差、顺序不变。
        let expected = spans.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(flattened == expected)
    }

    // MARK: - 并排（2026-10-14，走查第 65 条）

    /// ⚠️ 这一组守的是**用户 2026-10-14 报回的那个难看**：README 开头四张徽章
    /// 被排成四行、吃掉 216pt。判据见 `MarkdownRun`（连续 ≥2 个"宽度已知"的格）。
    ///
    /// 判错的两种样子同样不报错：**该并不并** ⇒ 又是四行大白条；
    /// **不该并却并了** ⇒ 一张大截图被挤到半行、按比例缩成一小块。

    @Test("⚠️ 连续两张**写了宽度**的图 ⇒ 并成一行")
    func consecutiveSizedImagesFormRow() throws {
        let first = try #require(URL(string: "a.png"))
        let second = try #require(URL(string: "b.png"))
        let size = MarkdownImageSize(width: 32, height: 32)
        #expect(MarkdownInline.rows(of: [
            MarkdownSpan(text: "x", style: .image(first, size: size)),
            MarkdownSpan(text: "y", style: .image(second, size: size)),
        ]) == [
            .row([
                .image(url: first, alt: "x", size: size),
                .image(url: second, alt: "y", size: size),
            ])
        ])
    }

    @Test("⚠️ 徽章**不需要尺寸**也能并排（宽度由它自己的文字算出来）")
    func badgesFormRow() throws {
        let first = try #require(badge("license-MIT-12a58a"))
        let second = try #require(badge("written%20in-Rust-0a7563"))
        #expect(MarkdownInline.rows(of: spans(
            "![a](https://img.shields.io/badge/license-MIT-12a58a) ![b](https://img.shields.io/badge/written%20in-Rust-0a7563)"
        )) == [
            .row([.badge(first), .badge(second)])
        ])
    }

    @Test("⚠️ 中间夹一张**宽度未知**的图 ⇒ 那一行断开（它必须占满一整行）")
    func unknownWidthBreaksTheRow() throws {
        let small = try #require(URL(string: "a.png"))
        let big = try #require(URL(string: "b.png"))
        let size = MarkdownImageSize(width: 32, height: 32)
        #expect(MarkdownInline.rows(of: [
            MarkdownSpan(text: "x", style: .image(small, size: size)),
            MarkdownSpan(text: "y", style: .image(big, size: nil)),
            MarkdownSpan(text: "z", style: .image(small, size: size)),
        ]) == [
            .item(.image(url: small, alt: "x", size: size)),
            .item(.image(url: big, alt: "y", size: nil)),
            .item(.image(url: small, alt: "z", size: size)),
        ])
    }

    @Test("⚠️ `width=\"100%\"` 不算宽度 ⇒ 大截图各占一行（百分比在解析时就化成 `nil`）")
    func percentageWidthIsNotPairiable() throws {
        let first = try #require(URL(string: "a.png"))
        let second = try #require(URL(string: "b.png"))
        #expect(MarkdownInline.rows(of: [
            MarkdownSpan(text: "x", style: .image(first, size: nil)),
            MarkdownSpan(text: "y", style: .image(second, size: nil)),
        ]) == [
            .item(.image(url: first, alt: "x", size: nil)),
            .item(.image(url: second, alt: "y", size: nil)),
        ])
    }

    @Test("一张徽章 + 一段文字 ⇒ 各占一行（文字不参与并排）")
    func badgeWithTextStaysSeparate() throws {
        let only = try #require(badge("license-MIT-12a58a"))
        #expect(MarkdownInline.rows(of: spans(
            "看 ![a](https://img.shields.io/badge/license-MIT-12a58a) 这句"
        )) == [
            .text([MarkdownSpan(text: "看 ")]),
            .item(.badge(only)),
            .text([MarkdownSpan(text: " 这句")]),
        ])
    }

    @Test("三张徽章连着写 ⇒ 一行三格（不是只并前两张）")
    func threeBadgesFormOneRow() throws {
        let urls = ["a-1-red", "b-2-green", "c-3-blue"]
        let text = urls.map { "![](https://img.shields.io/badge/\($0))" }.joined(separator: " ")
        let rows = MarkdownInline.rows(of: spans(text))
        #expect(rows.count == 1)
        #expect(rows.first?.itemCount == 3)
    }

    // MARK: - HTML 那条路（与 `MarkdownHTML` 的分工）

    @Test("HTML 的居中段里那张 `<img>` 也变成图片块（README 最常见的开头）")
    func imagenInCenteredParagraph() throws {
        let url = try #require(URL(string: "assets/hero.png"))
        #expect(blocks("""
        <p align="center">
        <img src="assets/hero.png" alt="主图">
        </p>
        """) == [.image(url: url, alt: "主图", size: nil)])
    }
}
