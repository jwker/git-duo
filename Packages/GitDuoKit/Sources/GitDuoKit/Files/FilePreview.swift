import Foundation

/// 一个文件该用哪条通道取、能不能预览 —— TECH_SPEC §9.5、决策 #54。
///
/// ## 为什么判定必须在**发请求之前**
///
/// `GET …/contents/{path}` 对超过 1MB 的文件回 **HTTP 200 + `encoding: "none"` +
/// `content: ""`**（2026-10-07 实测：4,280,356 字节的文件就是这个形状）。
/// 不先判定、拿到空串再补救，用户会先看到**一个空白页**——而它不报错、不是加载中，
/// 看起来就是"这个文件是空的"。判定按**扩展名 + `size`** 做，两者在发请求前就都有。
///
/// ## 为什么不能"按 UTF-8 解码失败判二进制"
///
/// 那条路要求把**可能很大的字节**先读进内存再试解码 —— 而扩展名在发请求之前就有。
/// 图片同理：**先看 `size` 再决定下不下**（解码成位图后内存约为字节数的数倍，
/// 手机上没有理由硬拉一张 20MB 的 PNG，只为了发现它太大然后丢掉）。
///
/// ## ⚠️ 白名单判定的取舍方向
///
/// 判定是**白名单**式的：扩展名/文件名在表里 ⇒ 相应通道；不在 ⇒ `unsupported`。
/// 两个方向的错误代价不对称：
/// - 把文本错判成 `unsupported` ⇒ 用户少看一个文件，但有"跳网页端"的出口；
/// - 把二进制错判成文本 ⇒ 页面上出现一大片乱码（或崩在解码上）。
///
/// 所以表只会往"认得出来"的方向补，不在拿不准时猜。
public enum FilePreviewKind: Equatable, Sendable {

    /// 文本，且 `size` 在 `maxInlineTextBytes` 之内 ⇒ 走 contents 的 base64 `content`。
    case text

    /// 文本，但超过内联上限 ⇒ 走 `Accept: application/vnd.github.raw` 取原文。
    ///
    /// ⚠️ **只读浏览大文件是支持的**（§9.5 明写）。不做的是"上传 / 编辑 / 提交"
    /// 大文件（§9.6，那要 Git Data API）—— 这两件事常被并成一句"不支持大文件"。
    case largeText

    /// 图片，且 `size` 在 `maxImageBytes` 之内 ⇒ 走 raw 取字节再解码预览。
    case image

    /// 不下载。给「不支持预览」+ 跳网页端的出口（PRD §4.5）。
    case unsupported(Reason)

    /// 不预览的原因 —— 文案不同（`FileCopy`），因为用户的下一步不一样：
    /// 图片太大是"等个网络更好的时机或去网页端"，二进制是"这里根本打不开它"。
    public enum Reason: Equatable, Sendable {
        case binary
        case imageTooLarge
    }

    // MARK: - 常量

    /// 内联文本的上限。
    ///
    /// ⚠️ 取 **十进制 1,000,000** 而不是 `1 MiB`（1,048,576），是**故意偏小**：
    /// GitHub 那条 "up to 1 megabyte" 的确切阈值无法从文档确认，
    /// 而两种取法错的方向代价不对称 ——
    ///
    /// - 阈值取小了（1,020,000 字节的文件被判 `largeText`）⇒ 走 raw，**照样拿得到**
    ///   （raw 通道对 1KB 和 100MB 的文件都有效）；
    /// - 阈值取大了（同文件被判 `text`）⇒ 请求 contents，拿到 `encoding: "none"` +
    ///   空 `content` ⇒ **页面一片空白**，且不报错。
    ///
    /// 所以宁可早一步走 raw。
    public static let maxInlineTextBytes = 1_000_000

    /// 图片预览的上限。
    ///
    /// 超过就不下载 —— 一张 8MB 的 PNG 解码后约占 32MB 内存，而它只是列表里的一个点击。
    /// 用户仍有"跳网页端"这个出口（PRD §4.5 的降级出口）。
    public static let maxImageBytes = 5_000_000

    // MARK: - 判定

    /// 按**文件名 + 字节数**决定通道。
    ///
    /// - Parameters:
    ///   - name: 条目名或路径 —— 只看最后一段的扩展名（`docs/guide.md` 与 `guide.md` 同判）。
    ///   - size: `contents` 给的字节数；**未知时传 `nil`**。
    ///
    /// ⚠️ `size == nil` 时的行为：**按名字那一侧处理**（文本 ⇒ `.text`，图片 ⇒ `.image`），
    /// **不**按 `unsupported`。理由是调用点的差异 —— 问 `decide` 的有两处：
    /// 目录清单（`size` 一定有）与"从提交详情点进一个文件"（那里只有文件名，没有大小）。
    /// 后者若因为没有大小就判成 `unsupported`，一次本可以成功的查看会被挡掉；
    /// 而若它其实是大文件，contents 会回空 `content` —— 那条路**还有救**：
    /// 解码时发现 `encoding == "none"` 就改走 raw（见 `FileContent`），只多一个 RTT。
    /// 反过来（判成 `unsupported`）**没有救**。
    public static func decide(name: String, size: Int?) -> FilePreviewKind {
        let ext = extensionOf(name)
        let base = fileNameOf(name).lowercased()

        let isText = textExtensions.contains(ext) || textFileNames.contains(base)
        let isImage = imageExtensions.contains(ext)

        // 名字既不在文本表、也不在图片表 ⇒ 二进制（或我们不认识的类型）。
        guard isText || isImage else { return .unsupported(.binary) }

        guard let size else { return isText ? .text : .image }

        if isImage {
            // 图片优先判：一个 `.svg` 不会走到这里（它在文本表里），
            // 而如果将来两表出现交集，图片的判定应当胜出 —— 用户期待看到图。
            return size > maxImageBytes ? .unsupported(.imageTooLarge) : .image
        }
        return size > maxInlineTextBytes ? .largeText : .text
    }

    /// 该判定要不要走 `Accept: application/vnd.github.raw` 通道。
    public var needsRawChannel: Bool {
        switch self {
        case .largeText, .image: true
        case .text, .unsupported: false
        }
    }

    /// 这个文件在 App 里**有没有内容可显示**（`unsupported` 没有任何通道）。
    public var hasContent: Bool {
        if case .unsupported = self { return false }
        return true
    }

    // MARK: - 名字解析

    /// 小写扩展名（不含点）。`Makefile` / `.gitignore` 这类**没有扩展名**的返回空串。
    ///
    /// ⚠️ `.gitignore` 的 `pathExtension` 是 **空串**（前导点属于隐藏文件名，
    /// 不是扩展名分隔符）⇒ 它只能靠 `textFileNames` 那张表认出来，靠扩展名表认不出。
    public static func extensionOf(_ name: String) -> String {
        // 只看最后一段：`docs/a.b/c`（目录名里带点）不能把 `c` 的扩展名带歪。
        (fileNameOf(name) as NSString).pathExtension.lowercased()
    }

    /// 路径的最后一段（`docs/guide.md` → `guide.md`）。
    public static func fileNameOf(_ name: String) -> String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    // MARK: - 白名单

    /// 认得出的文本扩展名。按语言族排列，便于将来补。
    ///
    /// ⚠️ `svg` 在**这里**而不是图片表：iOS 的 `UIImage` 不渲染 SVG，
    /// 而它是一份可读的 XML ⇒ 当文本显示是它唯一说得通的用法。
    public static let textExtensions: Set<String> = [
        // 本项目与常见语言
        "swift", "rs", "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "go",
        "java", "kt", "kts", "scala", "rb", "php", "cs", "fs",
        // C 家族
        "c", "h", "cc", "cpp", "cxx", "hpp", "hh", "m", "mm",
        // 脚本与配置
        "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd",
        "json", "jsonc", "yaml", "yml", "toml", "ini", "cfg", "conf",
        "plist", "xml", "entitlements", "xcconfig", "pbxproj", "strings", "properties",
        "gradle", "podspec", "cmake", "mk",
        // 文档与数据
        "md", "markdown", "rst", "txt", "text", "log", "csv", "tsv", "adoc",
        // Web
        "html", "htm", "css", "scss", "sass", "less", "vue", "svelte", "svg",
        // 散装
        "gitignore", "gitattributes", "editorconfig", "env", "lock", "sum", "mod",
    ]

    /// 认得出的图片扩展名（`size` 还要在 `maxImageBytes` 内）。
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "heif", "tiff", "tif", "ico", "avif",
    ]

    /// **没有扩展名**、但确实是文本的常见文件名（小写比较）。
    ///
    /// ⚠️ 这张表不能省：`Makefile` / `LICENSE` / `.gitignore` 在仓库里极其常见，
    /// 而它们的 `pathExtension` 都是空串 —— 只靠扩展名表，这些文件在 App 里**全都不开**。
    public static let textFileNames: Set<String> = [
        "makefile", "gnumakefile", "dockerfile", "containerfile",
        "license", "licence", "copying", "notice", "authors", "contributors",
        "readme", "changelog", "changes", "history", "todo", "install", "news",
        "gemfile", "rakefile", "procfile", "brewfile", "vagrantfile", "justfile",
        ".gitignore", ".gitattributes", ".gitmodules", ".editorconfig",
        ".env", ".npmrc", ".nvmrc", ".prettierrc", ".eslintrc", ".babelrc",
        ".swiftlint.yml", ".ruby-version", ".python-version",
    ]
}
