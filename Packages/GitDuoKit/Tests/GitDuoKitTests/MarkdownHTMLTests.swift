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

    @Test("`<img src alt>` 退化成指向那张图的链接，文字取 `alt`")
    func imageBecomesLink() throws {
        let source = try #require(URL(string: "assets/desktop-hero-zh.png"))
        #expect(blocks("<img src=\"assets/desktop-hero-zh.png\" alt=\"桌面端主图\" width=\"100%\">") == [
            .paragraph([
                MarkdownSpan(text: "桌面端主图", style: .link(source))
            ])
        ])
    }

    @Test("没有 `alt` 的图片整张丢掉（不是留一个空链接）")
    func imageWithoutAltIsDropped() {
        #expect(blocks("<img src=\"assets/x.png\" width=\"96\">").isEmpty)
    }

    @Test("属性值里的 `>` 不算标签收尾")
    func angleBracketInsideAttribute() throws {
        let source = try #require(URL(string: "x.png"))
        #expect(blocks("<img alt=\"a > b\" src=\"x.png\">") == [
            .paragraph([
                MarkdownSpan(text: "a > b", style: .link(source))
            ])
        ])
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
