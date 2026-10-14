import Foundation
import Testing

@testable import GitDuoKit

/// `MarkdownHTML` —— README 里的 HTML 降级。
///
/// ## 这批用例在守什么
///
/// 真实 README 里的 HTML 形状**就那么几种**（居中的 `p` / `h1` / `h3`、
/// 包在链接里的 `img`、`sub` 里的 `br`、`details`/`summary`、`table`），
/// 而每一种都要走对一条"改写规则"。改写错了**不会报错** ——
/// 要么整块消失、要么多出一串星号、要么递归不收敛（唯一会崩的那种）。
@Suite("MarkdownHTML")
struct MarkdownHTMLTests {

    private func blocks(_ html: String) -> [MarkdownBlock] {
        MarkdownParser.blocks(from: html)
    }

    // MARK: - 标题（`anywhere-labs/dsh-desktop` 的开头就是这一串）

    @Test("`<h1 align=…>` ⇒ 一级标题，居中属性被丢掉")
    func centeredHeading() {
        #expect(blocks("<h1 align=\"center\">DSH Desktop</h1>") == [
            .heading(level: 1, spans: [MarkdownSpan(text: "DSH Desktop")])
        ])
    }

    @Test("`<h3>` 里的链接照常解析成链接")
    func headingWithLink() throws {
        // ⚠️ `#require` 不能在 `#expect` 的自动闭包里 `try`（那个闭包不是 throws 的）
        //    ⇒ 地址先在断言**外面**取出来。
        let href = try #require(URL(string: "https://dshdesktop.cn"))
        #expect(blocks("<h3 align=\"center\"><a href=\"https://dshdesktop.cn\">一键下载，开箱即用。</a></h3>") == [
            .heading(level: 3, spans: [
                MarkdownSpan(text: "一键下载，开箱即用。", style: .link(href))
            ])
        ])
    }

    // MARK: - 段落与行内标签

    @Test("`<p>` 里的 `<strong>` 变成粗体")
    func paragraphWithStrong() {
        #expect(blocks("<p align=\"center\">\n<strong>基于 DSH 构建的桌面客户端。</strong>\n</p>") == [
            .paragraph([
                MarkdownSpan(text: "基于 DSH 构建的桌面客户端。", style: .bold)
            ])
        ])
    }

    // MARK: - `<br>`

    @Test("`<br>` 断成两段（`MarkdownSpan` 里没有段内换行这一档）")
    func lineBreakSplitsParagraph() {
        #expect(blocks("<p>x<br>y</p>") == [
            .paragraph([MarkdownSpan(text: "x")]),
            .paragraph([MarkdownSpan(text: "y")])
        ])
    }

    // MARK: - 图片

    @Test("`<img src alt>` 变成**图片块**，`alt` 进读屏（2026-10-12 起不再降级成链接）")
    func imageBecomesImageBlock() throws {
        let source = try #require(URL(string: "assets/desktop-hero-zh.png"))
        // ⚠️ `width="100%"` **不是**合法像素值 ⇒ 尺寸留空（判据见 `MarkdownHTML.declaredImageSizes`）。
        #expect(blocks("<img src=\"assets/desktop-hero-zh.png\" alt=\"桌面端主图\" width=\"100%\">") == [
            .image(url: source, alt: "桌面端主图", size: nil)
        ])
    }

    @Test("没有 `alt` 的图片**照样画**（老规矩\"整张丢掉\"已废 —— 那在纯文字里才成立）")
    func imageWithoutAltIsKept() throws {
        let source = try #require(URL(string: "assets/x.png"))
        // ⚠️ `width="96"` 是合法像素值 ⇒ **回填到块上**（2026-10-14 新增的那一步）。
        //    视图据此决定占位块多高、以及小图别被放大。
        #expect(blocks("<img src=\"assets/x.png\" width=\"96\">") == [
            .image(url: source, alt: "", size: MarkdownImageSize(width: 96))
        ])
    }

    @Test("属性值里的 `>` 不算标签收尾")
    func angleBracketInsideAttribute() throws {
        let source = try #require(URL(string: "x.png"))
        #expect(blocks("<img alt=\"a > b\" src=\"x.png\">") == [
            .image(url: source, alt: "a > b", size: nil)
        ])
    }

    // MARK: - 图片尺寸（2026-10-14 新增）

    /// 这一组守的是用户 2026-10-14 报回的那张截图里**另一半**问题：
    /// 四张徽章各占一个 128pt 的大占位块，把正文挤得很长 ——
    /// 因为 `width` / `height` 在改写成 markdown 时被丢掉了。
    ///
    /// ⚠️ 尺寸丢了**不报错**：占位块大一点、徽章被放大一点，看起来都只是"排版不太对"。
    @Test("`<img width= height=>` 的尺寸**穿过改写**回到块上")
    func imageSizeSurvivesRewrite() throws {
        let source = try #require(URL(string: "https://img.shields.io/badge/Rust-100%25-orange"))
        #expect(blocks("""
        <a href="https://crates.io"><img src="https://img.shields.io/badge/Rust-100%25-orange" alt="Rust" height="20"></a>
        """) == [
            // ⚠️ 外链**有意丢掉**（`MarkdownSpan` 是平铺的，没有"一张可点的图"这一档）。
            .image(url: source, alt: "Rust", size: MarkdownImageSize(height: 20))
        ])
    }

    @Test("⚠️ `<a>` 与 `<img>` 跨行时也要**剥掉外链包装**（否则 `[` / `](href)` 会散成两段文字）")
    func multilineLinkedImageDropsAnchorWrapper() throws {
        let source = try #require(URL(string: "docs/brand/artcraft-logo.svg"))
        #expect(blocks("""
        <a href="https://getartcraft.com/">
          <img src="docs/brand/artcraft-logo.svg" alt="ArtCraft" width="200">
        </a>
        """) == [
            .image(url: source, alt: "ArtCraft", size: MarkdownImageSize(width: 200))
        ])
    }

    @Test("只写 `width` 也认（`height` 留空，由真实宽高比决定显示高度）")
    func widthOnlyIsKept() throws {
        let source = try #require(URL(string: "logo.svg"))
        #expect(blocks("<img src=\"logo.svg\" width=\"200\">") == [
            .image(url: source, alt: "", size: MarkdownImageSize(width: 200))
        ])
    }

    @Test("⚠️ 非数字的尺寸一律当没写（`100%` / `auto` / 小数 / 负数）")
    func nonNumericSizesAreIgnored() throws {
        let source = try #require(URL(string: "x.png"))
        for width in ["100%", "auto", "12.5", "-3", "", "96px"] {
            #expect(blocks("<img src=\"x.png\" width=\"\(width)\">") == [
                .image(url: source, alt: "", size: nil)
            ], "`width=\"\(width)\"` 不该被当成像素值")
        }
    }

    @Test("⚠️ 注释里的 `<img width=…>` **不进尺寸表**（正文里同地址那张不该被它带上尺寸）")
    func commentedOutImageDoesNotLeakSize() throws {
        let source = try #require(URL(string: "x.png"))
        #expect(blocks("<!-- <img src=\"x.png\" width=\"999\"> -->\n<img src=\"x.png\" width=\"16\" height=\"16\">") == [
            .image(url: source, alt: "", size: MarkdownImageSize(width: 16, height: 16))
        ])
    }

    @Test("表格单元格里的图**同样回填**（HTML 表格里放徽章是常见写法）")
    func tableCellImageSizeIsFilled() throws {
        let source = try #require(URL(string: "badge.svg"))
        let blocks = self.blocks("""
        <table><tr><th>构建</th></tr><tr><td><img src="badge.svg" width="80" height="20"></td></tr></table>
        """)
        // 表格块里的那一个单元格：`[MarkdownSpan]` 的首个片段必须带上尺寸。
        guard case let .table(table) = try #require(blocks.first) else {
            Issue.record("期望一个表格块，实际是 \(blocks)")
            return
        }
        guard case let .image(url, size) = table.rows.first?.first?.first?.style else {
            Issue.record("期望单元格里的第一个片段是图片，实际是 \(table.rows)")
            return
        }
        #expect(url == source)
        #expect(size == MarkdownImageSize(width: 80, height: 20))
    }

    // MARK: - 相对链接（与第 3 条目视发现合起来才完整）

    @Test("`<a href=\"README.en.md\">` 里的相对地址原样交给链接解析")
    func relativeLinkSurvives() throws {
        let href = try #require(URL(string: "README.en.md"))
        #expect(blocks("<sub>中文 · <a href=\"README.en.md\">English</a></sub>") == [
            .paragraph([
                MarkdownSpan(text: "中文 · "),
                MarkdownSpan(text: "English", style: .link(href)),
            ])
        ])
    }

    // MARK: - details / summary

    @Test("`<summary>` 变粗体段落；`</details>` 单独一块不产出任何东西")
    func detailsAndSummary() {
        #expect(blocks("<details open>\n<summary>❤️ 赞助商</summary>") == [
            .paragraph([MarkdownSpan(text: "❤️ 赞助商", style: .bold)])
        ])

        #expect(blocks("</details>").isEmpty)
    }

    // MARK: - HTML 表格 → GFM

    @Test("HTML 表格转成 GFM 表格块（`<th>` 为表头）")
    func htmlTableWithTH() {
        let html = "<table><tr><th>名称</th><th>数值</th></tr><tr><td>甲</td><td>1</td></tr></table>"
        #expect(blocks(html) == [
            .table(MarkdownTable(
                alignments: [.left, .left],
                header: [[MarkdownSpan(text: "名称")], [MarkdownSpan(text: "数值")]],
                rows: [[[MarkdownSpan(text: "甲")], [MarkdownSpan(text: "1")]]]
            ))
        ])
    }

    @Test("⚠️ 全 `<td>` 的表格：第一行兜底为表头")
    func htmlTableWithoutTHUsesFirstRowAsHeader() {
        let html = "<table><tr><td>企业微信</td><td>QQ群</td></tr></table>"
        #expect(blocks(html) == [
            .table(MarkdownTable(
                alignments: [.left, .left],
                header: [[MarkdownSpan(text: "企业微信")], [MarkdownSpan(text: "QQ群")]],
                rows: []
            ))
        ])
    }

    @Test("`<thead>` 里的 `<td>` 也是表头")
    func htmlTableWithTHead() {
        let html = "<table><thead><tr><td>列一</td></tr></thead><tbody><tr><td>数据</td></tr></tbody></table>"
        #expect(blocks(html) == [
            .table(MarkdownTable(
                alignments: [.left],
                header: [[MarkdownSpan(text: "列一")]],
                rows: [[[MarkdownSpan(text: "数据")]]]
            ))
        ])
    }

    // MARK: - 实体

    @Test("实体要还原（README 的徽章地址里 `&amp;` 遍地都是）")
    func entitiesAreDecoded() {
        #expect(MarkdownHTML.decodeEntities("a &amp; b &lt;c&gt; &#65; &#x42;") == "a & b <c> A B")
        #expect(blocks("<p>a &amp; b</p>") == [.paragraph([MarkdownSpan(text: "a & b")])])
    }

    @Test("认不出的实体原样保留（比变成空白更容易查）")
    func unknownEntityIsKept() {
        #expect(MarkdownHTML.decodeEntities("&foo; &") == "&foo; &")
    }

    // MARK: - 不该被碰的东西

    @Test("围栏代码块里的标签是**原文**，一个字符都不动")
    func fencedCodeIsUntouched() {
        #expect(blocks("```html\n<p>hi</p>\n```") == [
            .codeBlock(language: "html", lines: ["<p>hi</p>"])
        ])
    }

    @Test("`<https://example.com>` 不是标签，不进 HTML 块（照旧当正文）")
    func autolinkIsNotATag() {
        // ⚠️ 它连"HTML 块起始"都不是 —— `htmlBlockStart` 要求标签名后面紧跟
        //    `>` / `/` / 空白，而这里跟的是 `:`。
        #expect(MarkdownParser.htmlBlockStart("<https://example.com>") == false)
        #expect(blocks("<https://example.com>") == [
            .paragraph([MarkdownSpan(text: "<https://example.com>")])
        ])
    }

    @Test("一行残缺的 `<b` 不是 HTML 块起始（否则递归不收敛）")
    func incompleteTagIsNotABlockStart() {
        #expect(MarkdownParser.htmlBlockStart("<b") == false)
        #expect(blocks("<b") == [.paragraph([MarkdownSpan(text: "<b")])])
    }

    // MARK: - 已登记的有损处（写成断言，免得它被当成"没实现"）

    @Test("实体转义出来的标签会被吃掉 —— 已登记的降级，不是 bug")
    func escapedTagIsRemoved() {
        // 第二趟去标签是为了断掉"还原出标签 → 再被当 HTML 块"的递归，
        // 代价就是正文里 `&lt;div&gt;` 写出来的 `<div>` 会消失。
        // 代码块不受影响（上一条用例已钉住）。要根治得区分"实体来源的 `<`"，
        // 与收益不成比例 —— 登记在 `MarkdownHTML` 的类型说明里。
        #expect(blocks("<p>&lt;div&gt;</p>").isEmpty)
    }

    // MARK: - 有序列表

    @Test("`<ol>` 还原编号：1、2、3")
    func orderedListKeepsNumbers() {
        #expect(blocks("<ol><li>一</li><li>二</li><li>三</li></ol>") == [
            .listItem(ordered: true, number: 1, depth: 0, checked: nil, spans: [MarkdownSpan(text: "一")]),
            .listItem(ordered: true, number: 2, depth: 0, checked: nil, spans: [MarkdownSpan(text: "二")]),
            .listItem(ordered: true, number: 3, depth: 0, checked: nil, spans: [MarkdownSpan(text: "三")]),
        ])
    }

    @Test("`<ol start=5>` 从 5 开始；`<li value=9>` 改变当前编号")
    func orderedListStartAndValue() {
        #expect(blocks("<ol start=\"5\"><li>五</li><li value=\"9\">九</li><li>十</li></ol>") == [
            .listItem(ordered: true, number: 5, depth: 0, checked: nil, spans: [MarkdownSpan(text: "五")]),
            .listItem(ordered: true, number: 9, depth: 0, checked: nil, spans: [MarkdownSpan(text: "九")]),
            .listItem(ordered: true, number: 10, depth: 0, checked: nil, spans: [MarkdownSpan(text: "十")]),
        ])
    }

    @Test("嵌套列表各自计数（ul 里套 ol；本期不做缩进，层级都是 0）")
    func nestedOrderedAndUnordered() {
        #expect(blocks("<ul><li>外</li><ol><li>内一</li><li>内二</li></ol></ul>") == [
            .listItem(ordered: false, number: nil, depth: 0, checked: nil, spans: [MarkdownSpan(text: "外")]),
            .listItem(ordered: true, number: 1, depth: 0, checked: nil, spans: [MarkdownSpan(text: "内一")]),
            .listItem(ordered: true, number: 2, depth: 0, checked: nil, spans: [MarkdownSpan(text: "内二")]),
        ])
    }

    // MARK: - 改写本身

    @Test("HTML 块**以空行收尾**，不是以 `</div>` 收尾（CommonMark 6 / 7 型）")
    func blockEndsAtBlankLine() {
        // 第二行是普通 markdown ⇒ 它属于**另一个**块，不被卷进 HTML 里。
        #expect(blocks("<div align=\"center\">\n标题\n\n普通段落") == [
            .paragraph([MarkdownSpan(text: "标题")]),
            .paragraph([MarkdownSpan(text: "普通段落")]),
        ])
    }
}
