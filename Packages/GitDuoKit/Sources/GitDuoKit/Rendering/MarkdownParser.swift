import Foundation

/// 块级 Markdown 解析器 —— TECH_SPEC §11.1。
///
/// ## 为什么自研
///
/// §11.1 的「注意」已写明：`AttributedString(markdown:)` 的系统能力
/// **对块级结构支持有限**（它会尽力而为地渲染，但拿不到"这是一个几级标题"
/// "这是代码块的第几行"这类信息，而 README 与文件查看页都要按块排版）。
/// 本项目又是零第三方依赖（决策 #12）⇒ 只能自研，且**必须可单测**。
///
/// ## 扫描方式：按行 → 判定块 → 行内解析
///
/// 三趟的顺序不能换：
/// 1. **按行拆**（`\r\n` 归一）；
/// 2. **块类型判定**（代码块 fence / 分隔线 / 标题 / 引用 / 列表 / 段落）；
/// 3. **行内解析**（`MarkdownInline`）。
///
/// 顺序若反了（先做行内解析），代码块里的 `**` 与 `#` 会被当标记吃掉 ——
/// 而"代码块内部的一切都是原文"正是 §11.1 要求用单测覆盖的第一个边界。
public enum MarkdownParser {

    /// 解析成块序列。空行不产生块。
    public static func blocks(from markdown: String) -> [MarkdownBlock] {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var blocks: [MarkdownBlock] = []
        var index = 0
        // 列表嵌套深度用"缩进栈"算，不用 `缩进 / 2`：
        // markdown 里 2 空格与 4 空格缩进都有人写，除法会把两者算成不同层级；
        // 栈只关心"比上一层深还是浅"，与具体用了几个空格无关。
        var indentStack: [Int] = []

        while index < lines.count {
            let line = lines[index]
            let content = line.trimmingCharacters(in: .whitespaces)

            // 空行：跳过。⚠️ 不产出空块 —— 空块会让视图画出多余的垂直间距。
            if content.isEmpty {
                index += 1
                continue
            }

            // ① 代码块 fence —— 必须在其它判定之前：它是唯一会"吞掉后续所有行"的块。
            if let fence = Fence(line: content) {
                var body: [String] = []
                index += 1
                while index < lines.count, !fence.closes(lines[index].trimmingCharacters(in: .whitespaces)) {
                    body.append(lines[index])
                    index += 1
                }
                // 跳过收尾 fence（**未闭合时不跳** —— 直接取到文末，见下）
                if index < lines.count { index += 1 }
                blocks.append(.codeBlock(language: fence.language, lines: body))
                indentStack.removeAll()
                continue
            }

            // ② 分隔线
            if Self.isDivider(content) {
                blocks.append(.divider)
                index += 1
                indentStack.removeAll()
                continue
            }

            // ③ 标题
            if let heading = Self.heading(content) {
                blocks.append(.heading(level: heading.level, spans: MarkdownInline.spans(heading.text)))
                index += 1
                indentStack.removeAll()
                continue
            }

            // ④ 引用
            if content.hasPrefix(">") {
                let quoted = String(content.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(MarkdownInline.spans(quoted)))
                index += 1
                indentStack.removeAll()
                continue
            }

            // ④.5 HTML 块（2026-10-07 目视发现的第 2 条：真实 README 大量用 HTML）。
            //
            //      ⚠️ 必须排在**列表与段落之前**：`<p align="center">` 那一行
            //      既不是段落也不是列表，而它后面的若干行（`<img>` / `</p>`）
            //      都属于同一块。收尾条件是**空行**，不是 `</div>` ——
            //      这正是 CommonMark 6 / 7 型块的规定，也与 README 的实际写法吻合
            //      （`<details>` 里夹一段 markdown 表格，中间就有空行）。
            if Self.htmlBlockStart(content) {
                // ⚠️ **起始那一行也要收进来**。少了它，`<h1>标题</h1>` 这种
                //    单行 HTML 会整行消失 —— 而多行输入里这个 bug 是隐形的
                //    （起始行通常只是一个纯标签，转换之后本来就是空串）。
                var htmlLines: [String] = [content]
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    htmlLines.append(lines[index].trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                // ⚠️ 改写 + 再解析，而不是在本文件里直接产块：块判定 / 行内解析 /
                //    实体 / 列表缩进栈全部复用同一条路（见 `MarkdownHTML`）。
                blocks.append(contentsOf: MarkdownHTML.blocks(from: htmlLines.joined(separator: "\n")))
                indentStack.removeAll()
                continue
            }

            // ⑤ 列表项
            if let item = Self.listItem(line) {
                let depth = Self.depth(forIndent: item.indent, stack: &indentStack)
                var itemLines = [item.text]
                index += 1
                // 续行：缩进不比本项浅、且自身不是新的块起始 ⇒ 并入本项。
                // ⚠️ 不并入的话，一个折行的列表项会被显示成"列表项 + 一个孤零零的段落"。
                while index < lines.count {
                    let next = lines[index]
                    let nextContent = next.trimmingCharacters(in: .whitespaces)
                    if nextContent.isEmpty || Self.isBlockStart(nextContent) { break }
                    if Self.leadingIndent(next) < item.indent { break }
                    itemLines.append(nextContent)
                    index += 1
                }
                blocks.append(
                    .listItem(
                        ordered: item.ordered,
                        number: item.number,
                        depth: depth,
                        checked: item.checked,
                        spans: MarkdownInline.spans(itemLines.joined(separator: " "))
                    )
                )
                continue
            }

            // ⑥ 段落：连续行合并成**一个**段落（markdown 里折行不产生新段落）。
            var paragraphLines = [content]
            index += 1
            while index < lines.count {
                let nextContent = lines[index].trimmingCharacters(in: .whitespaces)
                if nextContent.isEmpty || Self.isBlockStart(nextContent) { break }
                paragraphLines.append(nextContent)
                index += 1
            }
            blocks.append(.paragraph(MarkdownInline.spans(paragraphLines.joined(separator: " "))))
            indentStack.removeAll()
        }

        // 去掉"解析出来但什么都没有"的块（例如一行只有 `> `）。
        return blocks.filter { !$0.isEmpty }
    }

    // MARK: - 块判定

    /// 这一行是不是**某个块的起始**（段落收集时用来断句）。
    ///
    /// ⚠️ 它与主循环里的判定必须**同源**：两处各写一套，
    /// 迟早出现"主循环认为是段落、这里认为是列表"的行，表现为
    /// "某一行莫名从段落里掉出来变成独立一行"。
    static func isBlockStart(_ content: String) -> Bool {
        Fence(line: content) != nil
            || isDivider(content)
            || heading(content) != nil
            || content.hasPrefix(">")
            || htmlBlockStart(content)
            || listItem(content) != nil
    }

    /// 这一行是不是 **HTML 块的起始**（CommonMark 的 6 / 7 型，简化版）。
    ///
    /// 判据是"看起来像起始标签"：`<` + 可选 `/` + 字母开头的标签名，
    /// 且标签名之后紧跟着 `>` / `/` / 空白。
    /// 最后那一条专为把 `<https://example.com>` 挡在外面 —— 它的"标签名"后面
    /// 跟的是 `:`，而那是正文里的一个网址。
    static func htmlBlockStart(_ content: String) -> Bool {
        guard content.hasPrefix("<") else { return false }
        if content.hasPrefix("<!--") { return true }

        // ⚠️ 必须**同一行里有收尾的 `>`**。少了这一条，一行残缺的 `<b`
        //    会被当成 HTML 块，而 `MarkdownHTML` 处理不了它（不是标签）、原样返回，
        //    下一趟又被判定成 HTML 块 ⇒ **递归不收敛**。
        guard content.contains(">") else { return false }

        var rest = content.dropFirst()
        if rest.hasPrefix("/") { rest = rest.dropFirst() }
        guard let first = rest.first, first.isLetter else { return false }

        let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "-" }
        guard let next = rest.dropFirst(name.count).first else { return true }
        return next == ">" || next == "/" || next.isWhitespace
    }

    /// `---` / `***` / `___`（至少三个同类字符，其间允许空格）。
    static func isDivider(_ content: String) -> Bool {
        let stripped = content.filter { !$0.isWhitespace }
        guard stripped.count >= 3 else { return false }
        guard let first = stripped.first, first == "-" || first == "*" || first == "_" else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    /// `#` 到 `######` + 一个空格 + 标题文字。
    ///
    /// ⚠️ **要求 `#` 后面有空格**（CommonMark 的规则）：否则 `#hashtag` 会变成一级标题，
    /// 而它在 README 里是常见写法（Issue 引用、标签）。同理 `#######`（7 个）不是标题。
    static func heading(_ content: String) -> (level: Int, text: String)? {
        let hashes = content.prefix { $0 == "#" }
        let level = hashes.count
        guard (1...6).contains(level) else { return nil }
        let rest = content.dropFirst(level)
        guard rest.first == " " || rest.isEmpty else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    /// 列表项：`- ` / `* ` / `+ ` / `1. ` / `1) `，可带任务列表勾选框。
    static func listItem(_ line: String) -> (ordered: Bool, number: Int?, indent: Int, checked: Bool?, text: String)? {
        let indent = leadingIndent(line)
        let body = line.dropFirst(min(indent, line.count))
        guard !body.isEmpty else { return nil }

        var ordered = false
        var number: Int?
        var rest = Substring(body)

        if let first = body.first, first == "-" || first == "*" || first == "+" {
            let after = body.dropFirst()
            // 标记后必须是空格或直接结束（`-foo` 不是列表，是文字里的破折号）。
            guard after.isEmpty || after.first == " " else { return nil }
            rest = after
        } else {
            // 有序标记：数字 + `.` 或 `)`。⚠️ 最多 9 位（避免把 `2024.05.01` 这种日期当列表）。
            let digits = body.prefix { $0.isNumber }
            guard !digits.isEmpty, digits.count <= 9 else { return nil }
            let afterDigits = body.dropFirst(digits.count)
            guard let separator = afterDigits.first, separator == "." || separator == ")" else { return nil }
            let after = afterDigits.dropFirst()
            guard after.isEmpty || after.first == " " else { return nil }
            ordered = true
            number = Int(digits)
            rest = after
        }

        var text = rest.trimmingCharacters(in: .whitespaces)

        // 任务列表：`[ ]` / `[x]` / `[X]` + 空格。
        var checked: Bool?
        if text.hasPrefix("[") {
            let marks = text.dropFirst()
            if let marker = marks.first, marker == " " || marker == "x" || marker == "X" {
                let afterMarker = marks.dropFirst()
                if let bracket = afterMarker.first, bracket == "]" {
                    let after = afterMarker.dropFirst()
                    if after.isEmpty || after.first == " " {
                        checked = marker != " "
                        text = after.trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }

        return (ordered, number, indent, checked, text)
    }

    /// 前导缩进 —— 空格记 1、tab 记 4（tab 在许多编辑器里即 4 空格）。
    static func leadingIndent(_ line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " { count += 1 }
            else if character == "\t" { count += 4 }
            else { break }
        }
        return count
    }

    /// 缩进栈算出嵌套深度（第一层为 0）。
    ///
    /// 规则：比栈顶深 ⇒ 压栈（新的一层）；比栈顶浅 ⇒ 弹到合适的层；相等 ⇒ 同层。
    static func depth(forIndent indent: Int, stack: inout [Int]) -> Int {
        while let top = stack.last, indent < top { stack.removeLast() }
        if let top = stack.last {
            if indent > top { stack.append(indent) }
        } else {
            stack.append(indent)
        }
        return max(0, stack.count - 1)
    }

    /// 代码块围栏（```` ``` ```` 或 `~~~`，至少三个）。
    struct Fence {

        let marker: Character
        let count: Int
        let language: String?

        /// 这一行是不是围栏的**开头**。
        ///
        /// ⚠️ 围栏必须**顶格**（允许最多 3 个前导空格，CommonMark 的规则）——
        /// 缩进更深的 ```` ``` ```` 是列表项里的代码块，本解析器不处理那种情形，
        /// 但也不能把它当成顶格的围栏，否则会把后面一大片正文都吞进代码块。
        init?(line: String) {
            let indent = MarkdownParser.leadingIndent(line)
            guard indent <= 3 else { return nil }
            let body = line.dropFirst(indent)
            guard let first = body.first, first == "`" || first == "~" else { return nil }
            let marks = body.prefix { $0 == first }
            guard marks.count >= 3 else { return nil }
            // 反引号围栏的 info string 里**不许再有反引号**（CommonMark），
            // 否则 `` ``` `` 后面跟一段行内代码会被误当语言名。
            let info = body.dropFirst(marks.count).trimmingCharacters(in: .whitespaces)
            if first == "`" && info.contains("`") { return nil }
            self.marker = first
            self.count = marks.count
            self.language = info.isEmpty ? nil : info.split(separator: " ").first.map(String.init)
        }

        /// 这一行能不能**收尾**：同种字符且不少于开头那么多个（CommonMark）。
        func closes(_ content: String) -> Bool {
            guard let first = content.first, first == marker else { return false }
            let marks = content.prefix { $0 == marker }
            guard marks.count >= count else { return false }
            // 收尾行后面不许有别的内容。
            return content.dropFirst(marks.count).trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}

/// 行内解析（TECH_SPEC §11.1「行内代码 / 链接 / 粗斜体」）。
///
/// 逐字符扫描、遇标记才切换样式，其余时间累积普通文本。
/// 不引入正则：**零第三方依赖**，而 `NSRegularExpression` 的错误是运行时的
/// （模式写错在编译期看不出来，只会在某个输入上静默漏匹配）。
public enum MarkdownInline {

    /// 解析一段行内文本。
    ///
    /// 支持的标记与**明确不支持的**：
    /// - 支持：`` `代码` `` · `**粗体**` · `*斜体*` · `[文字](地址)`
    /// - 不支持嵌套（见 `MarkdownSpan` 的类型说明）；
    /// - ⚠️ **不支持 `_斜体_`**：`snake_case_name` 与 `a_b_c` 在代码文档里太常见，
    ///   支持 `_` 会让它们在渲染时被吃掉半截、变成"斜体 + 下划线消失"。
    ///   CommonMark 用一整套"左右侧边界字符"规则来处理它，而本项目的 README 里
    ///   用 `_` 强调的概率远低于出现 `snake_case` 的概率 —— 取这一侧。
    public static func spans(_ text: String) -> [MarkdownSpan] {
        let characters = Array(text)
        var result: [MarkdownSpan] = []
        var buffer = ""
        var index = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            result.append(MarkdownSpan(text: buffer))
            buffer = ""
        }

        while index < characters.count {
            let character = characters[index]

            // ① 行内代码 —— **第一优先**：代码里的 `**` 与 `[]()` 都是原文。
            //
            // ⚠️ 闭合必须是**等长的反引号串**（CommonMark 的规则）。
            //    只找"下一个反引号"会把 `` ``` `` 错配成"第一个 ` 与第二个 `"，
            //    于是 `` ``` swift ``` extra `` 里的反引号被吃掉两个 ——
            //    **内容被改了，而页面上看不出来**（用户复制出来的是错的）。
            if character == "`" {
                let runLength = runLength(of: "`", in: characters, from: index)
                let contentStart = index + runLength
                if let close = firstIndex(ofRun: "`", length: runLength, in: characters, from: contentStart) {
                    flush()
                    result.append(MarkdownSpan(text: String(characters[contentStart..<close]), style: .code))
                    index = close + runLength
                    continue
                }
            }

            // ② 粗体（`**` 必须先于单 `*` 判，否则 `**x**` 会被吃成"斜体 + 星号"）。
            if character == "*", index + 1 < characters.count, characters[index + 1] == "*" {
                if let close = firstIndex(ofSequence: ["*", "*"], in: characters, from: index + 2), close > index + 2 {
                    let inner = String(characters[(index + 2)..<close])
                    if isEmphasisBody(inner) {
                        flush()
                        result.append(MarkdownSpan(text: inner, style: .bold))
                        index = close + 2
                        continue
                    }
                }
            }

            // ③ 斜体（只认 `*`）。
            if character == "*", index + 1 < characters.count {
                if let close = firstIndex(of: "*", in: characters, from: index + 1), close > index + 1 {
                    let inner = String(characters[(index + 1)..<close])
                    if isEmphasisBody(inner) {
                        flush()
                        result.append(MarkdownSpan(text: inner, style: .italic))
                        index = close + 1
                        continue
                    }
                }
            }

            // ④ 链接 `[文字](地址)`
            if character == "[", let link = parseLink(characters, at: index) {
                flush()
                result.append(MarkdownSpan(text: link.label, style: .link(link.url)))
                index = link.next
                continue
            }

            buffer.append(character)
            index += 1
        }

        flush()
        return result
    }

    // MARK: - 内部

    /// 强调内容的两条边界（CommonMark 的"左/右侧成对"规则的简化版）：
    /// **首尾不能是空格**，且**不能为空**。
    ///
    /// 少了它，`2 * 3 * 4`（乘号）会被解析成斜体的 ` 3 `；
    /// 而 `a*b*` 里那个开头紧贴字母的 `*` 在强调里是**不合法**的 ——
    /// 不过本条只挡空格，字母紧贴仍然会被吃（`a*b*` ⇒ `a` + 斜体 `b`）。
    /// 那一步需要完整的 Unicode 左侧/右侧边界判定，超出本期范围，已登记。
    private static func isEmphasisBody(_ inner: String) -> Bool {
        guard !inner.isEmpty else { return false }
        guard let first = inner.first, !first.isWhitespace else { return false }
        guard let last = inner.last, !last.isWhitespace else { return false }
        return true
    }

    private static func firstIndex(of target: Character, in characters: [Character], from start: Int) -> Int? {
        var index = start
        while index < characters.count {
            if characters[index] == target { return index }
            index += 1
        }
        return nil
    }

    /// 从 `index` 起连续同一个字符的个数（`runLength(of: "`", ...)` ⇒ 反引号串的长度）。
    static func runLength(of target: Character, in characters: [Character], from index: Int) -> Int {
        var cursor = index
        while cursor < characters.count, characters[cursor] == target { cursor += 1 }
        return cursor - index
    }

    /// 找**正好 `length` 个**连续字符的起点 —— 行内代码的闭合标记必须与开头等长。
    ///
    /// ⚠️ 比它更长的一串也**不算**匹配（`` `` `` 不能给 `` ` `` 收尾）：
    /// 那正是 CommonMark 规定的行为，而宽松地"找至少这么长"会让
    /// `` `a`` `` 这类输入被吃成两段奇怪的东西。
    private static func firstIndex(
        ofRun target: Character,
        length: Int,
        in characters: [Character],
        from start: Int
    ) -> Int? {
        var index = start
        while index < characters.count {
            if characters[index] == target {
                let run = runLength(of: target, in: characters, from: index)
                if run == length { return index }
                // 长度不对 ⇒ 跳过整串（不跳过会让 `` `` `` 里的第二个反引号又被当成新的一串）。
                index += run
                continue
            }
            index += 1
        }
        return nil
    }

    /// 找连续的字符序列（`**`）—— 逐个比对，避免 `***` 这类连排时错位。
    private static func firstIndex(ofSequence target: [Character], in characters: [Character], from start: Int) -> Int? {
        var index = start
        while index + target.count <= characters.count {
            if Array(characters[index..<(index + target.count)]) == target { return index }
            index += 1
        }
        return nil
    }

    /// 解析 `[文字](地址)`；不是合法链接时返回 `nil`（调用方当作普通字符处理）。
    ///
    /// - Returns: 文字、地址（**已通过 `URL` 校验**，无效地址算"不是链接"）、下一个下标。
    static func parseLink(_ characters: [Character], at start: Int) -> (label: String, url: URL, next: Int)? {
        guard characters[start] == "[" else { return nil }
        guard let closingBracket = firstIndex(of: "]", in: characters, from: start + 1) else { return nil }
        let afterBracket = closingBracket + 1
        guard afterBracket < characters.count, characters[afterBracket] == "(" else { return nil }
        guard let closingParen = firstIndex(of: ")", in: characters, from: afterBracket + 1) else { return nil }

        let label = String(characters[(start + 1)..<closingBracket])
        let address = String(characters[(afterBracket + 1)..<closingParen])
        guard !label.isEmpty, !address.isEmpty else { return nil }
        // ⚠️ 地址里不能有空格 —— `[a](b c)` 不是链接。
        //    `URL(string:)` 对空格是**宽容**的（它会自动百分号编码），
        //    所以这里必须自己拦，否则 `[点这里](参见 上文)` 会变成一个能点的链接。
        guard !address.contains(" ") else { return nil }
        guard let url = URL(string: address) else { return nil }

        return (label, url, closingParen + 1)
    }
}
