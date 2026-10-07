import Foundation

/// 一个文件的内容（PRD §4.5、TECH_SPEC §9.5）。
///
/// ## 三种来源合成同一个类型
///
/// 决策 #54 的三档降级最终都要落到"屏幕上显示什么"，所以这里只有一个类型：
/// 正文（文本 / 图片字节）、它来自哪条通道、以及 blob 的 SHA。
///
/// ⚠️ **`blobSHA` 必存**：文件查看页本身只读，但切片 8 的编辑器要拿它去做
/// 乐观锁（`PUT …/contents/{path}` 带 `sha` 表示"更新"，不带就是"新建"）。
/// 本页是用户唯一能拿到它的地方之一（另一处是目录清单的 `TreeEntry.sha`）。
public struct FileContent: Sendable {

    /// 文件在仓库内的路径。
    public let path: RepoPath

    /// blob SHA —— 编辑与"是否已变更"的基准。
    public let blobSHA: String

    /// 字节数（服务端给的那个数，不是解码后重算的）。
    public let size: Int

    /// 正文。
    public let body: Body

    /// 观众看到的形态（决定视图画代码块还是图片，以及"不支持预览"的出口）。
    public let preview: FilePreviewKind

    public init(path: RepoPath, blobSHA: String, size: Int, body: Body, preview: FilePreviewKind) {
        self.path = path
        self.blobSHA = blobSHA
        self.size = size
        self.body = body
        self.preview = preview
    }

    public enum Body: Sendable {
        case text(String)
        case image(Data)
    }

    /// 正文的文本形式；图片时为 `nil`。
    ///
    /// 供「Raw：复制原文到剪贴板」用（决策 #51：`Raw` 当真做，零请求）。
    /// 图片没有"原文可复制" ⇒ `nil`，那个按钮在图片上也不该出现。
    public var text: String? {
        if case let .text(value) = body { return value }
        return nil
    }

    /// 行拆分 —— 文件查看页与代码块视图共用。
    ///
    /// ⚠️ **不用 `split(separator:)` 的默认行为**：它会丢掉空行（`omittingEmptySubsequences`
    /// 默认为真），而空行是代码里最不能丢的东西 —— 丢了之后行号全错位，
    /// 而"行号对不上"是用户唯一用来定位自己没看到的那几行的手段。
    /// 同时把 `\r\n` 归一成 `\n`（Windows 检出的文件很常见）。
    public static func lines(of text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var result = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // `"a\n"` 拆出来是 `["a", ""]` —— 末尾那个空串不是一行，是"文件以换行结尾"。
        // 留着它会让代码块底部多出一条空行、行号也多一号。
        if result.last == "" { result.removeLast() }
        return result
    }
}

/// contents 响应的解码规则（§9.5、决策 #54）。
///
/// ## 为什么这些是纯函数、放在领域层
///
/// 三条都是"错了不会报错、只会显示成别的东西"的规则：
/// base64 里带换行（GitHub 每 60 字符插一个）没去掉 ⇒ **解码直接失败**；
/// `encoding == "none"` 没识别 ⇒ 显示一个**空文件**；
/// 行拆分把空行吃掉 ⇒ **行号全错**。放进本包，它们落在 `FileContentCodecTests` 里。
public enum FileContentCodec {

    // MARK: - base64

    /// GitHub contents 的 base64 是**带换行**的。
    ///
    /// `Data(base64Encoded:)` 默认**不容忍**内嵌空白（`options: []`）⇒
    /// 直接把服务端那串丢进去会返回 `nil`，而 `nil` 在这里会被当成"文件为空"。
    /// 所以先剥掉全部空白（空格、`\n`、`\r`、`\t`），再解码。
    ///
    /// ⚠️ 用 `.ignoringUnknownCharacters` 是**不够的**：那个选项跳的是"不在 base64 字母表里
    /// 的字符"，而换行恰好不在字母表里 —— 看起来能用。但它同时会**静默吞掉真正的坏字符**
    /// （例如把 `+` 写成了空格），于是"传输损坏"会变成"内容悄悄少一段"。
    /// 精确剥空白 + 严格解码，"坏"就仍然是坏。
    public static func decodeBase64(_ encoded: String) -> Data? {
        let stripped = encoded.filter { !$0.isWhitespace }
        guard !stripped.isEmpty else { return nil }
        return Data(base64Encoded: stripped)
    }

    // MARK: - 是否要走 raw 回退

    /// contents 这次响应**是不是一个"内容没给"的空壳**。
    ///
    /// 判据两条，任一成立即为真：
    /// 1. `encoding == "none"` —— 官方对大文件的表示（实测 4,280,356 字节的文件回这个）；
    /// 2. `size > 0` 但 `content` 为空 —— 防御性的第二条：`encoding` 是**字符串**，
    ///    GitHub 将来换个取值（或者某个中间层把它吞了）时，只看第 1 条会
    ///    把一个有内容的文件渲染成空页。
    ///
    /// ⚠️ 反过来（`size == 0` 且 `content` 为空）**不是**空壳，那是**真正的空文件** ——
    /// 去 raw 通道取一次只会得到同样一个空串，白费一次请求。
    public static func isContentOmitted(encoding: String?, base64: String?, size: Int) -> Bool {
        if encoding?.lowercased() == "none" { return true }
        return size > 0 && (base64?.isEmpty ?? true)
    }

    // MARK: - 文本解码

    /// 把字节解成文本；**解不出来返回 `nil`**。
    ///
    /// ⚠️ 这里**不做**"有损解码"（`String(decoding:as:)` 那种把非法字节换成 `�` 的做法）：
    /// 一个 GBK 编码的 `.md` 用有损 UTF-8 解出来是一大片 `�`，
    /// 而用户看到它会以为"这个文件坏了" —— 真实情况只是"这个 App 不认识它的编码"。
    /// 返回 `nil` 让调用方走「不支持预览 + 跳网页端」，那句话是**准确**的。
    ///
    /// 注意与 §9.5 那句"不按 UTF-8 解码失败判二进制"**不矛盾**：
    /// 那句说的是**判定阶段**（决定下不下载）要用扩展名而不是先解码；
    /// 这里是**已经拿到了文本通道的内容**之后的最后一步。
    public static func text(from data: Data) -> String? {
        String(data: data, encoding: .utf8)
    }
}
