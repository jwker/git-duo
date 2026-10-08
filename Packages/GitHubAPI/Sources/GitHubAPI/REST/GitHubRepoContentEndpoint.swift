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

    // MARK: - 写：新建 / 更新一个文件

    /// 新建或更新一个文件 —— `PUT /repos/{owner}/{repo}/contents/{path}`
    /// （TECH_SPEC §9.6.1 的 ①②③④ 四条写通道都走它、§9.6.2）。
    ///
    /// ## ⚠️ 这条请求有两处"错了都不报错"，两处都在签名里挡掉
    ///
    /// 1. **`branch` 没有默认值**：官方原文是 *"The branch name.
    ///    **Default: the repository's default branch.**"* ⇒ 不传的后果是
    ///    **用户在 `feature/x` 上编辑、提交却落到 `main`**，而全过程**没有任何错误信号**
    ///    （界面显示"已提交"、分支也对，只是提交去了别处）—— 决策 #65。
    ///    所以它不是可选参数：**这一层不允许"忘了传"这件事发生**。
    ///    有一条正面断言钉住它的值真的是调用方那一版（不是仓库默认分支）。
    /// 2. **`sha` 也没有默认值**，而且它的值必须是**用户读到的那一版**（乐观锁，决策 #64）。
    ///    在提交时刻现取一个新 `sha` 会让并发改动**永远撞不上 409** ⇒ 静默丢掉远端改动。
    ///    `nil` 是**有含义的**：表示"新建"（路径已存在 ⇒ 服务端 422，**不静默覆盖**）。
    ///
    /// ## ⚠️ `content` 是原始字节，base64 在这里编
    ///
    /// 领域层（`SaveFile`）交过来的是 `Data`。官方要的是 base64 字符串。
    /// 这一步放在数据层的理由与"图片不重编码"同源：它错了的表现是**内容损坏**，
    /// 而不是"少了一个字段" —— 离网络最近的那一层做它，可被单测直接钉住。
    ///
    /// - Parameters:
    ///   - path: 仓库内相对路径（**不带前导 `/`**，由 `route(...)` 统一处理）。
    ///   - message: 提交信息。空串不该走到这里 —— 「空则用默认信息」在领域层
    ///     （`CommitDraft.effectiveMessage`）。
    ///   - sha: 见上（`nil` = 新建）。
    ///
    /// - Returns: 新 blob SHA 与这次提交 SHA（**两个不是一回事**，见 `FileWriteResultDTO`）。
    ///
    /// ⚠️ **不自动重试**（`HTTPMethod.isSafelyRetryable` 只认 GET）：带过期 `sha` 的重复 PUT
    /// 会回 409，自动重试会让用户看到"提交失败"而第一次其实已经成功 —— 这种"假失败"比不重试危险。
    public func putFile(
        owner: String,
        repo: String,
        path: String,
        message: String,
        content: Data,
        sha: String?,
        branch: String
    ) async throws -> FileWriteResultDTO {
        let response = try await client.send(
            .sending(
                .put,
                to: client.url(route(owner: owner, repo: repo, path: path)),
                body: try Self.writeBody(
                    message: message,
                    content: content,
                    sha: sha,
                    branch: branch
                ),
                invalidating: Self.headDependentPrefixes(owner: owner, repo: repo)
            )
        )
        return try response.decode(FileWriteResultDTO.self)
    }

    // MARK: - 写：删除一个文件

    /// 删除一个文件 —— `DELETE /repos/{owner}/{repo}/contents/{path}`（§9.6.5）。
    ///
    /// ## ⚠️ 它不能与 `putFile` 并行
    ///
    /// 官方 NOTE 原文：这两个端点并行会冲突，*"You must use these endpoints serially instead."*
    /// ⇒ 「重命名 = `PUT` 新路径 + `DELETE` 旧路径」**必须顺序两步**（决策 #66）。
    /// 串行的编排在领域层 `RenameFile` —— 数据层只提供两个各自独立的动作，
    /// 因为"这两步之间断了怎么办"是**产品口径**（要告诉用户"新旧两个文件都在"），不是协议细节。
    ///
    /// ## ⚠️ `message` 与 `sha` 都是必填（官方原文两条 `(required)`）
    ///
    /// `sha` 是**现取**的（`DELETE` 前补一次 `GET contents`）—— 删除没有
    /// "用户手上读过的那一版"这回事，见 `DeleteFile`。这与 `putFile` 的语义**相反**，
    /// 两者在类型上都是 `String`，所以这一句必须写在这里。
    ///
    /// - Returns: 无返回值 —— 成功是 **204 No Content**，**没有响应体**
    ///   （所以它天然没有"返回值必须被消费"那个问题，与 `putFile` 不同）。
    public func deleteFile(
        owner: String,
        repo: String,
        path: String,
        message: String,
        sha: String,
        branch: String
    ) async throws {
        let body = try JSONSerialization.data(
            withJSONObject: ["message": message, "sha": sha, "branch": branch],
            options: [.sortedKeys]
        )
        _ = try await client.send(
            .sending(
                .delete,
                to: client.url(route(owner: owner, repo: repo, path: path)),
                body: body,
                invalidating: Self.headDependentPrefixes(owner: owner, repo: repo)
            )
        )
    }

    // MARK: - 请求体

    /// `PUT /contents` 的请求体 —— `{message, content, sha?, branch}`。
    ///
    /// ⚠️ `branch` 是**非可选且无默认值**的形参：这是"不带 `branch` 的请求发不出去"
    /// 那条要求的落点。它只在这里被拼进请求体一次，没有第二条路径。
    ///
    /// ⚠️ `sha` 为空时**整条键不写**，不是写 `null` —— 官方对 `"sha": null` 的行为没有文档保证，
    /// 而"不带这个键 = 新建"是文档里写明的（与 `refQuery` 那条同一个道理：不要发明空值语义）。
    ///
    /// ⚠️ **`content` 必须是 base64 的字符串**。`Data.base64EncodedString()` 不带换行；
    /// GitHub 也接受带换行的（MIME）形式，但不带是唯一没有歧义的一种。
    private static func writeBody(
        message: String,
        content: Data,
        sha: String?,
        branch: String
    ) throws -> Data {
        var payload: [String: String] = [
            "message": message,
            "content": content.base64EncodedString(),
            "branch": branch,
        ]
        if let sha { payload["sha"] = sha }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    // MARK: - 缓存前缀

    /// 写成功后必须失效的三条路径 —— contents / commits / branches。
    ///
    /// 一次 `PUT` / `DELETE` 会同时改变三件事：那个路径的**内容**、仓库多出**一条提交**、
    /// 以及所在分支的 **HEAD**。任何一条没清，都会在"提交完直接返回上一页"这条路上显形
    /// （而**下拉刷新走 `forcesReload` 绕过缓存，看不出问题**）。
    ///
    /// ⚠️ 按**路径前缀**匹配、不看查询串 ⇒ 会把**所有分支**的 contents / commits 一起清掉。
    /// 这是有意的粗粒度，理由同 `GitHubRepoBranchEndpoint.deleteBranch`：
    /// 分清 `?ref=main` 与 `?ref=feature` 需要把查询串纳入键的语义，
    /// 而"多几个请求"比"改完之后一直看到旧内容"轻得多。
    private static func headDependentPrefixes(owner: String, repo: String) -> [String] {
        [
            "/repos/\(owner)/\(repo)/contents",
            "/repos/\(owner)/\(repo)/commits",
            "/repos/\(owner)/\(repo)/branches",
        ]
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
