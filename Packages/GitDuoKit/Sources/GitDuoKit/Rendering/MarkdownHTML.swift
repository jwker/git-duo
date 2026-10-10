import Foundation

/// **HTML 块的降级**：把一段 HTML 改写成 Markdown 源，再交给 `MarkdownParser`。
///
/// ## 为什么需要它（2026-10-07 目视发现的第 2 条）
///
/// 真实的 README **大量使用 HTML** —— 以 `anywhere-labs/dsh-desktop` 为例，
/// 开头那段就是 `<p align="center">` + `<h1 align="center">` + `<img>` + `<sub>` +
/// `<br>`，后面还有 `<details>` / `<summary>` 与好几张 `<table>`。
/// 在此之前，这些标签会**原样打出来**，整屏都是尖括号。
///
/// ## 为什么是"改写成 Markdown"而不是"直接产出 `[MarkdownBlock]`"
///
/// 因为改写之后**一切复用**：块判定、行内解析（`**粗体**` / `[文字](地址)`）、
/// 实体、列表缩进栈 —— 全部走同一条路。直接产块等于把 `MarkdownParser` 里
/// 那些判定抄第二遍，而抄的那一份只在 HTML 这一支生效 ⇒ 两处迟早分叉。
///
/// 这也让本件是一个**纯函数**（`String -> String`），可以用等号断言钉住：
/// 领域层出结构、可单测，是决策 #34 那条标准的直接应用。
///
/// ## ⚠️ 四档降级 + 一条表格改写（降级都**不丢正文**，只是形状变了）
///
/// | HTML | 变成 | 为什么 |
/// |---|---|---|
/// | `<h1>`–`<h6>` | `#`–`######` | 标题本来就有块类型 |
/// | `<br>` | **空行** | `MarkdownSpan` 里没有"换行"这一档（`AGENTS.md §3` 的登记一起看） |
/// | `<img src alt>` | `[alt](src)` | 图片这一期不画；退化成"指向那张图的链接"，点下去进文件查看页（那一页本来就会画图片）。`alt` 为空则整张丢掉 |
/// | `<a href>` | `[文字](href)` | 复用行内链接；仓库内的相对地址由 `RepoLinkResolver` 再解析 |
/// | `<table>` / `<tr>` / `<td>` / `<th>` | **GFM 表格**（表头 + 分隔行 + 数据行） | 已有表格块类型（`TECH_SPEC §11.1`「表格（GFM）已支持」）；`<th>` / `<thead>` 判为表头，**全 `<td>` 时首行兜底为表头**（GFM 表格必须有表头） |
/// | 其余标签 | 只去标签、留文字 | 最保守的一档 |
///
/// ## ⚠️ 一条已知的有损处（登记待评审）
///
/// 1. **字面量标签会被吃掉** —— 正文里靠实体转义写出的 `<div>`（`&lt;div&gt;`）
///    在**第一趟之后**才被还原，于是第二趟会把它当标签去掉。
///    代码块（``` 围栏）不受影响：围栏在块判定的第一支就被拿走了，永远到不了这里。
///    要根治得区分"实体来源的 `<`"，代价是给本件加一份位置表 —— 与收益不成比例。
///
/// （`<ol>` 的编号**已修复**：扫描时维护列表栈、区分 ol/ul 各自计数，支持 `<ol start=…>` 与 `<li value=…>`。
///    ⚠️ **嵌套只还原编号、不还原缩进**（层级仍是 0）—— HTML 的嵌套深度没有对应的 markdown 写法。
///    ⚠️ **`colspan` / `rowspan` 合并格不做**：列数按表头归一化时**多截断**，
///    会丢被合并的多余格 ⇒ 与本节"不丢正文"那条原则有张力，已登记待评审。）
public enum MarkdownHTML {

    /// 一段 HTML → 一段 Markdown 源。
    ///
    /// ## ⚠️ 为什么走**两趟**
    ///
    /// 第一趟去标签、做映射；然后**还原实体**（`&amp;` → `&`、`&lt;` → `<`）；
    /// 第二趟只去标签、不做映射。第二趟是必须的：第一趟留下的 `&lt;div&gt;`
    /// 在还原之后会变成一个货真价实的 `<div>`，若不再去一次，
    /// `MarkdownParser` 会把它当**新的 HTML 块**再解析一遍 —— 而它改出来的东西
    /// 又是同一个串，于是递归不收敛。
    ///
    /// 第二趟**不映射**（不把 `<b>` 变成 `**`）：那时已经不区分"用户写的标签"与
    /// "刚还原出来的文字"，再做映射会给正文添上不该有的星号。
    public static func markdown(from html: String) -> String {
        let rewritten = rewrite(html, mapping: true)
        return rewrite(decodeEntities(rewritten), mapping: false)
    }

    /// 直接产出块 —— 给 `MarkdownParser` 调用。
    public static func blocks(from html: String) -> [MarkdownBlock] {
        MarkdownParser.blocks(from: markdown(from: html))
    }

    /// 一张 HTML 表格的改写状态。
    fileprivate struct TableState {
        /// 当前 `<tr>` 已开始的单元格数。
        var cellCount = 0
        /// 是否在 `<thead>` 内。
        var inHead = false
        /// 当前行是否出现过 `<th>`。
        var rowHasTH = false
        /// 表头分隔行是否已输出（一张表只输出一次）。
        var separatorEmitted = false
        /// 当前单元格是否已闭合（用来兼容省略 `</td>` 的写法）。
        var lastCellClosed = true
        /// 已处理的 `<tr>` 行数（第一行兜底为表头：GFM 表格必须有表头）。
        var rowCount = 0
    }

    // MARK: - 改写

    /// 扫一遍文本：标签按映射改写（`mapping` 为假时一律丢弃），其余原样保留。
    private static func rewrite(_ text: String, mapping: Bool) -> String {
        var out = ""
        var index = text.startIndex
        // 待闭合的 `<a>` 栈。存 `href`，`nil` 表示"这个 `<a>` 没有地址"。
        // ⚠️ `<a>` 不允许嵌套，所以一层栈就够；深一层也不会错，只是用不上。
        var openAnchors: [String?] = []
        // 列表栈：元素为有序列表的"下一个编号"（Int），或 `nil`（无序列表）。
        // 用栈是因为列表会嵌套（ul 里套 ol、ol 里套 ul），每层各自计数。
        var listStack: [Int?] = []
        // 表格栈：把 HTML `<table>` 改写成 GFM 表格（真实 README 里 HTML 表格很多）。
        var tableStack: [TableState] = []

        while index < text.endIndex {
            guard text[index] == "<" else {
                out.append(text[index])
                index = text.index(after: index)
                continue
            }

            // 注释整段丢弃（含内容 —— 它就是给人看的说明，不是正文）。
            if text[index...].hasPrefix("<!--") {
                if let end = text.range(of: "-->", range: index..<text.endIndex) {
                    index = end.upperBound
                    continue
                }
                break
            }

            guard let close = tagEnd(in: text, from: index) else {
                // 这一行里没有闭合的 `>` ⇒ 它不是标签（孤零零一个 `<`）。
                out.append("<")
                index = text.index(after: index)
                continue
            }

            let body = String(text[text.index(after: index)..<close])
            index = text.index(after: close)

            guard isTagLike(body) else {
                // `a < b`、`<https://x>` 这类**不是标签**，原样留着。
                out.append("<")
                out.append(body)
                out.append(">")
                continue
            }

            guard mapping else { continue }
            apply(
                tag: body,
                to: &out,
                openAnchors: &openAnchors,
                listStack: &listStack,
                tableStack: &tableStack
            )
        }

        return out
    }

    /// 一个标签的落点。
    private static func apply(
        tag body: String,
        to out: inout String,
        openAnchors: inout [String?],
        listStack: inout [Int?],
        tableStack: inout [TableState]
    ) {
        let trimmed = body.trimmingCharacters(in: .whitespaces)

        // `<!DOCTYPE …>` / `<?xml …>` —— 声明，丢。
        if trimmed.hasPrefix("!") || trimmed.hasPrefix("?") { return }

        let isClosing = trimmed.hasPrefix("/")
        let rest = isClosing ? trimmed.dropFirst() : Substring(trimmed)
        let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "-" }.lowercased()

        switch name {
        case "br":
            // ⚠️ 空行而不是单个 `\n`：`MarkdownBlock` 里没有"段内换行"这一档
            //    （`MarkdownSpan.Style` 只有 text / code / bold / italic / link）。
            //    单个 `\n` 会被段落收集那一支当成"同一段的下一行"、用空格接起来，
            //    于是 `<br>` 等于消失。空行至少**保住了断句**。
            out += "\n\n"

        case "h1", "h2", "h3", "h4", "h5", "h6":
            if let level = Int(name.suffix(1)) {
                out += isClosing ? "\n\n" : "\n\n" + String(repeating: "#", count: level) + " "
            }

        case "p", "div",
             "details", "blockquote", "dd", "dt", "figure", "figcaption", "dl",
             "picture", "video", "section", "article", "header", "footer", "main":
            if !isClosing { out += "\n\n" }

        // ── 表格：改写成 GFM（表头 + 分隔行 + 数据行）──
        case "table":
            if isClosing {
                _ = tableStack.popLast()
            } else {
                tableStack.append(TableState())
                out += "\n"
            }

        case "thead":
            if !tableStack.isEmpty {
                tableStack[tableStack.count - 1].inHead = !isClosing
            }

        case "tbody", "tfoot":
            if !tableStack.isEmpty {
                tableStack[tableStack.count - 1].inHead = false
            }

        case "tr":
            guard !tableStack.isEmpty else { break }
            if isClosing {
                var state = tableStack[tableStack.count - 1]
                // 第一行兜底为表头：GFM 表格必须有表头，即使 HTML 没写 th/thead。
                let isHeadRow = state.inHead || state.rowHasTH || state.rowCount == 0
                if isHeadRow && !state.separatorEmitted {
                    // 最后一个单元格若没闭合，先补上结尾管道。
                    if !state.lastCellClosed {
                        out += "|"
                        state.lastCellClosed = true
                    }
                    // 表头分隔行：每列一段 `---`。
                    out += "\n|" + String(repeating: "---|", count: max(1, state.cellCount))
                    state.separatorEmitted = true
                }
                state.rowCount += 1
                tableStack[tableStack.count - 1] = state
            } else {
                // 新行：重置行内状态，输出行首管道。
                tableStack[tableStack.count - 1].cellCount = 0
                tableStack[tableStack.count - 1].rowHasTH = false
                tableStack[tableStack.count - 1].lastCellClosed = true
                out += "\n|"
            }

        case "ol":
            if isClosing {
                _ = listStack.popLast()
            } else {
                // 有序列表：起始编号由 `start` 决定（默认 1），编号存在栈顶。
                let start = attribute("start", in: body).flatMap(Int.init) ?? 1
                listStack.append(start)
                out += "\n\n"
            }

        case "ul":
            if isClosing {
                _ = listStack.popLast()
            } else {
                // 无序列表：栈顶存 nil。
                listStack.append(nil)
                out += "\n\n"
            }

        case "td", "th":
            let isHeaderCell = name == "th"
            guard !tableStack.isEmpty else {
                // 表格外的孤立 td/th，保留每个单元格换行的旧降级。
                out += "\n"
                break
            }
            var state = tableStack[tableStack.count - 1]
            if isClosing {
                if !state.lastCellClosed {
                    out += "|"
                    state.lastCellClosed = true
                }
            } else {
                // 上一个单元格没闭合就先关上（兼容省略 `</td>` 的写法）。
                if state.cellCount > 0 && !state.lastCellClosed {
                    out += "|"
                }
                state.cellCount += 1
                if isHeaderCell { state.rowHasTH = true }
                state.lastCellClosed = false
            }
            tableStack[tableStack.count - 1] = state

        case "li":
            // 只在开标签时输出一个列表项；闭标签不产出。
            guard !isClosing else { break }
            if !listStack.isEmpty {
                // `value` 可以指定这一项的编号（仅对有序列表生效）。
                if let value = attribute("value", in: body).flatMap(Int.init) {
                    listStack[listStack.count - 1] = value
                }
                if let number = listStack[listStack.count - 1] {
                    // 有序：输出当前编号并把栈顶计数 +1。
                    out += "\n\(number). "
                    listStack[listStack.count - 1] = number + 1
                } else {
                    // 栈顶为 nil ⇒ 无序。
                    out += "\n- "
                }
            } else {
                // 不在任何列表里的孤立 <li>，兜底成无序项。
                out += "\n- "
            }

        case "summary":
            // 折叠标题：`<summary>` 之后是正文，加粗一下才看得出它是标题。
            out += isClosing ? "**\n\n" : "\n\n**"

        case "b", "strong":
            out += "**"

        case "i", "em":
            out += "*"

        case "a":
            if isClosing {
                // `href` 为空（`<a id="run"></a>`）⇒ 这一对标签什么都不产出。
                if let href = openAnchors.popLast(), let href {
                    out += "](\(href))"
                }
            } else if let href = attribute("href", in: body), !href.isEmpty {
                openAnchors.append(href)
                out += "["
            } else {
                openAnchors.append(nil)
            }

        case "img":
            // 见类型说明那一行：图片退化成指向它的链接，文字取 `alt`。
            // `alt` 为空时**整张丢掉** —— 一枚没有替代文字的图在纯文字里没有落点。
            let attributes = attributes(in: body)
            if let source = attributes["src"], !source.isEmpty,
               let alt = attributes["alt"], !alt.isEmpty {
                out += "[\(alt)](\(source))"
            }

        default:
            // 未知标签（含 `sub` / `sup` / `span` / `font` / `kbd` …）：只去标签、留文字。
            break
        }
    }

    // MARK: - 标签识别

    /// 找这个标签的收尾 `>`。
    ///
    /// ⚠️ **引号内的 `>` 不算收尾** —— `<img alt="a > b" src="x">` 里那个 `>`
    /// 是属性值的一部分。少了这条，标签会在中间被截断，剩下半截属性当正文打出来。
    private static func tagEnd(in text: String, from start: String.Index) -> String.Index? {
        var index = text.index(after: start)
        var quote: Character?

        while index < text.endIndex {
            let character = text[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// `body`（尖括号内部那一段）看起来是不是一个标签。
    ///
    /// 判据只有一条：**去掉可选的 `/` 之后以字母开头，且标签名后面紧跟着
    /// 空白 / `/` / 结束**。这一条专为把 `<https://example.com>` 挡在外面 ——
    /// 它的"标签名"后面跟的是 `:`，而那是正文里的一个网址，不是标签。
    private static func isTagLike(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("!") || trimmed.hasPrefix("?") { return true }

        let rest = trimmed.hasPrefix("/") ? trimmed.dropFirst() : Substring(trimmed)
        guard let first = rest.first, first.isLetter else { return false }

        let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "-" }
        guard let next = rest.dropFirst(name.count).first else { return true }
        return next.isWhitespace || next == "/"
    }

    // MARK: - 属性

    /// 把标签内部那一段解析成属性表（键统一小写）。
    ///
    /// 标签名本身会被跳过；三种写法都认：`href="x"` / `href='x'` / `href=x`。
    private static func attributes(in body: String) -> [String: String] {
        var result: [String: String] = [:]
        let characters = Array(body)
        var index = 0

        // 跳过标签名（以及闭合标签那个 `/`）。
        while index < characters.count, !characters[index].isWhitespace { index += 1 }

        while index < characters.count {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            guard index < characters.count else { break }

            var key = ""
            while index < characters.count, !characters[index].isWhitespace, characters[index] != "=" {
                key.append(characters[index])
                index += 1
            }
            guard !key.isEmpty else {
                index += 1
                continue
            }

            while index < characters.count, characters[index].isWhitespace { index += 1 }

            var value = ""
            if index < characters.count, characters[index] == "=" {
                index += 1
                while index < characters.count, characters[index].isWhitespace { index += 1 }
                if index < characters.count, characters[index] == "\"" || characters[index] == "'" {
                    let quote = characters[index]
                    index += 1
                    while index < characters.count, characters[index] != quote {
                        value.append(characters[index])
                        index += 1
                    }
                    if index < characters.count { index += 1 }
                } else {
                    while index < characters.count, !characters[index].isWhitespace {
                        value.append(characters[index])
                        index += 1
                    }
                }
            }

            result[key.lowercased()] = value
        }
        return result
    }

    private static func attribute(_ name: String, in body: String) -> String? {
        attributes(in: body)[name.lowercased()]
    }

    // MARK: - 实体

    /// 具名实体表。**只收常见的这一批** —— 完整表有两千多条，而 README 里
    /// 真正出现的就那么几个（`&amp;` 与 `&nbsp;` 占绝大多数）。
    /// 认不出的实体原样保留（`&foo;`），那比变成空白更容易查。
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": " ", "ensp": " ", "emsp": " ",
        "mdash": "—", "ndash": "–", "minus": "−", "hellip": "…",
        "copy": "©", "reg": "®", "trade": "™", "times": "×", "divide": "÷",
        "middot": "·", "bull": "•", "laquo": "«", "raquo": "»",
        "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’",
        "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓",
        "check": "✓", "cross": "✗", "star": "★", "hearts": "♥",
        "le": "≤", "ge": "≥", "ne": "≠", "deg": "°", "plusmn": "±",
    ]

    /// 还原 HTML 实体（具名 + 十进制 `&#123;` + 十六进制 `&#x1F600;`）。
    static func decodeEntities(_ text: String) -> String {
        var out = ""
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "&" else {
                out.append(text[index])
                index = text.index(after: index)
                continue
            }

            // 实体名不会太长；超了就不是实体。
            guard let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                out.append("&")
                index = text.index(after: index)
                continue
            }

            let body = String(text[text.index(after: index)..<semicolon]).lowercased()
            if let replacement = replacement(for: body) {
                out += replacement
                index = text.index(after: semicolon)
            } else {
                out.append("&")
                index = text.index(after: index)
            }
        }
        return out
    }

    private static func replacement(for body: String) -> String? {
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits, radix: 10)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return namedEntities[body]
    }
}
