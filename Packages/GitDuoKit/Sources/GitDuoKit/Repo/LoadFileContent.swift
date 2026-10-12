import Foundation
import GitHubAPI

/// 文件查看页（§4.5）的取数 —— **决策 #54 的三档降级**。
///
/// ## 一个文件可能走三条路，走哪条**在发请求之前**就定了
///
/// | 档 | 依据 | 请求 |
/// |---|---|---|
/// | `.text`（≤1MB） | 扩展名在白名单 + `size` 不超上限 | `contents`（base64 就在响应里） |
/// | `.largeText`（>1MB） | 同上但超上限 | `Accept: application/vnd.github.raw` |
/// | `.image` | 图片扩展名 + `size` 不超 `maxImageBytes` | 同上（要字节才能解码） |
/// | `.unsupported` | 其余二进制 / 超限图片 | **一个请求都不发** |
///
/// 判定本身是纯函数（`FilePreviewKind.decide`），本类型只负责**照它说的发对的请求**。
///
/// ## ⚠️ 为什么允许"第二次请求"（`.text` 拿到空壳时改走 raw）
///
/// `size` 可能小于真实值：调用方只有文件名（从提交详情点进来），或者服务端给了
/// 一个陈旧的大小。此时 `contents` 会回 **200 + `encoding: "none"` + 空 `content`**
/// —— 一个"内容没给你"的显式信号（§9.5 实测 4,280,356 字节的文件就是这个形状）。
/// 那条路**还有救**：补一次 raw，只多一个 RTT。
///
/// 反过来（先把所有文件都按大文件处理、一律走 raw）看起来更省事，
/// 但它会让每个 2KB 的 `.swift` 也走 raw —— 而 raw 的响应没有 JSON 外壳，
/// 拿不到 `blobSHA`，切片 8 的编辑器就没有乐观锁的基准了。
public struct LoadFileContent: Sendable {

    private let contents: any RepoContentsDataSource

    public init(contents: any RepoContentsDataSource) {
        self.contents = contents
    }

    /// 取一个文件该显示的东西。
    ///
    /// - Parameters:
    ///   - path: 仓库内路径（末段就是文件名 —— 判定只看它）。
    ///   - size: 调用方知道的字节数；**不知道就传 `nil`**（走"按名字判"那一档）。
    ///   - blobSHA: 调用方知道的 blob SHA（目录行 `TreeEntry.sha` 有它）；
    ///     不知道就传 `nil` ⇒ 本方法补一次 `contents` 去拿（见类型说明）。
    ///   - ref: 当前分支。**必须传**，否则看到的是默认分支的内容。
    ///
    /// - Throws: `RepositoryMappingError.malformedFullName` 与请求本身的错误。
    ///   ⚠️ README 那处的"吞 404"在这里**不成立**：文件不存在就是不存在，
    ///   要如实说（`FileCopy` 没有"这个文件不见了"以外的解释）。
    public func load(
        fullName: String,
        path: RepoPath,
        size: Int? = nil,
        blobSHA: String? = nil,
        ref: String? = nil
    ) async throws -> FileViewOutcome {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let preview = FilePreviewKind.decide(name: path.displayName, size: size)

        // ── 不下载的那一档：连请求都不发（决策 #54 的全部意义）。
        if case let .unsupported(reason) = preview { return .unsupported(reason) }

        if case .text = preview {
            return try await loadInlineText(owner: owner, repo: repo, path: path, ref: ref)
        }

        // ── 大文本 / 图片：raw 取字节。sha 与 size 优先用调用方给的（一次 RTT）。
        if let blobSHA, let size {
            let bytes = try await contents.rawFile(
                owner: owner, repo: repo, path: path.raw, ref: ref
            )
            return Self.outcome(preview: preview, path: path, sha: blobSHA, size: size, bytes: bytes)
        }

        // 调用方不知道 ⇒ 先问一次 `contents` 拿元数据。
        // ⚠️ 这一次是**轻的**：>1MB 的文本回空壳、图片也只要它的 `sha` / `size`，
        //    两个大字节流不会同时进内存。
        guard let dto = try await filePayload(owner: owner, repo: repo, path: path, ref: ref) else {
            return .unsupported(.binary)
        }

        // ⚠️ **拿到真实字节数之后要重判一次**，不能用上面那个按名字算出来的 `preview`。
        //
        // 走到这里的 `size` 通常是 `nil`（调用方只有文件名），而 `decide(name:size:)`
        // 在 `size == nil` 时**按名字那一侧**处理：图片一律 `.image`。于是"先看 size
        // 再决定下不下"这条（`FilePreviewKind` 的类型说明点名的那条）就落空了 ——
        // 一张 20MB 的 PNG 会被整张拉进内存，只为发现它太大然后丢掉。
        //
        // 这不是"判定挪到了发请求之后"：第一次请求（`contents`）本身就是为了拿到判据。
        // 重判落在**第二个请求（raw）之前** —— 那一趟才是可能拉大字节流的那趟。
        // 文本侧不受影响：未知大小的文本走的是 `loadInlineText`，到不了这里。
        let sized = FilePreviewKind.decide(name: path.displayName, size: dto.size)
        if case let .unsupported(reason) = sized { return .unsupported(reason) }

        let bytes = try await contents.rawFile(
            owner: owner, repo: repo, path: path.raw, ref: ref
        )
        return Self.outcome(preview: sized, path: path, sha: dto.sha, size: dto.size, bytes: bytes)
    }

    // MARK: - 内部

    /// 小文本：base64 就在响应里，一次请求拿全。
    private func loadInlineText(
        owner: String,
        repo: String,
        path: RepoPath,
        ref: String?
    ) async throws -> FileViewOutcome {
        guard let dto = try await filePayload(owner: owner, repo: repo, path: path, ref: ref) else {
            // 调用方只对**文件**调本方法（目录行走"进下一级"）。服务端行为若变了
            // （`path` 回了数组），这里给"看不了"，而不是把整页变成一次解码失败。
            return .unsupported(.binary)
        }

        // ⚠️ 服务端明确说"内容没给你" ⇒ 我们的 size 判小了（或没有 size）
        //    ⇒ 改走 raw。这条路**还有救**（§9.5），别在这里判成"空文件"。
        if FileContentCodec.isContentOmitted(
            encoding: dto.encoding, base64: dto.content, size: dto.size
        ) {
            let bytes = try await contents.rawFile(
                owner: owner, repo: repo, path: path.raw, ref: ref
            )
            return Self.outcome(
                preview: .largeText, path: path, sha: dto.sha, size: dto.size, bytes: bytes
            )
        }

        guard let data = decodedBytes(dto) else {
            // base64 解不开（或 `content` 缺席、`size` 又不是 0）：**不是空文件**。
            return .undecodable
        }
        guard let content = RepoFileMapper.fileContent(dto, bytes: data) else {
            return .undecodable
        }
        return .content(content)
    }

    /// 这次响应里**能解出的字节**。
    ///
    /// ## ⚠️ 0 字节的文件与「内容没给」是两件事（6.4e 修正的真缺陷）
    ///
    /// 空文件的响应是 `size: 0` + `content: ""`。`isContentOmitted` 会**放行**它
    /// （第二条件是 `size > 0`，正好把它排掉）—— 这一步是对的，空文件走 raw
    /// 只会拿回同样一个空串，白费一趟。
    ///
    /// 但接下来那步踩了坑：`decodeBase64("")` 返回 **`nil`**（空串不是任何字节的
    /// base64 表示，这是 `FileContentCodec` 有意为之且被单测钉住的），于是
    /// `content.flatMap(…)` 也是 `nil` ⇒ 落进 `.undecodable`。
    /// **用户看到的是一个 0 字节的文件被说成「这个 App 不认识它的编码」** ——
    /// 那是假话，而且他连那个空文件都看不到。
    ///
    /// 所以在这里显式认成"零个字节"，让它走与其它文本**完全相同**的组装路径
    /// （`text(from: Data())` 是合法的空串，不是失败）。
    /// ⚠️ 修法**不是**去改 `decodeBase64("") == nil` —— 那条约定是对的，
    /// 它拦的正是"把解不出来当成空文件"这件更常见的事。
    private func decodedBytes(_ dto: RepoFileDTO) -> Data? {
        if dto.size == 0, dto.content?.isEmpty ?? true { return Data() }
        return dto.content.flatMap(FileContentCodec.decodeBase64)
    }

    /// 取单文件 payload；`path` 回的是数组（= 目录）时给 `nil`。
    private func filePayload(
        owner: String,
        repo: String,
        path: RepoPath,
        ref: String?
    ) async throws -> RepoFileDTO? {
        try await contents.contents(owner: owner, repo: repo, path: path.raw, ref: ref).file
    }

    /// 字节 + 判定 → 可显示的内容。
    ///
    /// ⚠️ **不按"UTF-8 解码失败"判二进制**（§9.5）：走到这里说明字节**已经在手上**、
    /// 且扩展名说它是文本。解不出来只有两种可能：这个 App 不认识它的编码（GBK 等），
    /// 或者扩展名骗了我们。两种都不该被说成"二进制文件，App 不下载它"——
    /// 那个说法在这里是**假话**（我们已经下载了）。所以给 `.undecodable` 一档。
    private static func outcome(
        preview: FilePreviewKind,
        path: RepoPath,
        sha: String,
        size: Int,
        bytes: Data
    ) -> FileViewOutcome {
        switch preview {
        case let .unsupported(reason):
            // 调用方已提前返回（那个分支一个请求都不发）—— 这里只是穷尽 switch。
            return .unsupported(reason)

        case .image:
            return .content(FileContent(
                path: path, blobSHA: sha, size: size, body: .image(bytes),
                preview: preview, markdown: nil
            ))

        case .text, .largeText:
            guard let text = FileContentCodec.text(from: bytes) else { return .undecodable }
            return .content(FileContent(
                path: path, blobSHA: sha, size: size, body: .text(text),
                preview: preview,
                // ⚠️ 大文本（`.largeText`，>1MB 走 raw）**也照样渲染** —— 用户裁定
                //    ">1MB 的 md 一并渲染"（走查第 57 条）。所以这一支不按 preview 分档，
                //    只看路径是不是 markdown（`MarkdownFile`）。
                markdown: MarkdownFile.document(path: path, text: text)
            ))
        }
    }
}

/// 文件查看页的三种结局。
///
/// ⚠️ **`.unsupported` 与 `.undecodable` 必须分开**：前者是"按判定**没下载**"，
/// 后者是"下载了但解不出来"。合成一档的后果是文案必须二选一，
/// 而两边的说法在对方的场景里都是错的：
/// - 对没下载的二进制说"不认识它的编码" ⇒ 用户以为下载过了、以为再试一次能好；
/// - 对 GBK 文件说"App 不下载它的内容" ⇒ **假话**，我们刚刚下载了它。
public enum FileViewOutcome: Sendable {

    /// 可以显示（文本或图片）。
    case content(FileContent)

    /// 判定为不下载（二进制 / 图片超限），给「不支持预览」+ 网页端出口。
    case unsupported(FilePreviewKind.Reason)

    /// 字节到手了，但解不成 UTF-8 文本（GBK / Big5 / 扩展名与内容不符）。
    case undecodable

    /// 可显示的内容；其余两档为 `nil`。
    public var content: FileContent? {
        if case let .content(content) = self { return content }
        return nil
    }

    /// 不下载的原因；其余两档为 `nil`。
    public var unsupportedReason: FilePreviewKind.Reason? {
        if case let .unsupported(reason) = self { return reason }
        return nil
    }

    /// 有没有可显示的正文。
    public var hasContent: Bool { content != nil }
}
