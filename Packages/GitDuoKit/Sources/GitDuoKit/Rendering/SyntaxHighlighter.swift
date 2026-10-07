import Foundation

/// 一个词法片段的类别（TECH_SPEC §11.3「关键字 / 字符串 / 注释 / 数字 / 函数名」）。
///
/// ⚠️ **这里只有语义类别，没有颜色** —— 颜色是设计包的活
/// （`GitDuoDesign` 的令牌到 `SyntaxTokenKind` 的映射）。
/// 理由同 §11.2 的结构模型：本包不得 import SwiftUI，而"哪种 token 该是什么色"
/// 是排版决定、会随主题变（本期只做浅色，但将来要补深色）。
public enum SyntaxTokenKind: Sendable, Hashable {

    /// 普通文字（**兜底**）。
    case plain

    case keyword

    /// 字符串字面量（含引号 —— 引号去掉后字符串的边界看不出来）。
    case string

    case comment

    case number

    /// 函数 / 方法名（**启发式**：标识符后面紧跟 `(`）。
    case function

    /// 类型名（**启发式**：首字母大写的标识符）。
    case type
}

/// 一段着色后的文字。
public struct SyntaxToken: Sendable, Hashable {

    /// 原文片段（**拼接起来必须等于原行**，一个字符都不多不少）。
    ///
    /// ⚠️ 这条不变量很重要：视图是"把这些片段依次画出来"，
    /// 若着色器吞掉了某个字符（例如把引号丢了），代码就会**被悄悄改掉**——
    /// 而用户复制它、或照着它对代码时，会得到一段不存在的源码。
    public let text: String

    public let kind: SyntaxTokenKind

    public init(text: String, kind: SyntaxTokenKind) {
        self.text = text
        self.kind = kind
    }
}

/// 认得出的语言（TECH_SPEC §11.3「先支持少量高频语言，其余降级为纯文本」）。
public enum CodeLanguage: String, Sendable, CaseIterable {

    case swift
    case rust
    case typescript
    case javascript
    case python
    case go
    case json
    case markdown

    /// 从代码块 fence 的 info string 认语言。
    ///
    /// ⚠️ **认不出来一律返回 `nil`（= 纯文本）**，不去猜：
    /// 猜错的语言会按错的规则着色（把 Go 的 `` `raw` `` 当字符串、把 Python 的 `#`
    /// 当运算符），那种"着色错了"比"没有着色"更让人怀疑内容本身。
    ///
    /// 别名表只收真实出现率高的那几个 —— 列长了维护不动，而漏掉一个别名
    /// 的后果只是"这个代码块没有颜色"。
    public static func named(_ info: String?) -> CodeLanguage? {
        guard let info else { return nil }
        let key = info.trimmingCharacters(in: .whitespaces).lowercased()
        if let direct = CodeLanguage(rawValue: key) { return direct }
        switch key {
        case "rs": return .rust
        case "ts", "tsx", "mts", "cts": return .typescript
        case "js", "jsx", "mjs", "cjs", "node": return .javascript
        case "py", "python3": return .python
        case "golang": return .go
        case "jsonc", "json5": return .json
        case "md", "mdown", "mkd": return .markdown
        default: return nil
        }
    }
}

/// 轻量词法着色 —— TECH_SPEC §11.3。
///
/// ## ⚠️ 它是**逐行**的，因此对跨行结构无能为力
///
/// §11.3 明写"逐行着色"，这个取舍的后果要说清楚：
/// - `/* 这里开始` … 若干行 … `到这里结束 */` —— **中间几行会被当成普通代码**；
/// - Python / Swift 的多行字符串（`"""`）—— 同上。
///
/// 要正确就得维护"跨行状态"（每一行的结果依赖前面所有行），
/// 而那会让"只对可见区域着色"（§11.3 的性能一行）失效 ——
/// 长文件里滚到中间某一屏时，必须先扫完前面所有行才知道自己处在什么状态里。
/// 两害相权，取"逐行独立"，代价是跨行结构着色不准（**内容仍然逐字正确**，
/// 只是颜色不对，而颜色不对不会让人读错代码）。
///
/// ## 内容不变量
///
/// 无论输入多奇怪，`tokens` 拼起来**恒等于原行**。
/// 这条由 `SyntaxHighlighterTests` 的一组"任意输入"用例守着 ——
/// 着色器吃掉一个字符，代码就被改了，而页面上看不出来。
public enum SyntaxHighlighter {

    /// 把一行拆成带类别的片段。
    ///
    /// - Parameter language: `nil` = 纯文本（整行一个 `.plain`）。
    public static func tokens(of line: String, language: CodeLanguage?) -> [SyntaxToken] {
        guard let language, !line.isEmpty else {
            return line.isEmpty ? [] : [SyntaxToken(text: line, kind: .plain)]
        }
        guard let rules = Rules.for(language) else {
            return [SyntaxToken(text: line, kind: .plain)]
        }
        return scan(line, rules: rules)
    }

    // MARK: - 扫描

    private static func scan(_ line: String, rules: Rules) -> [SyntaxToken] {
        let characters = Array(line)
        var tokens: [SyntaxToken] = []
        var index = 0

        /// 累积一段同类文字 —— 不逐个字符产出 token，
        /// 否则一行 `let x` 会变成 5 个 token，视图的 `Text` 拼接长度翻倍。
        func append(_ text: String, _ kind: SyntaxTokenKind) {
            guard !text.isEmpty else { return }
            if let last = tokens.last, last.kind == kind {
                tokens[tokens.count - 1] = SyntaxToken(text: last.text + text, kind: kind)
            } else {
                tokens.append(SyntaxToken(text: text, kind: kind))
            }
        }

        while index < characters.count {
            // ⚠️ **下标必须每一轮都推进**，否则这里是一个**死循环** ——
            //    而它的症状不是"某个测试失败"，是**整个测试进程被系统杀掉**
            //    （0.2 秒内吃满 CPU 与内存）。这一条 `defer` 是兜底：
            //    以后再加分支、忘了推进下标时，最坏结果是"少染一个字符"，
            //    而不是"跑不动"。2026-10-07 真的踩过一次（`@` 开头的标识符分支）。
            let iterationStart = index
            defer {
                if index == iterationStart { index += 1 }
            }

            // ① 行注释 —— **最先判**：它会把本行剩下的一切都吃掉。
            if let prefix = rules.lineComment, matches(prefix, in: characters, at: index) {
                append(String(characters[index...]), .comment)
                break
            }

            // ② 块注释（同一行内配对；跨行部分见类型说明）
            if let block = rules.blockComment, matches(block.open, in: characters, at: index) {
                let start = index
                index += block.open.count
                var closed = false
                while index < characters.count {
                    if matches(block.close, in: characters, at: index) {
                        index += block.close.count
                        closed = true
                        break
                    }
                    index += 1
                }
                // ⚠️ **未闭合也要产出 token**（到行尾为止）：不产出就等于把这段注释
                //    从输出里丢掉，而"拼起来等于原行"这条不变量会被破坏。
                _ = closed
                append(String(characters[start..<index]), .comment)
                continue
            }

            let character = characters[index]

            // ③ 字符串（同一行内找配对的引号）
            if rules.stringDelimiters.contains(character) {
                let start = index
                index += 1
                while index < characters.count {
                    let current = characters[index]
                    if current == "\\" && rules.supportsEscape {
                        index += 2
                        continue
                    }
                    if current == character { index += 1; break }
                    // ⚠️ 不跨行：一行结束就停（逐行着色的固有边界）。
                    index += 1
                }
                append(String(characters[start..<min(index, characters.count)]), .string)
                continue
            }

            // ④ 数字
            if character.isNumber {
                let start = index

                // 进制前缀（`0x1F` / `0b1010` / `0o777`）单独走一条：
                // ⚠️ `x` 不是十六进制数字（`isHexDigit` 为假），
                //    不特判的话 `0x1F` 会被切成 `0` + 标识符 `x1F` ——
                //    一个数字被染成"数字 + 类型名"，而页面上看不出这是错的。
                if character == "0", index + 1 < characters.count,
                   "xXbBoO".contains(characters[index + 1]) {
                    index += 2
                    while index < characters.count,
                          characters[index].isHexDigit || characters[index] == "_" {
                        index += 1
                    }
                } else {
                    while index < characters.count {
                        let current = characters[index]
                        if current.isNumber || current == "_" { index += 1; continue }
                        if current == "." {
                            // ⚠️ 不吃**连续的两个点**：`1..<5` 里的 `..` 是区间运算符，
                            //    吃进去会把运算符染成数字色，而且 `1..` 本身不是一个数。
                            if index + 1 < characters.count, characters[index + 1] == "." { break }
                            index += 1
                            continue
                        }
                        break
                    }
                }

                append(String(characters[start..<index]), .number)
                continue
            }

            // ⑤ 标识符（关键字 / 函数 / 类型 / 普通）
            if Self.isIdentifierStart(character) {
                let start = index
                while index < characters.count, Self.isIdentifierBody(characters[index]) { index += 1 }
                let word = String(characters[start..<index])

                if rules.keywords.contains(word) {
                    append(word, .keyword)
                } else if nextNonSpace(characters, from: index) == "(" {
                    append(word, .function)
                } else if let first = word.first, first.isUppercase {
                    append(word, .type)
                } else {
                    append(word, .plain)
                }
                continue
            }

            // ⑥ 其余：单字符普通文字
            append(String(character), .plain)
            index += 1
        }

        return tokens
    }

    // MARK: - 辅助

    /// 标识符的**起始**字符。
    static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_" || character == "$" || character == "@"
    }

    /// 标识符的**后续**字符。
    ///
    /// ⚠️ **必须包含 `isIdentifierStart` 的全部字符**。2026-10-07 这里漏了 `@`
    /// ⇒ `@available(…)` 走到标识符分支时，`while` 一步都不走、`index` 原地不动
    /// ⇒ 死循环 ⇒ 测试进程被系统直接杀掉（**没有任何失败信息**，只有 SIGKILL）。
    /// 两个集合的关系由 `SyntaxHighlighterTests` 的一条断言守着。
    static func isIdentifierBody(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }

    /// `needle` 是否从 `index` 处开始。
    ///
    /// ⚠️ 不能用 `line.hasPrefix` 直接在 `String` 上比对 —— 调用点手里是
    /// `[Character]` 与下标，混用 `String.Index` 与整数下标是本文件最容易出错的地方，
    /// 所以统一在字符数组上比。
    private static func matches(_ needle: String, in characters: [Character], at index: Int) -> Bool {
        let target = Array(needle)
        guard index + target.count <= characters.count else { return false }
        for offset in 0..<target.count {
            if characters[index + offset] != target[offset] { return false }
        }
        return true
    }

    /// 跳过空格，看下一个非空格字符（`func foo (` 这种带空格的情况也能认出函数名）。
    private static func nextNonSpace(_ characters: [Character], from index: Int) -> Character? {
        var cursor = index
        while cursor < characters.count {
            if !characters[cursor].isWhitespace { return characters[cursor] }
            cursor += 1
        }
        return nil
    }

    /// 一种语言的着色规则（关键字表 + 注释 / 字符串记号）。
    struct Rules {

        let keywords: Set<String>
        let lineComment: String?
        let blockComment: (open: String, close: String)?
        let stringDelimiters: Set<Character>
        let supportsEscape: Bool

        /// `nil` = 该语言不做词法着色（`markdown` —— 见下）。
        static func `for`(_ language: CodeLanguage) -> Rules? {
            switch language {
            case .swift:
                Rules(keywords: swift, lineComment: "//", blockComment: ("/*", "*/"),
                      stringDelimiters: ["\""], supportsEscape: true)
            case .rust:
                Rules(keywords: rust, lineComment: "//", blockComment: ("/*", "*/"),
                      stringDelimiters: ["\""], supportsEscape: true)
            case .typescript:
                Rules(keywords: typescript, lineComment: "//", blockComment: ("/*", "*/"),
                      stringDelimiters: ["\"", "'", "`"], supportsEscape: true)
            case .javascript:
                Rules(keywords: javascript, lineComment: "//", blockComment: ("/*", "*/"),
                      stringDelimiters: ["\"", "'", "`"], supportsEscape: true)
            case .python:
                Rules(keywords: python, lineComment: "#", blockComment: nil,
                      stringDelimiters: ["\"", "'"], supportsEscape: true)
            case .go:
                Rules(keywords: go, lineComment: "//", blockComment: ("/*", "*/"),
                      stringDelimiters: ["\"", "`"], supportsEscape: true)
            case .json:
                // ⚠️ JSON 没有注释语法，因此 `lineComment` 为 `nil` ——
                //    给了 `//` 会把 `"https://x"` 之外的东西也染成注释（真实例子：
                //    一个 JSON 值里出现 `//` 是非法但可能存在的），
                //    而"把合法的 JSON 染成注释色"比"不染"更糟。
                Rules(keywords: json, lineComment: nil, blockComment: nil,
                      stringDelimiters: ["\""], supportsEscape: true)
            case .markdown:
                // ⚠️ **Markdown 不做词法着色**：它的"关键字"是行首的 `#`、`>`、`-`，
                //    而那是**块级**的事，已经由 `MarkdownParser` 处理过一轮。
                //    在这里再按行内记号染一遍，会把 `# 标题` 里的 `#` 染成注释色、
                //    与块级渲染出来的标题样式打架。
                nil
            }
        }

        // MARK: 关键字表

        // ⚠️ 这些表**不追求完整**（§11.3 明写"非完整语法分析"）。
        //    漏一个关键字的后果是"它没有被染成关键字色"，用户读代码不受影响；
        //    而表越长越容易把**非关键字**收进来（例如把 `get`/`set` 当通用关键字，
        //    它们在很多语言里是普通方法名），那会让一屏普通的代码花掉。
        private static let swift: Set<String> = [
            "actor", "any", "as", "associatedtype", "async", "await", "borrowing", "break",
            "case", "catch", "class", "consuming", "continue", "convenience",
            "default", "defer", "deinit", "didSet", "do", "dynamic", "else", "enum",
            "extension", "fallthrough", "false", "fileprivate", "final", "for", "func",
            "get", "guard", "if", "import", "in", "indirect", "init", "inout", "internal",
            "is", "isolated", "lazy", "let", "mutating", "nil", "nonisolated", "nonmutating",
            "open", "operator", "override", "package", "private", "protocol", "public",
            "repeat", "required", "rethrows", "return", "self", "set", "some", "static",
            "struct", "subscript", "super", "switch", "throw", "throws", "true", "try",
            "typealias", "unowned", "var", "weak", "where", "while", "willSet",
        ]

        private static let rust: Set<String> = [
            "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
            "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop",
            "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static",
            "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while",
        ]

        private static let typescript: Set<String> = [
            "abstract", "any", "as", "async", "await", "boolean", "break", "case", "catch",
            "class", "const", "continue", "declare", "default", "delete", "do", "else",
            "enum", "export", "extends", "false", "finally", "for", "from", "function",
            "if", "implements", "import", "in", "instanceof", "interface", "is", "keyof",
            "let", "namespace", "never", "new", "null", "number", "object", "of", "private",
            "protected", "public", "readonly", "return", "static", "string", "super",
            "switch", "this", "throw", "true", "try", "type", "typeof", "undefined",
            "unknown", "var", "void", "while", "yield",
        ]

        private static let javascript: Set<String> = [
            "async", "await", "break", "case", "catch", "class", "const", "continue",
            "debugger", "default", "delete", "do", "else", "export", "extends", "false",
            "finally", "for", "from", "function", "if", "import", "in", "instanceof", "let",
            "new", "null", "of", "return", "static", "super", "switch", "this", "throw",
            "true", "try", "typeof", "undefined", "var", "void", "while", "yield",
        ]

        private static let python: Set<String> = [
            "and", "as", "assert", "async", "await", "break", "class", "continue", "def",
            "del", "elif", "else", "except", "False", "finally", "for", "from", "global",
            "if", "import", "in", "is", "lambda", "None", "nonlocal", "not", "or", "pass",
            "raise", "return", "True", "try", "while", "with", "yield",
        ]

        private static let go: Set<String> = [
            "any", "append", "bool", "break", "byte", "cap", "case", "chan", "const",
            "continue", "default", "defer", "else", "error", "fallthrough", "false",
            "float64", "for", "func", "go", "goto", "if", "import", "int", "int64",
            "interface", "len", "make", "map", "new", "nil", "package", "range", "return",
            "rune", "select", "string", "struct", "switch", "true", "type", "var",
        ]

        private static let json: Set<String> = ["true", "false", "null"]
    }
}

/// 逐行着色的**结果缓存**（TECH_SPEC §11.3「逐行着色 + 结果缓存」）。
///
/// ## 为什么需要它
///
/// SwiftUI 会因滚动、状态变化而重复求值同一行的视图体。
/// 着色是纯计算，但一次长文件滚动能让同一批行被反复扫描几十次 ——
/// 缓存把这件事从"每次 O(行长度)"降成一次哈希查找。
///
/// ## 为什么放在领域层而不是 App 层
///
/// 它是一个**策略**（缓存什么键、多大、怎么淘汰），不是排版；
/// 而 App target 没有测试 target，淘汰逻辑写错只会表现为"越用越慢"，
/// 那种问题在真机上极难定位。放这里至少能被单测钉住上限行为。
public actor SyntaxHighlightCache {

    private var storage: [String: [SyntaxToken]] = [:]

    /// 插入顺序（用于淘汰最旧的一条）——`Dictionary` 本身不保证顺序。
    private var order: [String] = []

    private let limit: Int

    /// - Parameter limit: 最多缓存多少行。默认 2,000 行 ——
    ///   按一行 80 字符、一个 token 约 40 字节粗估，上限约几百 KB；
    ///   而屏幕上的可见行数只有几十，长文件滚动时的命中率已经足够。
    public init(limit: Int = 2_000) {
        self.limit = max(1, limit)
    }

    /// 取（必要时才算）某一行的着色结果。
    public func tokens(of line: String, language: CodeLanguage?) -> [SyntaxToken] {
        let key = Self.key(line: line, language: language)
        if let cached = storage[key] { return cached }

        let computed = SyntaxHighlighter.tokens(of: line, language: language)
        storage[key] = computed
        order.append(key)

        // 淘汰最旧的一条（**一次只淘汰一条**：本函数的调用是逐行的，
        // 一次淘汰一批会让刚滚过去的那几行立刻又要重算）。
        if order.count > limit, let oldest = order.first {
            order.removeFirst()
            storage[oldest] = nil
        }
        return computed
    }

    public func clear() {
        storage.removeAll()
        order.removeAll()
    }

    /// 当前缓存了多少行。
    ///
    /// **internal（不是 public）**：它只服务单测对淘汰行为的断言，
    /// 对 App 层没有任何用处 —— 开放成 `public` 会让"缓存里现在有几行"
    /// 变成一个有人的依赖，而那是纯实现细节。
    var cachedLineCount: Int { storage.count }

    /// 缓存键 = 语言 + 行内容。
    ///
    /// ⚠️ **语言必须进键**：同一行 `let x = 1` 在 Swift 与在纯文本下的着色不同，
    /// 少了语言就会让"先看了一个 Swift 代码块、再看一个无语言的代码块"
    /// 拿到同一份结果 —— 而那一份是错的那个。
    /// 分隔符用 `\u{0}`（不可能出现在源码里的字符），避免"语言名 + 行内容"拼出歧义键。
    private static func key(line: String, language: CodeLanguage?) -> String {
        "\(language?.rawValue ?? "")\u{0}\(line)"
    }
}
