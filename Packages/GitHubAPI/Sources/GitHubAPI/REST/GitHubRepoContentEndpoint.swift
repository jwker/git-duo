import Foundation

/// 代码浏览：目录清单 / 文件正文 / README —— `GET /repos/{o}/{r}/contents/{path}` 与
/// `GET /repos/{o}/{r}/readme`（TECH_SPEC §9.5、PRD §4.4 代码分区 / §4.5 文件查看）。
///
/// ## 两条通道，由 `size` 与 `encoding` 决定（决策 #54）
///
/// | 情形 | 通道 |
/// |---|---|
/// | 文本 · ≤1MB | 本类型的 `contents(...)` —— `content` 是 base64 |
/// | 文本 · **>1MB** | `contents(...)` 只能拿到"内容没给你"的信号（`encoding:"none"` + 空串）⇒ 改走 `rawFile(...)` |
/// | 图片 | 先看 `size`，不超上限才 `rawFile(...)` 取字节 |
/// | 其余二进制 | 两条都不走，显示「不支持预览」+ 网页端出口 |
///
/// ⚠️ **档位判定不在这里** —— 它是领域层纯函数 `FilePreviewKind.decide(name:size:)`
/// （切片 6.1）。数据层只提供通道，谁走哪条由那条纯函数说了算
/// （App target 没有测试 target，把判定留在视图里就没人守）。
public struct GitHubRepoContentEndpoint: Sendable {

    /// 取**裸内容**的媒体类型。
    ///
    /// ⚠️ 它**覆盖** transport 的默认 `Accept`（`application/vnd.github+json`），
    /// 两者不会同时生效。
    ///
    /// ⚠️ 与 README 那处的实测结论一起看：`application/vnd.github.raw` 与
    /// `application/vnd.github.raw+json` **两种写法都回 200 + 裸内容**，
    /// 且响应头的 `content-type` 会把请求里那个串**原样回带** ——
    /// **别按响应 `content-type` 判内容类型**（2026-10-07 实测 `cli/cli`）。
    static let rawAccept = "application/vnd.github.raw"

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    /// ⚠️ **只有这一个初始化器**，不接受 credentials / session。
    public init(client: GitHubRESTClient) {
        self.client = client
    }

    // MARK: - 目录清单 / 单文件 payload

    /// 取一个路径的内容 —— `GET /repos/{owner}/{repo}/contents/{path}?ref={branch}`。
    ///
    /// - Parameters:
    ///   - path: 仓库内路径。**空串或 `"/"` 表示根目录**（此时路由里不带 path 段）。
    ///     其余情况请传**已经过 `RepoPath` 校验**的值（切片 6.1）：
    ///     本方法不做 `..` / `//` 的校验，而一个带 `..` 的路径在 URL 里
    ///     可能被归一化掉、于是**请求的是另一个目录**（不报错）。
    ///   - ref: 分支 / 标签 / 提交 SHA。`nil` ⇒ 服务端用**默认分支**。
    ///     ⚠️ 用户在非默认分支上浏览时必须传当前分支，否则看到的是另一条分支的内容。
    ///
    /// - Returns: 目录 ⇒ `.directory(条目)`；文件 ⇒ `.file(payload)`。
    ///   同一个端点两种形状，判据在 `ContentsPayload` 里，**调用方不需要试两次**。
    public func contents(
        owner: String,
        repo: String,
        path: String = "",
        ref: String? = nil
    ) async throws -> ContentsPayload {
        try await client.get(
            route(owner: owner, repo: repo, path: path),
            query: refQuery(ref),
            as: ContentsPayload.self,
            rateLimitResource: .core
        )
    }

    // MARK: - 文件正文（裸字节）

    /// 取文件**原文**（`Accept: application/vnd.github.raw`）。
    ///
    /// 用于两处（决策 #54）：**>1MB 的文本**（`contents` 那时不给内容）与
    /// **图片**（要字节才能解码成图）。
    ///
    /// ⚠️ 实测同一份 4,280,356 字节的文件在这里回**完整**内容
    /// （`size_download` 与仓库里的大小一致，首尾完整）—— **不是截断**。
    /// 第一次测到 1.2MB 是传输被打断，单跑复现为完整，别据此去写一个"raw 也有 1MB 上限"的结论。
    ///
    /// ⚠️ **不在这里判大小**：要不要下载由调用方按 `FilePreviewKind` + `size` 决定。
    /// 本方法一旦被调用就一定会把整份内容读进内存（图片解码后还要数倍于字节数），
    /// 所以"手机上没有理由硬拉一张 20MB 的 PNG"这条纪律的落点在**调用方**，
    /// 而不是在这一层再加一道 `if`。
    public func rawFile(
        owner: String,
        repo: String,
        path: String,
        ref: String? = nil
    ) async throws -> Data {
        let response = try await client.send(
            .get(
                client.url(route(owner: owner, repo: repo, path: path), query: refQuery(ref)),
                headers: ["Accept": Self.rawAccept],
                rateLimitResource: .core
            )
        )
        return response.body
    }

    // MARK: - README

    /// 取 README 原文（裸 Markdown）—— `GET /repos/{owner}/{repo}/readme`。
    ///
    /// - Returns: README 文本；**`nil` 表示这个仓库没有 README**。
    /// - Throws: 除 404 外的所有错误原样抛出（网络、配额、5xx、非 UTF-8…）。
    ///
    /// ⚠️ **404 在这里被有意吞掉并翻译成 `nil`**（同 `GitHubRepoInsightsEndpoint.latestRelease`）。
    /// 理由是可以确定的：同一屏的 `GET /repos/{o}/{r}` 与 `contents` 已经成功，
    /// 仓库存在且可见已被证实 ⇒ 这个 404 只可能是"没有 README 文件"。
    /// 不这么做，一个只是没写 README 的仓库会让整个代码分区显示成"加载失败"。
    ///
    /// ⚠️ **只吞 404**。把 5xx / 断网也吞成 `nil` 会让用户看到"这个仓库没有 README"，
    /// 而事实是网络断了 —— **"断网 ≠ 没有数据"**。
    ///
    /// ⚠️ 用 `ref` 指定分支：README 在各分支上**可能不同**，不带 `ref` 拿的是默认分支那份。
    /// ⚠️ 内容**不在这里解析** —— 块级 Markdown 渲染走领域层 `MarkdownParser`（§11.1、切片 6.1）。
    /// 本方法只负责把字符串拿回来（不透明地）。
    public func readme(
        owner: String,
        repo: String,
        ref: String? = nil
    ) async throws -> String? {
        let response: HTTPResponse
        do {
            response = try await client.send(
                .get(
                    client.url("repos/\(owner)/\(repo)/readme", query: refQuery(ref)),
                    headers: ["Accept": Self.rawAccept],
                    rateLimitResource: .core
                )
            )
        } catch {
            if case GitHubError.notFound = error { return nil }
            throw error
        }

        // ⚠️ 非 UTF-8 字节（二进制 README、或服务端返回了别的东西）⇒ **抛错**，不返回空串。
        //    返回空串会让"README 打不开"显示成"这个仓库的 README 是空的"。
        guard let text = String(data: response.body, encoding: .utf8) else {
            throw GitHubError.decoding(
                DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "README 不是 UTF-8 文本（官方该端点的 raw 媒体类型本应回文本）"
                    )
                )
            )
        }
        return text
    }

    // MARK: - 内部

    /// `repos/{owner}/{repo}/contents` 或 `.../contents/{path}`。
    ///
    /// ⚠️ 根目录**不带尾斜杠**：`contents/` 与 `contents` 在 GitHub 上都能返回，
    /// 但两者是**不同的 URL**、也就是缓存里不同的键 —— 同一个目录被缓存两份没有收益。
    /// 统一成不带斜杠那一版（`/contents`），并顺手吃掉调用方可能带来的首尾斜杠。
    private func route(owner: String, repo: String, path: String) -> String {
        let base = "repos/\(owner)/\(repo)/contents"
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? base : "\(base)/\(trimmed)"
    }

    /// `ref` 只在非空时进查询串。
    ///
    /// ⚠️ 不要把 `ref=` 写成空串：服务端对空 `ref` 的行为没有文档保证，
    /// 而"空串 ⇒ 当默认分支"纯属猜测。不带这个参数才是文档里"用默认分支"的写法。
    private func refQuery(_ ref: String?) -> [URLQueryItem] {
        guard let ref, !ref.isEmpty else { return [] }
        return [URLQueryItem(name: "ref", value: ref)]
    }
}
