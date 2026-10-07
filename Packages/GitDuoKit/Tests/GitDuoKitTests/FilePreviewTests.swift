import Foundation
import Testing

@testable import GitDuoKit

/// 文件预览的三档降级（TECH_SPEC §9.5、决策 #54）。
///
/// ## 为什么这一套必须存在
///
/// 判定错了的表现是"页面一片空白"或"一屏乱码"，而两者都**不报错**：
/// - 把大文件判成 `.text` ⇒ 请求 contents，拿回 `encoding: "none"` + 空内容 ⇒ **空白页**；
/// - 把二进制判成 `.text` ⇒ 把字节当 UTF-8 渲染 ⇒ **乱码**；
/// - 把常见文本判成 `.unsupported` ⇒ 用户看不到 `Makefile` / `.gitignore`
///   （它们的 `pathExtension` 是空串，只靠扩展名表认不出来）。
@Suite("文件预览 · 三档降级 / 扩展名 / 大小上限")
struct FilePreviewTests {

    // MARK: - 阈值本身

    @Test("⚠️ 文本内联阈值**故意偏小**（取小了走 raw 照样成功；取大了会拿到空内容 ⇒ 空白页）")
    func inlineThresholdIsConservative() {
        #expect(FilePreviewKind.maxInlineTextBytes == 1_000_000)
        // 断言它**小于** 1 MiB —— 这条是"故意偏小"的实锤。
        #expect(FilePreviewKind.maxInlineTextBytes < 1_048_576)
        #expect(FilePreviewKind.maxImageBytes == 5_000_000)
    }

    @Test("⚠️ 判定必须在发请求之前就能定：`decide` 只看名字与大小")
    func decisionNeedsOnlyNameAndSize() {
        // 这个签名本身就是"事前可判"的证明 —— 没有第三个参数。
        #expect(FilePreviewKind.decide(name: "a.swift", size: 10) == .text)
    }

    // MARK: - 文本

    @Test("普通文本：≤ 上限走内联，> 上限走 raw")
    func textBySize() {
        #expect(FilePreviewKind.decide(name: "a.swift", size: 1_000) == .text)
        #expect(FilePreviewKind.decide(name: "a.swift", size: FilePreviewKind.maxInlineTextBytes) == .text)
        #expect(
            FilePreviewKind.decide(name: "a.swift", size: FilePreviewKind.maxInlineTextBytes + 1) == .largeText
        )
        // 实测那个 4.2MB 的文件就是这个形状。
        #expect(FilePreviewKind.decide(name: "swagger.json", size: 4_280_356) == .largeText)
    }

    @Test("大小写不敏感的扩展名（`README.MD` 也是 Markdown）")
    func extensionIsCaseInsensitive() {
        #expect(FilePreviewKind.decide(name: "README.MD", size: 100) == .text)
        #expect(FilePreviewKind.decide(name: "Photo.PNG", size: 100) == .image)
        #expect(FilePreviewKind.extensionOf("README.MD") == "md")
    }

    @Test("路径只看最后一段（目录名里带点不能把扩展名带歪）")
    func onlyLastComponentCounts() {
        #expect(FilePreviewKind.extensionOf("docs/v1.2/guide.md") == "md")
        #expect(FilePreviewKind.fileNameOf("docs/v1.2/guide.md") == "guide.md")
        #expect(FilePreviewKind.decide(name: "docs.v2/README", size: 10) == .text)
    }

    // MARK: - 无扩展名的常见文本文件（最容易被漏掉的一类）

    @Test("⚠️ `Makefile` / `LICENSE` / `.gitignore` 这类**没有扩展名**的文件必须认成文本")
    func recognisesExtensionlessTextFiles() {
        for name in ["Makefile", "makefile", "Dockerfile", "LICENSE", "README", ".gitignore", ".env"] {
            #expect(
                FilePreviewKind.decide(name: name, size: 100) == .text,
                "「\(name)」应当被认成文本"
            )
            // 它们的 `pathExtension` 是空串 —— 这正是必须另建一张表的原因。
            #expect(FilePreviewKind.extensionOf(name).isEmpty)
        }
    }

    @Test("⚠️ `svg` 当**文本**而不是图片：iOS 的 `UIImage` 不渲染它，而它是一份可读的 XML")
    func svgIsTextNotImage() {
        #expect(FilePreviewKind.decide(name: "logo.svg", size: 2_000) == .text)
        #expect(FilePreviewKind.textExtensions.contains("svg"))
        #expect(FilePreviewKind.imageExtensions.contains("svg") == false)
    }

    // MARK: - 图片

    @Test("图片：≤ 上限走 raw 取字节；超上限不下载")
    func imageBySize() {
        #expect(FilePreviewKind.decide(name: "a.png", size: 500_000) == .image)
        #expect(FilePreviewKind.decide(name: "a.png", size: FilePreviewKind.maxImageBytes) == .image)
        #expect(
            FilePreviewKind.decide(name: "a.png", size: FilePreviewKind.maxImageBytes + 1)
                == .unsupported(.imageTooLarge)
        )
    }

    // MARK: - 其余二进制

    @Test("认不出来的扩展名 ⇒ 不下载、给「不支持预览」的出口")
    func unknownExtensionsAreUnsupported() {
        #expect(FilePreviewKind.decide(name: "a.zip", size: 100) == .unsupported(.binary))
        #expect(FilePreviewKind.decide(name: "a.dylib", size: 100) == .unsupported(.binary))
        #expect(FilePreviewKind.decide(name: "noextension", size: 100) == .unsupported(.binary))
    }

    @Test("⚠️ 超限图片与二进制**是两档**（用户的下一步不同：一个可换小图，一个这里根本打不开）")
    func imageTooLargeIsItsOwnReason() {
        let tooLarge = FilePreviewKind.decide(name: "big.png", size: 9_000_000)
        let binary = FilePreviewKind.decide(name: "x.bin", size: 100)

        #expect(tooLarge != binary)
        if case .unsupported(.imageTooLarge) = tooLarge {} else { Issue.record("应当是 imageTooLarge") }
        if case .unsupported(.binary) = binary {} else { Issue.record("应当是 binary") }
    }

    // MARK: - 大小未知（"从提交详情点进一个文件"那条路）

    @Test("⚠️ `size == nil` 时**按名字那一侧**处理，不判 `unsupported`（判 unsupported 没有救）")
    func unknownSizeFallsBackToName() {
        #expect(FilePreviewKind.decide(name: "a.swift", size: nil) == .text)
        #expect(FilePreviewKind.decide(name: "a.png", size: nil) == .image)
        // 认不出来的仍然不可预览 —— 这一档不因"缺 size"而放宽。
        #expect(FilePreviewKind.decide(name: "a.zip", size: nil) == .unsupported(.binary))
    }

    // MARK: - 派生属性

    @Test("要不要走 raw 通道 / 有没有内容可显示")
    func derivedFlags() {
        #expect(FilePreviewKind.text.needsRawChannel == false)
        #expect(FilePreviewKind.largeText.needsRawChannel)
        #expect(FilePreviewKind.image.needsRawChannel)
        #expect(FilePreviewKind.unsupported(.binary).needsRawChannel == false)

        #expect(FilePreviewKind.text.hasContent)
        #expect(FilePreviewKind.largeText.hasContent)
        #expect(FilePreviewKind.image.hasContent)
        #expect(FilePreviewKind.unsupported(.binary).hasContent == false)
    }
}
