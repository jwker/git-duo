import Foundation
import GitHubAPI

/// 代码浏览的 DTO → 领域模型映射（PRD §4.4 代码分区 / §4.5 文件查看、TECH_SPEC §9.5）。
///
/// ## 为什么单独一层、而且是**纯函数**
///
/// 与 `SearchRowMapper` / `RepositoryMapper` 同一分工：这一层只看 DTO，
/// 直接喂 JSON 就能断言，不必先起一套 HTTP 桩件。
/// 而它们要钉住的恰恰是"错了不会报错、只会显示成别的东西"的那几条：
///
/// - `type` 的四种取值怎么落到 `TreeEntry.Kind` 的三档上（映射错了目录就点不动）；
/// - `size` 缺席时给什么（给错就选错通道，见 `FileContent`）。
public enum RepoFileMapper {

    // MARK: - 目录条目

    /// 目录清单的一项 → 文件树的一行。
    ///
    /// ⚠️ 目录清单接口带的就是这五样（名字 / 路径 / 种类 / 大小 / SHA）。
    /// 2026-10-11 之前这里还给 `recentCommit` 留了个"由第二趟补请求填"的口子 ——
    /// 那条链路（决策 #49）已整条删除。
    public static func treeEntry(_ dto: ContentEntryDTO) -> TreeEntry {
        TreeEntry(
            name: dto.name,
            // 服务端给的路径是权威的 —— `RepoPath(path:)` 不校验（见它的说明：
            // 解析一个既有路径不该是一件会失败的事）
            path: RepoPath(path: dto.path),
            kind: kind(of: dto.type),
            // ⚠️ 目录的 `size` 缺席 ⇒ `0`。这里给 0 是安全的：目录**不会**被当成文件打开
            //    （`kind == .directory`），所以它不参与"三档降级"的判定。
            size: dto.size ?? 0,
            sha: dto.sha
        )
    }

    /// `RepoContentType` → `TreeEntry.Kind`。
    ///
    /// ⚠️ `symlink` / `submodule` / 认不出的取值**都归到 `.unsupported`**：
    /// - symlink 的 `content` 是**链接目标那串文本**，当文件打开会把它显示成"文件内容"；
    /// - submodule 的 `sha` 是**另一个仓库的提交**，点进去请求 contents 只会 404；
    /// - 认不出的取值同理 —— 归到 `.unsupported` 的后果是"这一条点不动"，
    ///   归到 `.file` 的后果是"显示错误的内容"。两害相权取前者。
    public static func kind(of type: RepoContentType) -> TreeEntry.Kind {
        switch type {
        case .directory: .directory
        case .file: .file
        case .symlink, .submodule, .unknown: .unsupported
        }
    }

    // MARK: - 文件正文

    /// 组装文件查看页要显示的内容（决策 #54 的三档降级）。
    ///
    /// - Parameters:
    ///   - dto: `contents` 的单文件 payload。
    ///   - bytes: **已经取到的字节** —— 小文本是 `content` 经 base64 解开的，
    ///     大文本与图片是 `Accept: application/vnd.github.raw` 拿回的。
    ///     走哪条通道由调用方按 `FilePreviewKind` 决定（本层不认识网络）。
    ///
    /// - Returns: 可显示的 `FileContent`；**`nil` 表示这一档不该在这里渲染**：
    ///   - `preview` 是 `.unsupported`（二进制 / 超限图片）⇒ 调用方走"不支持预览 + 网页端"；
    ///   - 文本通道但字节不是合法 UTF-8（GBK / 二进制误判）⇒ 同上。
    ///
    /// ⚠️ 第二种情形**不返回空串**：空串会被显示成"这是一个空文件"，
    /// 而事实是"这个 App 不认识它的编码"（`FileContentCodec.text(from:)` 的说明）。
    public static func fileContent(_ dto: RepoFileDTO, bytes: Data) -> FileContent? {
        let preview = FilePreviewKind.decide(name: dto.name, size: dto.size)

        switch preview {
        case .unsupported:
            return nil

        case .image:
            return FileContent(
                path: RepoPath(path: dto.path),
                blobSHA: dto.sha,
                // 用**服务端给的** size，不是 `bytes.count` —— 两者在"解码后重算"这件事上
                // 会不一样，而界面上那句 `{大小}` 应当与服务端一致
                size: dto.size,
                body: .image(bytes),
                preview: preview,
                // 图片没有 markdown 一回事（`MarkdownFile` 只认 .md / .markdown）。
                markdown: nil
            )

        case .text, .largeText:
            guard let text = FileContentCodec.text(from: bytes) else { return nil }
            return FileContent(
                path: RepoPath(path: dto.path),
                blobSHA: dto.sha,
                size: dto.size,
                body: .text(text),
                preview: preview,
                // ⚠️ 只有 `.md` / `.markdown` 会在这里拿到一份文档；其余文本是 `nil`
                //    ⇒ 视图仍走代码块（`MarkdownFile` 的说明、走查第 57 条）。
                markdown: MarkdownFile.document(path: RepoPath(path: dto.path), text: text)
            )
        }
    }
}
