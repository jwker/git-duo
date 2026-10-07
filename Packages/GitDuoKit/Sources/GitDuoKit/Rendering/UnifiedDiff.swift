import Foundation

/// unified diff 的一行（TECH_SPEC §11.2）。
public struct DiffLine: Sendable, Hashable {

    public let kind: Kind

    /// 行内容 —— **已去掉行首那一个标记字符**（`+` / `-` / 空格）。
    ///
    /// ⚠️ 去掉是有意的：视图要按 `kind` 上红绿底色，若文字里还留着符号，
    /// 用户会看到 `+ + 新增的内容`（符号被画了两遍 —— 一遍在底色里、一遍在文字里）。
    public let text: String

    /// 旧文件里的行号。`nil` 表示这一行在旧文件里**不存在**（新增行）。
    public let oldNumber: Int?

    /// 新文件里的行号。`nil` 同理（删除行）。
    public let newNumber: Int?

    public init(kind: Kind, text: String, oldNumber: Int? = nil, newNumber: Int? = nil) {
        self.kind = kind
        self.text = text
        self.oldNumber = oldNumber
        self.newNumber = newNumber
    }

    public enum Kind: Sendable, Hashable {

        /// 上下文行（未改动）。
        case context

        case addition

        case deletion

        /// `\ No newline at end of file` —— 它不是文件里的一行，
        /// 而是一条**关于上一行**的说明（那一行没有以换行结尾）。
        ///
        /// ⚠️ **不消耗行号**：它没有自己的行号，把它算进计数会让后面的行号整体偏 1。
        case noNewline

        /// 认不出来的行（不以前述任何标记开头）。
        ///
        /// 留着它是为了**不丢内容**：unified diff 里出现过非标准行时
        /// （某些工具会在 hunk 里插注释），丢掉它会让用户看到的 diff **少一行**、
        /// 而少的那行没有任何迹象。归到这一档，照原文显示、不上色。
        case unknown
    }
}

/// 一个 hunk（`@@ -a,b +c,d @@` 开头的连续块）。
public struct DiffHunk: Sendable, Hashable {

    /// 原始表头行（`@@ -40,7 +40,9 @@`），**含 `@@`**。
    ///
    /// 视图直接把它当一行等宽文字显示（原型 `.hunk` 就是整行照印）。
    public let header: String

    /// 表头后面那一段（GitHub 会带上函数名之类的上下文），没有则为 `nil`。
    public let section: String?

    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int

    public let lines: [DiffLine]

    public init(
        header: String,
        section: String? = nil,
        oldStart: Int,
        oldCount: Int,
        newStart: Int,
        newCount: Int,
        lines: [DiffLine]
    ) {
        self.header = header
        self.section = section
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

/// 一个文件的 diff（多文件原文里的一个段落）。
public struct FileDiff: Sendable, Hashable {

    /// 旧路径（`a/GitDuo/App.swift` 去掉 `a/`）。新建文件时为 `/dev/null` ⇒ `nil`。
    public let oldPath: String?

    /// 新路径同上。
    public let newPath: String?

    /// 服务端直说这是二进制（`Binary files … differ`）。
    ///
    /// ⚠️ 与 `FileChange.isBinary`（推断）**不是一回事**：那个是"文件名看着不是文本"，
    /// 这个是 diff 原文里的一句明确陈述。两者结论不同时，**以这个为准**。
    public let isBinary: Bool

    public let hunks: [DiffHunk]

    public init(oldPath: String? = nil, newPath: String? = nil, isBinary: Bool = false, hunks: [DiffHunk] = []) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.isBinary = isBinary
        self.hunks = hunks
    }

    /// 显示用的路径：优先新路径，新建/删除时退到旧路径。
    public var displayPath: String? { newPath ?? oldPath }
}

/// unified diff 解析器 —— TECH_SPEC §11.2。
///
/// ## 两个入口，共用一套实现
///
/// - `hunks(from:)` —— 解析 `commits/{sha}` 里 `files[].patch` 那种**单文件**片段；
/// - `files(from:)` —— 解析 `application/vnd.github.diff` 那种**多文件**原文
///   （以 `diff --git` 分割）。
///
/// ## 性能：**按需解析**（§11.2 最后一行）
///
/// 本解析器是**纯函数、无状态、无缓存**，所以"按需"由调用方保证 ——
/// 折叠状态的文件**不要调它**。一个数百文件的 PR 若一上来全解析，
/// 那几百段文本都要走一遍字符扫描，而用户可能一个都没展开。
public enum UnifiedDiffParser {

    /// 解析单文件片段（`files[].patch`）。
    ///
    /// ⚠️ 传入 `nil` 或空串都返回空数组 —— 调用方不需要在调用前判空
    /// （`FileChange.patch` 本来就是可选的，每个调用点都写一次 `if let` 是噪音）。
    public static func hunks(from patch: String?) -> [DiffHunk] {
        guard let patch, !patch.isEmpty else { return [] }
        return parseLines(patch).hunks
    }

    /// 解析多文件原文（`diff --git a/x b/y` 分割）。
    public static func files(from diffText: String) -> [FileDiff] {
        let lines = normalize(diffText)
        var result: [FileDiff] = []
        var current: [String] = []
        var sawHeader = false

        func flush() {
            // 还没遇到任何 `diff --git` 之前的散行（例如某些工具前面会贴一行说明）
            // ⇒ 也当作一个匿名文件段落解析，不丢内容。
            guard sawHeader || current.contains(where: { !$0.isEmpty }) else { return }
            let parsed = parseLines(current.joined(separator: "\n"))
            result.append(parsed)
            current = []
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                flush()
                sawHeader = true
                current = [line]
            } else {
                current.append(line)
            }
        }
        flush()
        return result
    }

    // MARK: - 内部

    /// 一个文件段落的解析结果（`hunks` + 从 `diff --git` 头里读到的路径与二进制标记）。
    private static func parseLines(_ patch: String) -> FileDiff {
        let lines = normalize(patch)
        var oldPath: String?
        var newPath: String?
        var isBinary = false
        var hunks: [DiffHunk] = []

        var index = 0
        while index < lines.count {
            let line = lines[index]

            if line.hasPrefix("diff --git ") {
                // `diff --git a/x b/y` —— 两个路径可能都含空格，所以不按空格简单切分，
                // 只在**已知前缀** `a/` 与中间的 ` b/` 上找。
                if let (old, new) = Self.pathsFromGitHeader(line) {
                    oldPath = old
                    newPath = new
                }
                index += 1
                continue
            }

            if line.hasPrefix("--- ") {
                let value = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                oldPath = Self.stripPrefix(value)
                index += 1
                continue
            }

            if line.hasPrefix("+++ ") {
                let value = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                newPath = Self.stripPrefix(value)
                index += 1
                continue
            }

            if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
                isBinary = true
                index += 1
                continue
            }

            if line.hasPrefix("@@") {
                let (hunk, next) = Self.parseHunk(lines, startingAt: index)
                hunks.append(hunk)
                index = next
                continue
            }

            index += 1
        }

        return FileDiff(oldPath: oldPath, newPath: newPath, isBinary: isBinary, hunks: hunks)
    }

    /// 从一个 hunk 表头开始，吃到下一个表头（或文件级标记）之前。
    private static func parseHunk(_ lines: [String], startingAt start: Int) -> (DiffHunk, Int) {
        let header = lines[start]
        let (oldStart, oldCount, newStart, newCount, section) = Self.parseHunkHeader(header)

        var body: [DiffLine] = []
        // ⚠️ 行号从**表头给的起点**开始，不是从 1 —— 这是 diff 能对上原文的唯一依据。
        var oldLine = oldStart
        var newLine = newStart
        // 空文件的两端：`@@ -0,0 +1,28 @@` 里 old 侧**一行都没有**，
        // 此时 old 行号整段为 `nil`（而不是从 0 开始数出 0、1、2…）。
        let hasOld = oldCount > 0
        let hasNew = newCount > 0

        var index = start + 1
        while index < lines.count {
            let line = lines[index]
            // 下一个 hunk / 下一个文件 ⇒ 本 hunk 结束。
            if line.hasPrefix("@@") || line.hasPrefix("diff --git ") { break }

            // ⚠️ `" "` 与 `""` 都要判成上下文行：diff 里一个**空行**的上下文
            //    写作一个空格（有些工具会把它丢成空串）。两者都是"上下文"，
            //    归到同一档才不会让它变成 `unknown` 而丢掉行号。
            if line.hasPrefix("+") {
                body.append(DiffLine(kind: .addition, text: String(line.dropFirst()), newNumber: hasNew ? newLine : nil))
                if hasNew { newLine += 1 }
            } else if line.hasPrefix("-") {
                body.append(DiffLine(kind: .deletion, text: String(line.dropFirst()), oldNumber: hasOld ? oldLine : nil))
                if hasOld { oldLine += 1 }
            } else if line.hasPrefix("\\") {
                // `\ No newline at end of file` —— **不消耗行号**。
                body.append(DiffLine(kind: .noNewline, text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix(" ") || line.isEmpty {
                let text = line.isEmpty ? "" : String(line.dropFirst())
                body.append(
                    DiffLine(
                        kind: .context,
                        text: text,
                        oldNumber: hasOld ? oldLine : nil,
                        newNumber: hasNew ? newLine : nil
                    )
                )
                if hasOld { oldLine += 1 }
                if hasNew { newLine += 1 }
            } else {
                body.append(DiffLine(kind: .unknown, text: line))
            }
            index += 1
        }

        let hunk = DiffHunk(
            header: header,
            section: section,
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            lines: body
        )
        return (hunk, index)
    }

    /// `@@ -40,7 +40,9 @@ optional section` ⇒ 五个值。
    ///
    /// ⚠️ 逗号与数量都可以省略（`@@ -1 +1 @@` 表示各 1 行），
    /// 所以 `-40` 与 `-40,7` 两种都要认。认不出来时返回全 0 且**不崩** ——
    /// 一个畸形表头不该让整页打不开（那正是"服务端给了没见过的形状"时的表现）。
    static func parseHunkHeader(_ header: String) -> (
        oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, section: String?
    ) {
        // 表头形如 `@@ -a,b +c,d @@ section`；`@@` 之间的部分才是坐标。
        let inner = header.dropFirst(2)
        guard let closing = inner.range(of: "@@") else { return (0, 0, 0, 0, nil) }
        let coordinates = inner[..<closing.lowerBound].trimmingCharacters(in: .whitespaces)
        let sectionText = inner[closing.upperBound...].trimmingCharacters(in: .whitespaces)

        var oldStart = 0
        var oldCount = 0
        var newStart = 0
        var newCount = 0

        for token in coordinates.split(separator: " ") {
            guard let sign = token.first, sign == "-" || sign == "+" else { continue }
            let numbers = token.dropFirst().split(separator: ",")
            let start = numbers.first.flatMap { Int($0) } ?? 0
            // 省略数量时（`-40`）表示 1 行。
            let count = numbers.count > 1 ? (Int(numbers[1]) ?? 0) : 1
            if sign == "-" {
                oldStart = start
                oldCount = count
            } else {
                newStart = start
                newCount = count
            }
        }

        return (oldStart, oldCount, newStart, newCount, sectionText.isEmpty ? nil : sectionText)
    }

    /// `a/x/y.swift` / `b/x/y.swift` ⇒ `x/y.swift`；`/dev/null` ⇒ `nil`。
    static func stripPrefix(_ path: String) -> String? {
        if path == "/dev/null" { return nil }
        if path.hasPrefix("a/") || path.hasPrefix("b/") { return String(path.dropFirst(2)) }
        return path
    }

    /// 从 `diff --git a/x b/y` 里取两个路径。
    static func pathsFromGitHeader(_ line: String) -> (old: String?, new: String?)? {
        let rest = line.dropFirst("diff --git ".count)
        // 找中间的 ` b/`：路径本身可能含空格，所以不能用 `split(separator: " ")`。
        guard let separator = rest.range(of: " b/") else { return nil }
        let old = Self.stripPrefix(String(rest[..<separator.lowerBound]))
        let new = Self.stripPrefix("b/" + rest[separator.upperBound...])
        return (old, new)
    }

    /// 换行归一 + 按行拆（**保留空行**，见 `FileContent.lines` 的同源理由）。
    private static func normalize(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // diff 原文常以一个换行结尾 ⇒ 尾部那个空串不是一行。
        if lines.last == "" { lines.removeLast() }
        return lines
    }
}
