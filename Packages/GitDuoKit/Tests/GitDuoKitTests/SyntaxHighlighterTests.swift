import Foundation
import Testing

@testable import GitDuoKit

/// 轻量词法着色（TECH_SPEC §11.3）。
///
/// ## 最重要的一条：**内容不变量**
///
/// `tokens` 拼起来必须**逐字等于原行**。着色器吞掉一个字符，代码就被改了 ——
/// 而页面上完全看不出来（用户复制出来的是错的、照着它对代码会莫名其妙地不匹配）。
/// 这一条用一组"任意输入"来守，而不是挑几个好看的例子。
@Suite("语法高亮 · 词法 / 语言 / 内容不变量 / 缓存")
struct SyntaxHighlighterTests {

    private func tokens(_ line: String, _ language: CodeLanguage?) -> [SyntaxToken] {
        SyntaxHighlighter.tokens(of: line, language: language)
    }

    private func rejoin(_ line: String, _ language: CodeLanguage?) -> String {
        tokens(line, language).map(\.text).joined()
    }

    // MARK: - 内容不变量

    @Test("⚠️ **任意输入下**，token 拼起来必须等于原行（少一个字符 = 悄悄改了代码）")
    func tokensReconstructTheLine() {
        let samples = [
            "let x = 1",
            "func foo(bar: String) -> Int { return 0 }",
            "// 注释里有 \"引号\" 和 `反引号`",
            "let s = \"未闭合的字符串",
            "/* 未闭合的块注释",
            "中文注释：这是一行没有任何标记的文字",
            "",
            "   ",
            "\\",
            "\"\"\"",
            "1..<5",
            "x = 0x1F + 0b1010 + 1_000_000",
            "@available(iOS 27, *)",
            "$variable # 井号",
        ]

        for language in CodeLanguage.allCases {
            for sample in samples {
                #expect(
                    rejoin(sample, language) == sample,
                    "「\(sample)」在 \(language.rawValue) 下被改动了"
                )
            }
        }
        // 纯文本也一样。
        for sample in samples {
            #expect(rejoin(sample, nil) == sample)
        }
    }

    // MARK: - 词法

    @Test("⚠️ 标识符的**起始**字符必须也满足**后续**字符（不满足 = 扫描器**死循环**）")
    func identifierStartImpliesBody() {
        // 这条断言是 2026-10-07 那次事故的守卫：`@` 曾在起始集合里、
        // 却不在后续集合里 ⇒ `@available(…)` 走进标识符分支后一步都不推进下标
        // ⇒ 死循环 ⇒ **测试进程被系统直接杀掉**（没有失败信息，只有 SIGKILL，
        // 排查时看起来像"环境坏了"）。
        let candidates: [Character] = [
            "a", "Z", "_", "$", "@", "0", "9", "中", "é", "🎉", " ", ".", "-", "/", "\\", "*", "`",
        ]

        for character in candidates where SyntaxHighlighter.isIdentifierStart(character) {
            #expect(
                SyntaxHighlighter.isIdentifierBody(character),
                "「\(character)」是起始字符却不是后续字符 ⇒ 扫描器会死循环"
            )
        }
    }

    @Test("关键字 / 字符串 / 数字")
    func basicTokenKinds() {
        let line = "let name = \"GitDuo\""
        let result = tokens(line, .swift)

        #expect(result.contains(SyntaxToken(text: "let", kind: .keyword)))
        // ⚠️ 字符串 token **含引号** —— 去掉之后字符串的边界看不出来。
        #expect(result.contains(SyntaxToken(text: "\"GitDuo\"", kind: .string)))
    }

    @Test("注释：`//` 之后整行都是注释（含其中的引号与关键字）")
    func lineCommentSwallowsTheRest() {
        let result = tokens("let x = 1 // let y = 2", .swift)

        #expect(result.last?.kind == .comment)
        #expect(result.last?.text == "// let y = 2")
        // 注释里的 `let` 不该被染成关键字。
        #expect(result.filter { $0.kind == .keyword }.count == 1)
    }

    @Test("Python 的注释是 `#`（不是 `//`）")
    func pythonCommentPrefix() {
        #expect(tokens("x = 1  # 注释", .python).last?.kind == .comment)
        #expect(tokens("x = 1  # 注释", .python).last?.text == "# 注释")
    }

    @Test("块注释（同一行内配对）")
    func blockComment() {
        let result = tokens("let x = /* 说明 */ 1", .swift)

        #expect(result.contains(SyntaxToken(text: "/* 说明 */", kind: .comment)))
    }

    @Test("⚠️ 未闭合的块注释**到行尾为止**，不能整段丢掉（丢了就破坏内容不变量）")
    func unclosedBlockCommentRunsToEndOfLine() {
        let line = "let x = /* 没关"
        let result = tokens(line, .swift)

        #expect(result.last?.kind == .comment)
        #expect(rejoin(line, .swift) == line)
    }

    @Test("数字：十进制 / 十六进制 / 下划线分隔 / 小数")
    func numbers() {
        #expect(tokens("x = 42", .swift).contains(SyntaxToken(text: "42", kind: .number)))
        #expect(tokens("x = 0x1F", .swift).contains(SyntaxToken(text: "0x1F", kind: .number)))
        #expect(tokens("x = 1_000", .swift).contains(SyntaxToken(text: "1_000", kind: .number)))
        #expect(tokens("x = 3.14", .swift).contains(SyntaxToken(text: "3.14", kind: .number)))
    }

    @Test("⚠️ 区间运算符 `1..<5` 里的点不吃进数字（否则运算符会被染成数字色）")
    func rangeOperatorIsNotPartOfTheNumber() {
        let result = tokens("for i in 1..<5 {}", .swift)
        let numbers = result.filter { $0.kind == .number }.map(\.text)

        #expect(numbers.contains("1"))
        // `1.` 这种"吃了点的数字"不该出现。
        #expect(numbers.allSatisfy { !$0.hasSuffix(".") })
        #expect(rejoin("for i in 1..<5 {}", .swift) == "for i in 1..<5 {}")
    }

    @Test("函数名：标识符后面紧跟 `(`（允许中间有空格）")
    func functionNames() {
        #expect(tokens("foo()", .swift).contains(SyntaxToken(text: "foo", kind: .function)))
        #expect(tokens("foo (x)", .swift).contains(SyntaxToken(text: "foo", kind: .function)))
        // 关键字即使在 `if (` 这种位置也不该变函数名。
        #expect(tokens("if (x)", .swift).contains(SyntaxToken(text: "if", kind: .keyword)))
    }

    @Test("类型名：首字母大写**且不跟括号**的标识符")
    func typeNames() {
        let result = tokens("let x: String = \"\"", .swift)

        #expect(result.contains(SyntaxToken(text: "String", kind: .type)))
        #expect(result.contains(SyntaxToken(text: "let", kind: .keyword)))
    }

    // MARK: - 语言

    @Test("纯文本（`nil` 语言）⇒ 整行一个 `.plain`，不做任何着色")
    func nilLanguageIsPlainText() {
        let line = "let x = 1 // 注释"
        let result = tokens(line, nil)

        #expect(result == [SyntaxToken(text: line, kind: .plain)])
    }

    @Test("⚠️ `markdown` **不做词法着色**（行首的 `#` 是块级的事，已由 MarkdownParser 处理）")
    func markdownIsPlainText() {
        let line = "# 标题"
        #expect(tokens(line, .markdown) == [SyntaxToken(text: line, kind: .plain)])
    }

    @Test("语言别名：`ts` / `js` / `py` / `rs` / `golang` / `md`")
    func languageAliases() {
        #expect(CodeLanguage.named("ts") == .typescript)
        #expect(CodeLanguage.named("tsx") == .typescript)
        #expect(CodeLanguage.named("js") == .javascript)
        #expect(CodeLanguage.named("py") == .python)
        #expect(CodeLanguage.named("rs") == .rust)
        #expect(CodeLanguage.named("golang") == .go)
        #expect(CodeLanguage.named("md") == .markdown)
        #expect(CodeLanguage.named("Swift") == .swift)
        #expect(CodeLanguage.named(" swift ") == .swift)
    }

    @Test("⚠️ 认不出来的语言返回 `nil`（= 纯文本），**不去猜** —— 猜错比不着色更让人怀疑内容")
    func unknownLanguageIsNil() {
        #expect(CodeLanguage.named("brainfuck") == nil)
        #expect(CodeLanguage.named("") == nil)
        #expect(CodeLanguage.named(nil) == nil)
        // 认不出来 ⇒ 整行一个 plain token（而不是按别的语言规则染一半）。
        let line = "let x = 1"
        #expect(tokens(line, CodeLanguage.named("brainfuck")) == [SyntaxToken(text: line, kind: .plain)])
    }

    // MARK: - 缓存

    @Test("缓存：同一行同一语言取两次结果一致；不同语言**不串味**（语言在缓存键里）")
    func cacheSeparatesLanguages() async {
        let cache = SyntaxHighlightCache()

        let swift = await cache.tokens(of: "let x = 1", language: .swift)
        let plain = await cache.tokens(of: "let x = 1", language: nil)

        // ⚠️ 相同的行、不同的语言 ⇒ 结果必须不同（`let` 在 Swift 是关键字，在纯文本不是）。
        #expect(swift != plain)
        #expect(plain == [SyntaxToken(text: "let x = 1", kind: .plain)])
        #expect(await cache.tokens(of: "let x = 1", language: .swift) == swift)
    }

    @Test("⚠️ 缓存超限时**淘汰最旧的**，且淘汰后结果仍然正确（不是「淘汰了就返回错的东西」）")
    func cacheEvictsOldestAndStaysCorrect() async {
        let cache = SyntaxHighlightCache(limit: 2)

        _ = await cache.tokens(of: "line 1", language: .swift)
        _ = await cache.tokens(of: "line 2", language: .swift)
        #expect(await cache.cachedLineCount == 2)

        _ = await cache.tokens(of: "line 3", language: .swift)
        #expect(await cache.cachedLineCount == 2)

        // 被淘汰的那一行重新算，结果必须与纯函数一致。
        #expect(await cache.tokens(of: "line 1", language: .swift) == SyntaxHighlighter.tokens(of: "line 1", language: .swift))
    }

    @Test("`clear` 清空缓存（登出 / 切账号时用）")
    func cacheClear() async {
        let cache = SyntaxHighlightCache()
        _ = await cache.tokens(of: "x", language: .swift)

        await cache.clear()
        #expect(await cache.cachedLineCount == 0)
    }
}
