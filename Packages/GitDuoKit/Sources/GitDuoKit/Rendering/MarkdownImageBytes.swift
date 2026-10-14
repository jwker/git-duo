import Foundation

/// 一段图片字节的两件解读：**它是不是 SVG**（`looksLikeSVG`）、
/// 以及**它自己声明了多大**（`declaredSize`）—— 两者都只在 `UIImage` 解不出来**之后**才被问。
///
/// ⚠️ **两件事必须按这个顺序问**：先 `looksLikeSVG`、再 `declaredSize`。
/// 反过来的话，一份"正文里写着 `<svg width=…>`"的文档会被量出一个假尺寸。
///
/// ## 格式判断只用在一个地方：`UIImage` 解不出来**之后**
///
/// `MarkdownImageStore` 拿到字节第一件事是 `UIImage(data:)` ——
/// **成功就是图片，那条路上本件一句话都不说**。只有解码**失败**时才来这里问一句
/// "那它是不是 SVG"，好把占位文案从「图片加载失败」换成「SVG 图片：xxx」。
///
/// ⚠️ **两步的顺序不能反**（先解码、后判格式）：SVG 嗅探是**启发式**（找 `<svg` 字样），
/// 而 `UIImage(data:)` 是**确定**的。先猜后解会让一张"恰好含 `<svg` 字样的坏 PNG"
/// 被报成 SVG —— 而那种错误没人会报回来，它看起来只是"这句话说得怪"。
///
/// ## 为什么需要它（而不是按扩展名判）
///
/// 2026-10-14 用户报回的两张截图里，失败的图**一半根本没有 `.svg` 后缀**：
/// `https://img.shields.io/badge/Rust-100%25-orange` 这种徽章地址**只出 SVG**、
/// 而路径上没有任何提示（`api.star-history.com/svg?repos=…` 同理，后缀被 query 挡住）。
/// ⇒ 只有看字节才判得准。（同一天用户报的另一个仓库那个 `docs/brand/artcraft-logo.svg`
/// 倒是带后缀，但一条判据要能同时管住两种，就不能依赖后缀。）
///
/// ## 为什么在领域层
///
/// `make test` **不编译 App target**（同 `MarkdownRun` / `RepoCopy.clipboardPath` 的处置）
/// ⇒ 判据写在视图里就永远跑不进单测。而它错了的样子只有两种——"把一张坏图说成 SVG"
/// 与"把真 SVG 说成加载失败"——**都只是一句文案不准**、都不会报错，
/// 正好是最该用断言钉住的那一类。
///
/// ## ⚠️ 与 `FilePreviewKind.imageExtensions` 的关系
///
/// 那一边从 2026-10-12 起就把 `svg` **排除在图片之外**（`FilePreviewTests` 钉住），
/// 理由是同一个：`UIImage` 画不了矢量图。两处判据**互相独立、结论一致** ——
/// 那边判"这个**文件**要不要走图片通道"（有路径可用），
/// 这边判"这段**字节**是不是 SVG"（只有内容可用，因为 markdown 里的地址可能没后缀）。
public enum MarkdownImageBytes {

    /// 这段字节看起来是不是 SVG。
    ///
    /// ## 判据
    ///
    /// SVG 是**文本**（XML），开头只有这几种形状：XML 声明、注释、`DOCTYPE`、空白，
    /// 然后才是根元素 `<svg`：
    ///
    /// ```xml
    /// <?xml version="1.0" encoding="UTF-8"?>
    /// <svg xmlns="http://www.w3.org/2000/svg" width="200" height="40">
    /// ```
    ///
    /// 所以判据是：**从头开始，只允许这些"序言"成分，然后必须出现 `<svg`**。
    /// 一旦撞上别的东西（正文、另一个标签）就判否 —— 那正是"开头含 `<svg` 字样的
    /// 普通文本"与"真 SVG"的分界（前者开头是 `<p>` 之类）。
    ///
    /// ## ⚠️ 三处有意"少做"
    ///
    /// 1. **只看前 1024 字节**：真去全文找 `<svg`，一份**讲解 SVG 的 Markdown 文档**
    ///    也会被判成 SVG。而 `<svg` 是根元素 ⇒ 对真实 SVG 文件它必然出现在最前面。
    /// 2. **只认 UTF-8 / ASCII**：UTF-16 编码的 SVG 判不出来（`<` 是 `00 3C`）。
    ///    那种文件在本项目的场景里不存在（GitHub 上渲染的 SVG 都是 UTF-8）。
    /// 3. **不做 XML 解析**：`XMLParser` 要引 `FoundationXML`、还要处理命名空间与错误恢复，
    ///    而这里要回答的只是一个布尔问题。
    ///
    /// - Parameter data: 取回的原始字节（`URLSession` 已解压过 `Content-Encoding`）。
    public static func looksLikeSVG(_ data: Data) -> Bool {
        let head = data.prefix(1024)
        guard !head.isEmpty else { return false }
        // ⚠️ 不用 `String(data:encoding:.utf8)`：它对非法字节**整个返回 nil**，
        //    而这里要的是"能读多少读多少"（一个开头有坏字节的 SVG 仍该被判出来）。
        //    `String(decoding:as:)` 把非法字节换成 U+FFFD、不失败。
        return hasSVGRoot(String(decoding: head, as: UTF8.self))
    }

    /// 从头扫序言成分，遇到 `<svg` 为真；遇到任何别的东西为假。
    private static func hasSVGRoot(_ text: String) -> Bool {
        svgRootRange(in: text) != nil
    }

    /// 找根元素 `<svg` 的**位置** —— 它只能出现在"序言之后"。
    ///
    /// 这条"只能出现在序言之后"就是 `looksLikeSVG` 那条判据的本体，
    /// 而 `declaredSize` 也**必须**走它（不能自己去全文搜 `<svg`）：
    /// 一份正文里写着"用 `<svg width="300" height="150">` 插一张图"的 Markdown 文档，
    /// 全文搜会把那串示例量成真尺寸。
    ///
    /// - Returns: `<svg` 这四个字符的范围（**不含**后面的属性与 `>`）；不是 SVG 根时 `nil`。
    private static func svgRootRange(in text: String) -> Range<String.Index>? {
        var index = text.startIndex

        func skipWhitespace() {
            while index < text.endIndex, text[index].isWhitespace || text[index] == "\u{FEFF}" {
                index = text.index(after: index)
            }
        }

        skipWhitespace()

        while index < text.endIndex {
            // 走到这里还没见到 `<svg` 却已经不是一个标签的开头 ⇒ 不是 SVG。
            guard text[index] == "<" else { return nil }
            let rest = text[index...]

            if rest.hasPrefix("<svg") {
                let after = text.index(index, offsetBy: 4)
                // ⚠️ 判一个边界：`<svgfoo>` 不是 svg 根（XML 的标签名到空白 / `>` / `/` 为止）。
                if let next = text[after...].first,
                   !(next.isWhitespace || next == ">" || next == "/") { return nil }
                return index..<after
            }

            // XML 声明 / 注释 / DOCTYPE —— 三种序言，各自跳到结尾再继续。
            let terminator: String
            if rest.hasPrefix("<?") {
                terminator = "?>"
            } else if rest.hasPrefix("<!--") {
                terminator = "-->"
            } else if rest.hasPrefix("<!") {
                terminator = ">"
            } else {
                // 别的标签（`<p>` / `<html>` …）⇒ 这一份不是 SVG。
                return nil
            }

            guard let end = rest.range(of: terminator) else { return nil }
            index = end.upperBound
            skipWhitespace()
        }

        return nil
    }

    // MARK: - 固有尺寸（2026-10-14 傍晚新增）

    /// 从 SVG 字节里读出它**自己声明的尺寸**。
    ///
    /// ## 为什么需要它（用户报回"占位图很大、尺寸不对"）
    ///
    /// `storytold/pdfcraft` 的 README 里那排状态徽章长这样：
    ///
    /// ```html
    /// <img alt="Written in Rust" src="https://img.shields.io/badge/written%20in-Rust-0a7563">
    /// ```
    ///
    /// **一个 `width` / `height` 都没写** ⇒ `MarkdownHTML.declaredImageSizes`
    /// 从 HTML 属性里拿不到尺寸 ⇒ 占位块落到那个"满宽 × 128"的兜底，
    /// 四块叠起来就是一排大白条。
    ///
    /// 但这张图**本该多大是知道的**：SVG 文件自己声明了 ——
    /// `<svg xmlns="…" width="98" height="20" …>`。**浏览器就是读它来摆位的**，
    /// 我们只是从来没往字节里看一眼。
    ///
    /// ## 判据
    ///
    /// 1. **`width` / `height` 属性优先**：纯数字、允许小数、允许 `px` 后缀，
    ///    四舍五入到整数（`189.5` → `190`，pt 尺度上那半个像素看不出来）。
    ///    ⚠️ **百分比不算**（`width="100%"`）—— 那要跟着容器算，而这一层不知道容器多宽。
    /// 2. **拿不到就退到 `viewBox`**：`viewBox="0 0 98 20"` 的后两个数是固有宽高。
    /// 3. **两个都拿不到 ⇒ `nil`**：调用方落回它自己的兜底，这一层不猜。
    ///
    /// ## ⚠️ 三处有意"少做"（与 `looksLikeSVG` 同一套取舍）
    ///
    /// 1. **只看前 4096 字节**：根元素必在最前面，而 SVG 正文里可能有几千行 `<path>`；
    ///    读得比 `looksLikeSVG` 那 1024 字节多一点，是因为根标签上可能挂着
    ///    `xmlns:xlink` 之类一长串属性。
    /// 2. **只认 UTF-8 / ASCII**（同 `looksLikeSVG`）。
    /// 3. **不做 XML 解析** —— 它要回答的只是"有多大"。
    ///
    /// ⚠️ **本函数自己就会先判"根元素是不是 `<svg`"**（走 `svgRootRange`）——
    /// 所以一份"正文里写着 `<svg width="300" height="150">`"的 Markdown 文档
    /// 量不出假尺寸（那串示例不在序言之后的位置上）。调用点仍按
    /// "先 `looksLikeSVG`、后 `declaredSize`"的顺序写，两道一起兜。
    public static func declaredSize(in data: Data) -> MarkdownImageSize? {
        let head = data.prefix(4096)
        guard !head.isEmpty else { return nil }
        let text = String(decoding: head, as: UTF8.self)
        guard let root = svgRootRange(in: text) else { return nil }
        // 从 `<svg` 往后扫到这一对标签的收尾 `>`。
        // ⚠️ 引号里的 `>` 不算收尾 —— 徽章的 `aria-label` 里完全可能出现它，
        //    而扫错了会读不到属性、静默退回"满宽 128"的兜底。
        //    这套扫描与 `MarkdownHTML` 共用一份实现（那边注释里有同样的告诫）。
        guard let close = MarkdownHTML.tagEnd(in: text, from: root.lowerBound) else { return nil }
        let tag = String(text[root.lowerBound..<close])

        let attributes = MarkdownHTML.attributes(in: tag)
        let width = dimension(attributes["width"])
        let height = dimension(attributes["height"])

        // 两项都拿到了就不必再看 viewBox。
        // ⚠️ 只拿到一项时仍要看 —— `width="200"` 配 `viewBox` 是很常见的写法，
        //    而"只有宽没有高"正是那张 logo 的处境（下面 `MarkdownImage` 拿它算宽高比）。
        let box = viewBoxSize(attributes["viewbox"])
        let size = MarkdownImageSize(width: width ?? box?.width, height: height ?? box?.height)
        return size.isEmpty ? nil : size
    }

    /// `width` / `height` 属性的值 → 整数。**只认纯数字**（可带小数、可带 `px`）。
    private static func dimension(_ text: String?) -> Int? {
        guard var value = text?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if value.hasSuffix("px") {
            value = String(value.dropLast(2)).trimmingCharacters(in: .whitespaces)
        }
        // ⚠️ 自己拦一道：`Double("1.2.3")` 返回 nil 没问题，但 `%` / `em` / `auto`
        //    也必须在这里挡掉 —— 它们不是像素值，猜一个数比不猜更糟。
        guard value.contains(where: \.isNumber), value.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        guard let number = Double(value), number > 0, number.isFinite else { return nil }
        return Int(number.rounded())
    }

    /// `viewBox="min-x min-y width height"` 里的那两个宽高。
    private static func viewBoxSize(_ text: String?) -> MarkdownImageSize? {
        guard let text else { return nil }
        // 逗号与空白都有人用（SVG 规范两者都允许）。
        let parts = text.split { $0 == " " || $0 == "," || $0 == "\t" || $0 == "\n" }
        guard parts.count == 4 else { return nil }
        guard let width = Double(parts[2]), let height = Double(parts[3]),
              width > 0, height > 0 else { return nil }
        return MarkdownImageSize(width: Int(width.rounded()), height: Int(height.rounded()))
    }
}
