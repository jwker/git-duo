import Foundation
import Testing

@testable import GitDuoKit

/// `MarkdownImageBytes` —— "这段字节是不是 SVG"（2026-10-14 新增）。
///
/// ## 这批用例在守什么
///
/// 它只在**解码失败之后**被问一句（见 `MarkdownImageBytes` 的类型说明），
/// 而它错了的样子只有两种 —— **都只是一句文案不准**、都不报错：
///
/// | 判错的方向 | 用户看到的 |
/// |---|---|
/// | 把不是 SVG 的判成 SVG | 「SVG 图片」出现在一张坏掉的 PNG 上（说法怪，但不致命） |
/// | 把真 SVG 判漏 | 又回到「图片加载失败」——**排查方向被指错**（这正是 2026-10-14 那条缺陷） |
///
/// 两种都不报错 ⇒ 正好是最该用断言钉住的那一类。
/// 判据与"三处有意少做"写在 `MarkdownImageBytes` 的类型说明里。
@Suite("MarkdownImageBytes · SVG 嗅探")
struct MarkdownImageBytesTests {

    private func data(_ text: String) -> Data {
        Data(text.utf8)
    }

    // MARK: - 是 SVG

    @Test("最短的一支：直接以根元素开头")
    func bareRootElement() {
        #expect(MarkdownImageBytes.looksLikeSVG(data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>")))
    }

    @Test("shields.io 的真实形状：XML 声明 + 注释 + 根元素")
    func shieldsIoShape() {
        // `curl https://img.shields.io/badge/Rust-100%25-orange` 开头那几行。
        let svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- Generator: Adobe Illustrator 24.0.0, SVG Export Plug-In . SVG Version: 6.00 Build 0)  -->
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="104" height="20">
        """
        #expect(MarkdownImageBytes.looksLikeSVG(data(svg)))
    }

    @Test("DOCTYPE 也认（`<!DOCTYPE svg …>`）")
    func doctypePreamble() {
        #expect(MarkdownImageBytes.looksLikeSVG(
            data("<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" \"http://www.w3.org/x.dtd\">\n<svg>")
        ))
    }

    @Test("开头有空白 / BOM 也算（XML 允许前导空白）")
    func leadingWhitespaceAndBOM() {
        #expect(MarkdownImageBytes.looksLikeSVG(data("   \n\t<svg></svg>")))
        #expect(MarkdownImageBytes.looksLikeSVG(data("\u{FEFF}<svg></svg>")))
    }

    @Test("`<svg/>`、`<svg >`、`<svg`（文件到此为止）都算")
    func rootElementBoundaries() {
        #expect(MarkdownImageBytes.looksLikeSVG(data("<svg/>")))
        #expect(MarkdownImageBytes.looksLikeSVG(data("<svg >")))
        #expect(MarkdownImageBytes.looksLikeSVG(data("<svg")))
    }

    // MARK: - 不是 SVG

    @Test("⚠️ `<svgfoo>` **不是** svg 根（XML 的标签名到空白 / `>` / `/` 为止）")
    func similarElementNameIsNotSVG() {
        #expect(MarkdownImageBytes.looksLikeSVG(data("<svgfoo>x</svgfoo>")) == false)
        #expect(MarkdownImageBytes.looksLikeSVG(data("<svg:rect/>")) == false)
    }

    @Test("⚠️ 开头是别的标签 ⇒ 不是（这就是\"开头含 `<svg` 字样的普通文本\"那条分界）")
    func otherRootElementIsNotSVG() {
        #expect(MarkdownImageBytes.looksLikeSVG(data("<p>关于 svg 的说明</p><svg>")) == false)
        #expect(MarkdownImageBytes.looksLikeSVG(data("<html><body><svg></svg></body></html>")) == false)
        #expect(MarkdownImageBytes.looksLikeSVG(data("<!-- c --><p>x</p>")) == false)
    }

    @Test("正文里提到 `<svg` 的 markdown 文档不算")
    func proseMentioningSVGIsNotSVG() {
        #expect(MarkdownImageBytes.looksLikeSVG(data("# 如何写 SVG\n\n用 `<svg>` 标签。")) == false)
    }

    @Test("真正的位图不算 —— PNG 的魔数开头")
    func pngMagicIsNotSVG() {
        // PNG：89 50 4E 47 0D 0A 1A 0A
        #expect(MarkdownImageBytes.looksLikeSVG(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) == false)
    }

    @Test("JPEG 的魔数也不算")
    func jpegMagicIsNotSVG() {
        #expect(MarkdownImageBytes.looksLikeSVG(Data([0xFF, 0xD8, 0xFF, 0xE0])) == false)
    }

    @Test("空字节数组、以及全是空白 ⇒ 不是")
    func emptyInput() {
        #expect(MarkdownImageBytes.looksLikeSVG(Data()) == false)
        #expect(MarkdownImageBytes.looksLikeSVG(data("   \n\t ")) == false)
    }

    @Test("坏字节不致命（`String(decoding:)` 把非法字节换成替换符、不返回 nil）")
    func invalidBytesDoNotCrash() {
        var bytes = Data([0x3C, 0x73, 0x76, 0x67, 0x3E])  // `<svg>`
        bytes.append(contentsOf: [0xFF, 0xFE, 0x00])
        #expect(MarkdownImageBytes.looksLikeSVG(bytes))
    }

    // MARK: - 已登记的少做

    @Test("⚠️ 登记：只看前 1024 字节 ⇒ 一份**讲解 SVG 的长文**不会被误判")
    func onlyTheHeadIsScanned() {
        // 前面是一千多字节的说明文字，真正的 `<svg` 在后面 —— 判否。
        // 这是有意的：真去全文找 `<svg`，`README` 那种"讲 SVG 的文档"会被判成 SVG。
        let prose = String(repeating: "a", count: 1100) + "<svg>"
        #expect(MarkdownImageBytes.looksLikeSVG(data(prose)) == false)
    }

    @Test("⚠️ 登记：UTF-16 编码的 SVG **判不出来**（`<` 是 `00 3C`）")
    func utf16IsNotRecognized() {
        let utf16 = "<svg></svg>".data(using: .utf16)!
        #expect(MarkdownImageBytes.looksLikeSVG(utf16) == false)
    }

    // MARK: - 固有尺寸（2026-10-14 傍晚新增）

    /// 这一组守的是用户报回的"占位图很大、尺寸不对"：
    /// README 里那排徽章的 HTML **一个 `width` / `height` 都没写**，
    /// 占位块因此落到"满宽 × 128"的兜底 ⇒ 四块拼成一排大白条。
    /// 而 SVG 字节里其实写着它本该多大 —— 浏览器就是读它来摆位的。

    @Test("shields.io 徽章：`width` / `height` 直接读出来（真实形状，前面还有 `<title>` 与 `<rect>`）")
    func badgeSize() {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="98" height="20" role="img" aria-label="written in: Rust"><title>written in: Rust</title><rect width="98" height="20" rx="3"/></svg>"#
        #expect(MarkdownImageBytes.declaredSize(in: data(svg)) == MarkdownImageSize(width: 98, height: 20))
    }

    @Test("⚠️ 小数四舍五入（`189.5` → `190`）—— `?style=for-the-badge` 那种写法")
    func fractionalSizeIsRounded() {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="189.5" height="28" role="img"></svg>"#
        #expect(MarkdownImageBytes.declaredSize(in: data(svg)) == MarkdownImageSize(width: 190, height: 28))
    }

    @Test("`px` 后缀认（`width=\"96px\"`）")
    func pixelSuffix() {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="96px" height="24px"></svg>"#
        #expect(MarkdownImageBytes.declaredSize(in: data(svg)) == MarkdownImageSize(width: 96, height: 24))
    }

    @Test("⚠️ 百分比**不算**像素值 ⇒ 退到 `viewBox`（拿不到就宁可说不知道）")
    func percentageFallsBackToViewBox() {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 32 32"></svg>"#
        #expect(MarkdownImageBytes.declaredSize(in: data(svg)) == MarkdownImageSize(width: 32, height: 32))
    }

    @Test("只有 `viewBox` 也算 —— 空白分隔与逗号分隔都认")
    func viewBoxOnly() {
        let spaced = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 60"></svg>"#
        let commas = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0,0,64,48"></svg>"#
        #expect(MarkdownImageBytes.declaredSize(in: data(spaced)) == MarkdownImageSize(width: 120, height: 60))
        #expect(MarkdownImageBytes.declaredSize(in: data(commas)) == MarkdownImageSize(width: 64, height: 48))
    }

    @Test("⚠️ 只写了 `width` ⇒ **只给出宽**（高度那一维留给调用方按宽高比补）")
    func widthOnly() {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="200"></svg>"#
        #expect(MarkdownImageBytes.declaredSize(in: data(svg)) == MarkdownImageSize(width: 200))
    }

    @Test("一处尺寸都没有 ⇒ `nil`（这一层不猜，落回调用方的兜底）")
    func noSizeAtAll() {
        #expect(MarkdownImageBytes.declaredSize(in: data(#"<svg xmlns="http://www.w3.org/2000/svg"></svg>"#)) == nil)
    }

    @Test("序言（XML 声明 + 注释）之后仍能量到")
    func sizeAfterPreamble() {
        let svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- Generator: Adobe Illustrator 24.0.0 -->
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="50">
        """
        #expect(MarkdownImageBytes.declaredSize(in: data(svg)) == MarkdownImageSize(width: 200, height: 50))
    }

    @Test("⚠️ 引号里的 `>` 不影响收尾判定（`aria-label` 里可能有它）")
    func angleBracketInsideAttribute() {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" aria-label="a > b" width="64" height="64"></svg>"#
        #expect(MarkdownImageBytes.declaredSize(in: data(svg)) == MarkdownImageSize(width: 64, height: 64))
    }

    /// ⚠️ 这条守的是**顺序**：`declaredSize` 单独用在**不是 SVG** 的文本上时必须说"不知道"。
    /// 若它自己去全文搜 `<svg`，一份"讲怎么插图"的文档会被量出那串示例的尺寸 ——
    /// 而那种错**不报错**，只让某张图的占位块莫名变得很大。
    @Test("⚠️ 正文里那把 `<svg width=…>` 当示例讲的文档，**量不出假尺寸**")
    func proseExampleIsNotMeasured() {
        let prose = data("# 说明\n\n用 `<svg width=\"300\" height=\"150\">` 插一张图。")
        #expect(MarkdownImageBytes.declaredSize(in: prose) == nil)
        #expect(MarkdownImageBytes.looksLikeSVG(prose) == false)
    }
}
