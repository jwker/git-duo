import Foundation
import Testing

@testable import GitDuoKit

/// 块级 Markdown 解析（TECH_SPEC §11.1）。
///
/// §11.1 明写要用单测覆盖「嵌套列表、代码块内的 `#`、未闭合标记」这些边界 ——
/// 它们是**解析器最容易悄悄错**的地方：错了不报错，只是渲染出来的 README
/// 少了一行、或者一段代码被当成了标题。
@Suite("Markdown 块级解析 · 块判定 / 行内 / 边界")
struct MarkdownParserTests {

    private func blocks(_ markdown: String) -> [MarkdownBlock] {
        MarkdownParser.blocks(from: markdown)
    }

    /// 把块序列压成便于断言的一层结构（只取"是什么块 + 文字"）。
    private func outline(_ markdown: String) -> [String] {
        blocks(markdown).map { block -> String in
            switch block {
            case let .heading(level, spans):
                return "h\(level):\(MarkdownSpan.plainText(of: spans))"
            case let .paragraph(spans):
                return "p:\(MarkdownSpan.plainText(of: spans))"
            case let .listItem(ordered, number, depth, checked, spans):
                let mark = ordered ? "\(number ?? 0)." : "-"
                let box = checked.map { $0 ? "[x]" : "[ ]" } ?? ""
                return "li\(depth)\(mark)\(box):\(MarkdownSpan.plainText(of: spans))"
            case let .quote(spans):
                return "q:\(MarkdownSpan.plainText(of: spans))"
            case let .codeBlock(language, lines):
                return "code(\(language ?? "-")):\(lines.joined(separator: "\\n"))"
            case .divider:
                return "hr"
            }
        }
    }

    // MARK: - 标题

    @Test("`#` 到 `######` 是标题，级别就是 `#` 的个数")
    func headings() {
        #expect(outline("# 一级") == ["h1:一级"])
        #expect(outline("### 三级") == ["h3:三级"])
        #expect(outline("###### 六级") == ["h6:六级"])
        // 七个 `#` 不是标题（CommonMark 的上限是 6）—— 它是一条普通段落。
        #expect(outline("####### 七级不是标题") == ["p:####### 七级不是标题"])
    }

    @Test("⚠️ `#` 后面**必须有空格** —— 否则 `#hashtag` 会变成标题（README 里很常见）")
    func hashWithoutSpaceIsNotAHeading() {
        #expect(outline("#hashtag") == ["p:#hashtag"])
        #expect(outline("##也是") == ["p:##也是"])
    }

    // MARK: - 代码块

    @Test("代码块带语言、多行原样保留")
    func codeBlockWithLanguage() {
        let markdown = """
        ```swift
        let x = 1
        print(x)
        ```
        """

        #expect(outline(markdown) == ["code(swift):let x = 1\\nprint(x)"])
    }

    @Test("⚠️ **代码块内部的一切都是原文**：`#` 不是标题、`**` 不是粗体、`-` 不是列表")
    func codeBlockContentIsVerbatim() {
        let markdown = """
        ```
        # 这不是标题
        **这不是粗体**
        - 这不是列表
        ```
        """

        let result = blocks(markdown)
        #expect(result.count == 1)
        if case let .codeBlock(language, lines) = result[0] {
            #expect(language == nil)
            #expect(lines == ["# 这不是标题", "**这不是粗体**", "- 这不是列表"])
        } else {
            Issue.record("应当是一个代码块")
        }
    }

    @Test("⚠️ 未闭合的代码块**吃到文末**，不丢内容")
    func unclosedFenceRunsToEnd() {
        let markdown = """
        ```
        line 1
        line 2
        """

        #expect(outline(markdown) == ["code(-):line 1\\nline 2"])
    }

    @Test("`~~~` 也是围栏；长围栏要更长的围栏才能收尾")
    func tildeFences() {
        let markdown = """
        ~~~
        code
        ~~~
        """
        #expect(outline(markdown) == ["code(-):code"])
    }

    @Test("⚠️ 围栏后面那串里**再有反引号**就不是围栏（CommonMark 规则，防止行内代码被当语言名）")
    func fenceWithBacktickInInfoIsRejected() {
        let result = blocks("``` swift ``` extra")

        // ⚠️ 关键是它**不是代码块**：判成代码块的话，后面整篇 README 都会被吞进这个块里，
        //    而页面上只会表现为"这一行之后什么都没有了"。
        #expect(result.count == 1)
        if case .codeBlock = result.first {
            Issue.record("含反引号的 info string 不该被当成围栏")
        }
    }

    // MARK: - 列表

    @Test("无序列表三种记号 + 有序列表（**保留服务端给的编号**）")
    func listMarkers() {
        #expect(outline("- 一") == ["li0-:一"])
        #expect(outline("* 二") == ["li0-:二"])
        #expect(outline("+ 三") == ["li0-:三"])
        #expect(outline("3. 三") == ["li03.:三"])
        #expect(outline("4) 四") == ["li04.:四"])
    }

    @Test("⚠️ 嵌套列表按**缩进栈**算层级（2 空格与 4 空格缩进都能正确分层）")
    func nestedLists() {
        let twoSpaces = """
        - 一
          - 一之一
            - 一之一之一
        - 二
        """
        #expect(outline(twoSpaces) == ["li0-:一", "li1-:一之一", "li2-:一之一之一", "li0-:二"])

        let fourSpaces = """
        - 一
            - 一之一
        """
        #expect(outline(fourSpaces) == ["li0-:一", "li1-:一之一"])
    }

    @Test("任务列表：`[ ]` / `[x]` / `[X]`")
    func taskLists() {
        #expect(outline("- [ ] 未做") == ["li0-[ ]:未做"])
        #expect(outline("- [x] 已做") == ["li0-[x]:已做"])
        #expect(outline("- [X] 大写也行") == ["li0-[x]:大写也行"])
    }

    @Test("⚠️ `-foo`（记号后没空格）**不是列表** —— 它是文字里的一根破折号")
    func dashWithoutSpaceIsNotAList() {
        #expect(outline("-foo") == ["p:-foo"])
        #expect(outline("10.5 是数字不是有序列表项") == ["p:10.5 是数字不是有序列表项"])
    }

    @Test("列表项的**续行**并入本项（不并入的话会显示成「列表项 + 一个孤零零的段落」）")
    func listItemContinuation() {
        let markdown = """
        - 第一行很长，
          第二行接着写
        """

        #expect(outline(markdown) == ["li0-:第一行很长， 第二行接着写"])
    }

    // MARK: - 引用与分隔线

    @Test("引用去掉 `>` 与前导空格")
    func quotes() {
        #expect(outline("> 引用一句") == ["q:引用一句"])
        #expect(outline(">无空格") == ["q:无空格"])
    }

    @Test("分隔线：`---` / `***` / `___`（**至少三个**，其间可含空格）")
    func dividers() {
        #expect(outline("---") == ["hr"])
        #expect(outline("***") == ["hr"])
        #expect(outline("___") == ["hr"])
        #expect(outline("- - -") == ["hr"])
        // 只有两个横线不是分隔线（它是个普通段落）。
        #expect(outline("--") == ["p:--"])
        // `- -` 是"一个列表项，内容是 `-`"：记号后确实有一个空格。
        #expect(outline("- -") == ["li0-:-"])
    }

    // MARK: - 段落

    @Test("⚠️ 折行的段落合并成**一个**段落（markdown 里折行不产生新段落）")
    func paragraphsMergeLines() {
        let markdown = """
        第一行
        第二行
        """
        #expect(outline(markdown) == ["p:第一行 第二行"])
    }

    @Test("空行分隔两个段落；空行本身**不产生块**（否则页面上的间距会莫名其妙地大）")
    func blankLinesSeparateParagraphs() {
        let markdown = """
        第一段

        第二段
        """

        #expect(outline(markdown) == ["p:第一段", "p:第二段"])
    }

    @Test("空白输入 ⇒ 没有任何块（不是「一个空段落」）")
    func emptyInputProducesNoBlocks() {
        expectNoBlocks("")
        expectNoBlocks("\n\n\n")
        expectNoBlocks("   \n  \n")
    }

    // MARK: - 行内

    private func spans(_ text: String) -> [MarkdownSpan] {
        MarkdownInline.spans(text)
    }

    @Test("行内代码 / 粗体 / 斜体 / 链接")
    func inlineStyles() {
        #expect(spans("用 `ETag` 缓存") == [
            MarkdownSpan(text: "用 "),
            MarkdownSpan(text: "ETag", style: .code),
            MarkdownSpan(text: " 缓存"),
        ])

        #expect(spans("**很粗**") == [MarkdownSpan(text: "很粗", style: .bold)])
        #expect(spans("*斜的*") == [MarkdownSpan(text: "斜的", style: .italic)])

        guard case let .link(url) = spans("[主页](https://example.com)").first?.style else {
            Issue.record("应当解析成链接")
            return
        }
        #expect(url.absoluteString == "https://example.com")
    }

    @Test("⚠️ `**` 必须先于单个 `*` 判（否则 `**x**` 会被吃成「斜体 + 两个星号」）")
    func doubleAsteriskTakesPriority() {
        #expect(spans("**x**") == [MarkdownSpan(text: "x", style: .bold)])
        #expect(spans("**x**") != [MarkdownSpan(text: "x", style: .italic)])
    }

    @Test("⚠️ 行内代码里的标记符号**不解析**（`` `a_b_c` `` 就是它自己）")
    func inlineCodeIsVerbatim() {
        #expect(spans("`a **b** c`") == [MarkdownSpan(text: "a **b** c", style: .code)])
    }

    @Test("⚠️ 不支持 `_斜体_`：`snake_case_name` 在代码文档里太常见，支持它会把名字吃掉半截")
    func underscoresAreNotEmphasis() {
        #expect(spans("snake_case_name") == [MarkdownSpan(text: "snake_case_name")])
    }

    @Test("⚠️ 行内代码的闭合必须**等长**（只找「下一个反引号」会把 3 个错配成 1 个，吃掉字符）")
    func inlineCodeRequiresMatchingBacktickRunLength() {
        // 三个配三个 ⇒ 中间那段是代码，反引号一个不少。
        let triple = spans("``` swift ``` extra")
        #expect(triple.contains(MarkdownSpan(text: " swift ", style: .code)))
        #expect(MarkdownSpan.plainText(of: triple) == " swift  extra")

        // 单个配不上三个 ⇒ 整串保持字面量（**一个字符都不能少**）。
        #expect(MarkdownSpan.plainText(of: spans("`a`` b")) == "`a`` b")
    }

    @Test("⚠️ 强调内容首尾不能是空格（否则 `2 * 3 * 4` 会被解析成斜体）")
    func emphasisNeedsNonSpaceBoundaries() {
        #expect(spans("2 * 3 * 4") == [MarkdownSpan(text: "2 * 3 * 4")])
    }

    @Test("未配对的标记保持字面量（不吞字符）")
    func unmatchedMarkersStayLiteral() {
        #expect(spans("一个 ` 未闭合") == [MarkdownSpan(text: "一个 ` 未闭合")])
        #expect(spans("**未闭合") == [MarkdownSpan(text: "**未闭合")])
        #expect(spans("[未闭合](") == [MarkdownSpan(text: "[未闭合](")])
    }

    @Test("⚠️ 无效地址当作普通文本（`[a](b c)` 里那一个空格让它不是链接）")
    func invalidLinksStayLiteral() {
        #expect(spans("[点这里](参见 上文)") == [MarkdownSpan(text: "[点这里](参见 上文)")])
    }

    @Test("⚠️ 标记被**消费掉**（文字里不留 `**` / 反引号）；未配对的标记则必须**原样留着**")
    func markersAreConsumedButUnmatchedOnesSurvive() {
        // 配对的：标记消失，只留文字。
        #expect(MarkdownSpan.plainText(of: spans("**粗**")) == "粗")
        #expect(MarkdownSpan.plainText(of: spans("`code`")) == "code")
        #expect(MarkdownSpan.plainText(of: spans("[文字](https://x.y)")) == "文字")
        #expect(MarkdownSpan.plainText(of: spans("前 **粗** 后")) == "前 粗 后")

        // 未配对的：**一个字符都不能少** —— 把 `**未闭合` 渲染成 `未闭合`
        // 等于悄悄改了用户 README 的内容。
        #expect(MarkdownSpan.plainText(of: spans("**未闭合")) == "**未闭合")
        #expect(MarkdownSpan.plainText(of: spans("一个 ` 未闭合")) == "一个 ` 未闭合")
    }

    // MARK: - 辅助

    private func expectNoBlocks(_ markdown: String) {
        #expect(blocks(markdown).isEmpty, "「\(markdown)」不应当产出任何块")
    }
}
