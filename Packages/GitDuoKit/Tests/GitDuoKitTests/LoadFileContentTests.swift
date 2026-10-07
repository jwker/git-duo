import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

// MARK: - 替身

/// `RepoContentsDataSource` 的脚本化替身 —— 领域层测试用它，**不碰 HTTP**。
///
/// ⚠️ 本套件的**主要断言对象是两个调用计数器**，不是返回值。
/// 决策 #54 的全部意义是"某些档位**一个请求都不发**"、以及"另一些档位**只多发一趟
/// 而不是两趟**"，而这两件事**只能靠计数看出来** —— 判定写错时页面照样渲染出东西：
/// 要么白拉一趟大字节流进内存，要么反过来（一片空白、且不报错）。
actor ScriptedContentsSource: RepoContentsDataSource {

    /// 一次请求的记录。用结构体而不是元组 —— Swift 的 key path 不能指向元组元素。
    struct Call: Equatable, Sendable {
        let path: String
        let ref: String?
    }

    enum Reply {
        case payload(ContentsPayload)
        case error(GitHubError)
    }

    private let contentsReply: Reply
    private let rawReply: Data

    private(set) var contentsCalls: [Call] = []
    private(set) var rawCalls: [Call] = []

    init(contents: Reply = .error(.notFound), raw: Data = Data()) {
        self.contentsReply = contents
        self.rawReply = raw
    }

    func contents(
        owner: String,
        repo: String,
        path: String,
        ref: String?
    ) async throws -> ContentsPayload {
        contentsCalls.append(Call(path: path, ref: ref))
        switch contentsReply {
        case let .payload(payload): return payload
        case let .error(error): throw error
        }
    }

    func rawFile(
        owner: String,
        repo: String,
        path: String,
        ref: String?
    ) async throws -> Data {
        rawCalls.append(Call(path: path, ref: ref))
        return rawReply
    }

    func readme(owner: String, repo: String, ref: String?) async throws -> String? { nil }
}

/// 「服务端会回一个单文件 payload」这条答复的最小构造器（默认 `path == name`）。
private func payload(
    _ name: String,
    path: String? = nil,
    sha: String = "sha-srv",
    size: Int,
    encoding: String? = nil,
    content: String? = nil
) -> ScriptedContentsSource.Reply {
    .payload(
        .file(
            RepoFileDTO(
                name: name,
                path: path ?? name,
                sha: sha,
                size: size,
                encoding: encoding,
                content: content
            )
        )
    )
}

/// 文件查看页的取数（§4.5、决策 #54 / §9.5）。
///
/// 这一层要钉住的是**发了几趟请求、发给谁**：
/// - `.text`（≤1MB）⇒ 一趟 `contents`，base64 就在响应里；
/// - `.largeText` / `.image` ⇒ 一趟 raw（`blobSHA` + `size` 都已知时），否则先补一趟 `contents`；
/// - `.unsupported` ⇒ **零请求**（决策 #54 存在的全部理由）。
@Suite("文件取数 · 三档降级与两趟救援")
struct LoadFileContentTests {

    // MARK: - 不下载的那一档

    @Test("⚠️ 二进制：`contents` 与 `raw` **各一次都不发** —— 决策 #54 的全部意义")
    func binarySendsNoRequestAtAll() async throws {
        let source = ScriptedContentsSource()

        let outcome = try await LoadFileContent(contents: source).load(
            fullName: "octocat/hello", path: RepoPath(path: "Assets/icon.zip"), size: 40_000
        )

        #expect(outcome.unsupportedReason == .binary)
        #expect(await source.contentsCalls.isEmpty)
        #expect(await source.rawCalls.isEmpty)
    }

    @Test("⚠️ 调用方**已经知道** size 且图片超限 ⇒ 仍然零请求（第一道判定没有被「重判」破坏）")
    func knownOversizedImageSendsNoRequestAtAll() async throws {
        let source = ScriptedContentsSource()

        let outcome = try await LoadFileContent(contents: source).load(
            fullName: "octocat/hello", path: RepoPath(path: "design/hero.png"), size: 9_000_000
        )

        #expect(outcome.unsupportedReason == .imageTooLarge)
        #expect(await source.contentsCalls.isEmpty)
        #expect(await source.rawCalls.isEmpty)
    }

    // MARK: - size 重判（6.4 补的那个缺陷）

    @Test("⚠️ 调用方**不知道** size 时，图片要在拿到真实字节数后**重判一次**：20MB 的 PNG 一个字节都不下载")
    func reDecidesImageAfterMetadata() async throws {
        let source = ScriptedContentsSource(
            contents: payload("screenshot.png", path: "docs/screenshot.png", size: 20_000_000),
            raw: Data([0x89, 0x50, 0x4E, 0x47])
        )

        let outcome = try await LoadFileContent(contents: source).load(
            fullName: "octocat/hello",
            path: RepoPath(path: "docs/screenshot.png"),
            ref: "release/2.0"
        )

        #expect(outcome.unsupportedReason == .imageTooLarge)
        // 这一条才是重点：判定落空时 raw 会被发出去，20MB 进内存只为发现它太大。
        #expect(await source.rawCalls.isEmpty)
        #expect(await source.contentsCalls.map(\.path) == ["docs/screenshot.png"])
    }

    @Test("重判用的是**同一个阈值**（`>` 而不是 `>=`）：恰好等于图片上限仍然预览")
    func reDecisionUsesSameThreshold() async throws {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let source = ScriptedContentsSource(
            contents: payload("big.png", size: FilePreviewKind.maxImageBytes),
            raw: bytes
        )

        let outcome = try await LoadFileContent(contents: source).load(
            fullName: "octocat/hello", path: RepoPath(path: "big.png"), size: nil
        )

        let content = try #require(outcome.content)
        #expect(content.preview == .image)
        #expect(await source.rawCalls.count == 1)
    }

    @Test("图片在阈值内 ⇒ 补一趟 raw 取字节，`size` / `blobSHA` 用**服务端**给的那份")
    func imageWithinLimitProceedsViaRaw() async throws {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let source = ScriptedContentsSource(
            contents: payload("logo.png", sha: "sha-logo", size: 3_000_000),
            raw: bytes
        )

        let outcome = try await LoadFileContent(contents: source).load(
            fullName: "octocat/hello", path: RepoPath(path: "logo.png"), size: nil
        )

        let content = try #require(outcome.content)
        #expect(content.preview == .image)
        #expect(content.blobSHA == "sha-logo")
        #expect(content.size == 3_000_000)
        #expect(content.text == nil, "图片没有「原文可复制」⇒ 那个按钮不该出现")
        guard case let .image(data) = content.body else {
            Issue.record("png 应当是 .image 正文")
            return
        }
        #expect(data == bytes)
        #expect(await source.rawCalls.count == 1)
    }

    // MARK: - raw 通道的两条入口

    @Test("`blobSHA` + `size` 都已知 ⇒ **跳过元数据那一趟**，直接 raw（一次 RTT）")
    func knownMetadataSkipsTheMetadataRoundTrip() async throws {
        let text = String(repeating: "x", count: 32)
        let source = ScriptedContentsSource(raw: Data(text.utf8))

        let outcome = try await LoadFileContent(contents: source).load(
            fullName: "octocat/hello",
            path: RepoPath(path: "Sources/huge.swift"),
            size: 2_000_000,
            blobSHA: "sha-known",
            ref: "main"
        )

        let content = try #require(outcome.content)
        #expect(content.preview == .largeText)
        #expect(content.text == text)
        #expect(content.blobSHA == "sha-known")
        #expect(await source.contentsCalls.isEmpty, "两个判据都在手上，没有理由再问一次元数据")
        #expect(await source.rawCalls.map(\.ref) == ["main"], "⚠️ raw 少了 ref 会拿到默认分支的字节")
    }

    @Test("只有 size、没有 `blobSHA` ⇒ 先补一趟 `contents` 再走 raw（两趟），返回的 sha 来自服务端")
    func missingBlobSHACostsOneExtraRoundTrip() async throws {
        let text = String(repeating: "y", count: 64)
        let source = ScriptedContentsSource(
            contents: payload("huge.swift", path: "Sources/huge.swift", sha: "sha-srv", size: 2_000_000),
            raw: Data(text.utf8)
        )

        let outcome = try await LoadFileContent(contents: source).load(
            fullName: "octocat/hello",
            path: RepoPath(path: "Sources/huge.swift"),
            size: 2_000_000,
            ref: "feature/x"
        )

        let content = try #require(outcome.content)
        #expect(content.preview == .largeText)
        #expect(content.blobSHA == "sha-srv")
        #expect(content.size == 2_000_000)
        #expect(await source.contentsCalls.map(\.ref) == ["feature/x"])
        #expect(await source.rawCalls.map(\.ref) == ["feature/x"])
    }

    // MARK: - 小文本：一趟拿全

    @Test("小文本：base64 就在响应里 —— 只有一趟 `contents`，raw 一次都不走")
    func loadsSmallTextInline() async throws {
        let text = "let client = GitHubClient(token: store.load())\nprint(client)\n"
        let encoded = Data(text.utf8).base64EncodedString()
        let source = ScriptedContentsSource(
            contents: payload(
                "main.swift", path: "Sources/main.swift",
                sha: "sha-main", size: Data(text.utf8).count,
                encoding: "base64", content: encoded
            )
        )

        let outcome = try await LoadFileContent(contents: source).load(
            fullName: "octocat/hello", path: RepoPath(path: "Sources/main.swift"), size: nil
        )

        let content = try #require(outcome.content)
        #expect(content.preview == .text)
        #expect(content.text == text)
        #expect(content.blobSHA == "sha-main")
        #expect(await source.rawCalls.isEmpty)
        #expect(await source.contentsCalls.count == 1)
    }

    @Test("⚠️ 服务端说「内容没给你」（`encoding: none`）⇒ 补一趟 raw，**别渲染成一页空白**（§9.5 实测形状）")
    func recoversFromOmittedContentViaRaw() async throws {
        let text = String(repeating: "z", count: 128)
        let source = ScriptedContentsSource(
            // 实测：4,280,356 字节的文件回 200 + encoding "none" + content ""。
            contents: payload(
                "big.swift", path: "Sources/big.swift",
                sha: "sha-big", size: 4_280_356,
                encoding: "none", content: ""
            ),
            raw: Data(text.utf8)
        )

        let outcome = try await LoadFileContent(contents: source).load(
            fullName: "octocat/hello", path: RepoPath(path: "Sources/big.swift"), size: nil
        )

        let content = try #require(outcome.content)
        #expect(content.preview == .largeText)
        #expect(content.text == text)
        #expect(content.size == 4_280_356)
        #expect(await source.rawCalls.count == 1)
    }

    @Test("⚠️ 真正的空文件（`size: 0` + `content: \"\"`）⇒ 一页**空内容**，不是「解码失败」")
    func emptyFileIsEmptyContentNotUndecodable() async throws {
        let source = ScriptedContentsSource(
            contents: payload(
                "empty.txt", path: "empty.txt",
                sha: "sha-empty", size: 0,
                encoding: "base64", content: ""
            )
        )

        let outcome = try await LoadFileContent(contents: source).load(
            fullName: "octocat/hello", path: RepoPath(path: "empty.txt"), size: 0
        )

        let content = try #require(
            outcome.content,
            "空文件与「编码不认识」是两件事 —— 合成一档会让 0 字节的文件显示成「无法预览」"
        )
        #expect(content.text == "")
        #expect(content.preview == .text)
        #expect(content.size == 0)
        #expect(await source.rawCalls.isEmpty, "空文件走 raw 只会拿回同样一个空串")
    }

    // MARK: - `.undecodable`：下载了、但解不出

    @Test("⚠️ GBK 字节 ⇒ `.undecodable`，**不是**「不支持预览」—— 后者说在这里是假话")
    func gbkBytesYieldUndecodable() async throws {
        // "中文" 的 GBK 字节：不是合法 UTF-8。
        let gbk = Data([0xD6, 0xD0, 0xCE, 0xC4])
        let source = ScriptedContentsSource(
            contents: payload(
                "readme.txt", path: "readme.txt", sha: "sha-gbk", size: gbk.count,
                encoding: "base64", content: gbk.base64EncodedString()
            )
        )

        let outcome = try await LoadFileContent(contents: source).load(
            fullName: "octocat/hello", path: RepoPath(path: "readme.txt"), size: gbk.count
        )

        #expect(outcome.hasContent == false)
        // 这一条是 `.undecodable` 的判据：字节**已经下载过了**，
        // 所以不能给「App 不下载它的内容」那句话（那是假话）。
        #expect(outcome.unsupportedReason == nil)
        #expect(await source.contentsCalls.count == 1)
    }

    @Test("⚠️ raw 通道同样会给 `.undecodable` —— 扩展名说是文本、字节却不是（不是只改了名字那一侧）")
    func rawChannelAlsoYieldsUndecodable() async throws {
        let source = ScriptedContentsSource(raw: Data([0xD6, 0xD0, 0xCE, 0xC4]))

        let outcome = try await LoadFileContent(contents: source).load(
            fullName: "octocat/hello",
            path: RepoPath(path: "docs/notes.md"),
            size: 2_000_000,
            blobSHA: "sha-md"
        )

        #expect(outcome.hasContent == false)
        #expect(outcome.unsupportedReason == nil)
        #expect(await source.rawCalls.count == 1)
    }

    // MARK: - 形状与错误

    @Test("`contents` 回来的是一组条目（这个 path 其实是目录）⇒ 「不支持预览」，**不是**一次解码失败")
    func directoryPayloadYieldsUnsupported() async throws {
        let source = ScriptedContentsSource(
            contents: .payload(.directory([
                ContentEntryDTO(name: "a.swift", path: "Sources/a.swift", sha: "s1", size: 10, type: .file)
            ]))
        )

        let outcome = try await LoadFileContent(contents: source).load(
            fullName: "octocat/hello", path: RepoPath(path: "Sources/a.swift"), size: 10
        )

        #expect(outcome.unsupportedReason == .binary)
        #expect(await source.rawCalls.isEmpty)
    }

    @Test("⚠️ 读文件失败要**如实抛** —— README 那处的「吞 404」在这里不成立")
    func propagatesNotFound() async throws {
        let source = ScriptedContentsSource(contents: .error(.notFound))

        await #expect(throws: GitHubError.notFound) {
            _ = try await LoadFileContent(contents: source).load(
                fullName: "octocat/hello", path: RepoPath(path: "gone.md"), size: 10
            )
        }
    }

    @Test("`fullName` 里没有 `/` ⇒ 抛形状错误，且一个请求都不发")
    func rejectsMalformedFullName() async throws {
        let source = ScriptedContentsSource()

        await #expect(throws: RepositoryMappingError.malformedFullName("octocat")) {
            _ = try await LoadFileContent(contents: source).load(
                fullName: "octocat", path: RepoPath(path: "README.md"), size: 10
            )
        }
        #expect(await source.contentsCalls.isEmpty)
        #expect(await source.rawCalls.isEmpty)
    }
}
