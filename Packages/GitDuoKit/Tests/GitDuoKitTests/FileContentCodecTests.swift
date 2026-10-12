import Foundation
import Testing

@testable import GitDuoKit

/// contents 响应的解码规则（TECH_SPEC §9.5、决策 #54）。
///
/// 三条规则错了都**不会报错**：base64 带换行没剥 ⇒ 解码返回 `nil` ⇒ 被当成"空文件"；
/// `encoding: "none"` 没识别 ⇒ 显示一个空白页；行拆分把空行吃掉 ⇒ 行号全错。
@Suite("文件内容解码 · base64 / 空壳判定 / 文本 / 行拆分")
struct FileContentCodecTests {

    // MARK: - base64

    @Test("⚠️ GitHub 的 base64 **带换行**（每 60 字符一个）—— 不剥掉就解不出来")
    func decodesBase64WithEmbeddedNewlines() throws {
        let text = "let client = GitHubClient(token: store.load())\nprint(client)\n"
        let data = try #require(text.data(using: .utf8))
        let encoded = data.base64EncodedString()

        // 手工插入 GitHub 风格的分行（每 60 字符一个 `\n`）。
        var chunked = ""
        var index = encoded.startIndex
        while index < encoded.endIndex {
            let end = encoded.index(index, offsetBy: 60, limitedBy: encoded.endIndex) ?? encoded.endIndex
            chunked += encoded[index..<end] + "\n"
            index = end
        }

        #expect(chunked.contains("\n"))
        // 直接用 Foundation 解那串带换行的会失败 —— 这就是必须自己剥的原因。
        #expect(Data(base64Encoded: chunked) == nil)

        let decoded = try #require(FileContentCodec.decodeBase64(chunked))
        #expect(FileContentCodec.text(from: decoded) == text)
    }

    @Test("空串（空文件的 `content`）与空白串都解不出东西，返回 `nil` 而不是一个空 `Data`")
    func emptyBase64DecodesToNil() {
        // ⚠️ 返回 `Data()` 会让调用方以为"解码成功、文件是空的"，
        //    而真实情况是"服务端没给内容"（那要走 raw 回退）。
        #expect(FileContentCodec.decodeBase64("") == nil)
        #expect(FileContentCodec.decodeBase64("\n  \n") == nil)
    }

    @Test("真·空文件（大小 0）里也有内容的情况：`content` 是空串的 base64（`\"\"`）")
    func genuineEmptyFileIsDistinguishedFromOmitted() {
        // 0 字节文件的 base64 是空串 ⇒ `decodeBase64` 返回 nil，这是**对的**：
        // 它确实没有内容。它与"服务端没给"的区别在 `isContentOmitted` 那一侧判（见下）。
        #expect(FileContentCodec.decodeBase64("") == nil)
    }

    // MARK: - 空壳判定

    @Test("⚠️ `encoding: \"none\"` ⇒ 是空壳（大文件的官方表示，实测 4,280,356 字节的文件回这个）")
    func noneEncodingMeansOmitted() {
        #expect(
            FileContentCodec.isContentOmitted(encoding: "none", base64: "", size: 4_280_356)
        )
        // 大小写不敏感（防御）。
        #expect(FileContentCodec.isContentOmitted(encoding: "NONE", base64: "", size: 100))
    }

    @Test("⚠️ 第二条防御判据：`size > 0` 但没有 `content` ⇒ 也当空壳（`encoding` 是字符串，会变）")
    func missingContentWithNonZeroSizeIsOmitted() {
        #expect(FileContentCodec.isContentOmitted(encoding: "base64", base64: "", size: 500))
        #expect(FileContentCodec.isContentOmitted(encoding: nil, base64: nil, size: 500))
    }

    @Test("⚠️ 真·空文件（`size == 0` 且没有内容）**不是**空壳 —— 去 raw 只会白费一次请求")
    func genuineEmptyFileIsNotOmitted() {
        #expect(FileContentCodec.isContentOmitted(encoding: "base64", base64: "", size: 0) == false)
        #expect(FileContentCodec.isContentOmitted(encoding: nil, base64: nil, size: 0) == false)
    }

    @Test("有内容时当然不是空壳")
    func contentPresentIsNotOmitted() {
        #expect(FileContentCodec.isContentOmitted(encoding: "base64", base64: "aGk=", size: 2) == false)
    }

    // MARK: - 文本解码

    @Test("UTF-8 解得出就解；解不出返回 `nil`（**不做有损解码** —— 一堆 `�` 会被读成「文件坏了」）")
    func textDecodingIsStrict() throws {
        #expect(FileContentCodec.text(from: Data("hello".utf8)) == "hello")

        // 一个非 UTF-8 的字节序列（GBK 里"中文"的头两个字节）。
        let gbk = Data([0xC4, 0xE3, 0xBA, 0xC3])
        #expect(FileContentCodec.text(from: gbk) == nil)
        // 对照：有损解码会给出一个带替换字符的串 —— 那一串会被用户读成"文件坏了"。
        #expect(String(decoding: gbk, as: UTF8.self).contains("\u{FFFD}"))
    }

    // MARK: - 行拆分

    @Test("⚠️ 行拆分**保留空行**（丢掉它们会让行号整体错位，而这是用户定位代码的唯一手段）")
    func linesKeepEmptyLines() {
        let text = "a\n\nb\n\n\nc"

        #expect(FileContent.lines(of: text) == ["a", "", "b", "", "", "c"])
    }

    @Test("末尾换行不产生一条多余的空行（否则行号会多一号、代码块底部多一空行）")
    func trailingNewlineDoesNotAddALine() {
        #expect(FileContent.lines(of: "a\nb\n") == ["a", "b"])
        #expect(FileContent.lines(of: "a\nb") == ["a", "b"])
        // 只有换行 = 全是空行的文件（`\n\n`）⇒ 两条空行（末尾那条不算）。
        #expect(FileContent.lines(of: "\n\n") == ["", ""])
        #expect(FileContent.lines(of: "") == [])
    }

    @Test("`\\r\\n` 归一成 `\\n`（Windows 检出的文件很常见）")
    func normalisesCarriageReturns() {
        #expect(FileContent.lines(of: "a\r\nb\r\n") == ["a", "b"])
        // 只剩 `\r` 的老 Mac 换行不在处理范围（本项目的仓库里不会有），
        // 但断言它不会崩、也不会被当成换行。
        #expect(FileContent.lines(of: "a\rb") == ["a\rb"])
    }

    // MARK: - 模型

    @Test("`FileContent.text` 只对文本正文有值（图片没有「原文可复制」，`Raw` 按钮在图片上不出现）")
    func textIsNilForImages() {
        let text = FileContent(
            path: RepoPath(path: "a.swift"), blobSHA: "s", size: 3,
            body: .text("abc"), preview: .text, markdown: nil
        )
        let image = FileContent(
            path: RepoPath(path: "a.png"), blobSHA: "s", size: 3,
            body: .image(Data([1, 2, 3])), preview: .image, markdown: nil
        )

        #expect(text.text == "abc")
        #expect(image.text == nil)
    }
}
