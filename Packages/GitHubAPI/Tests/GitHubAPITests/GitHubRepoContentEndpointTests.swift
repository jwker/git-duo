import Foundation
import Testing

@testable import GitHubAPI

/// 代码浏览的数据层 —— `contents`（两种形状）/ `rawFile` / `readme`。
/// TECH_SPEC §9.5、决策 #54。
///
/// 本套件的靶心是三件**不会报错、只会给错东西**的事：
/// ① 同一个端点回数组还是对象（判错就是整页解不开）；
/// ② `encoding:"none"`（>1MB 的文件，HTTP 还是 **200** —— 只看状态码会把空串当内容）；
/// ③ `readme` 的 404（"没有 README"与"网络断了"必须分开）。
@Suite("GitHubRepoContentEndpoint · 目录 / 文件正文 / README")
struct GitHubRepoContentEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEndpoint(harness: StubURLProtocol.Harness) -> GitHubRepoContentEndpoint {
        let clock = now
        return GitHubRepoContentEndpoint(
            client: GitHubRESTClient(
                credentials: credentials,
                transport: HTTPTransport(
                    credentials: credentials,
                    session: harness.makeSession(),
                    cache: HTTPResponseCache(configuration: .memoryOnly()),
                    retryPolicy: .none,
                    clock: { clock },
                    sleeper: { _ in }
                )
            )
        )
    }

    // MARK: - 路由形状

    @Test("根目录：路由**不带**尾斜杠，且不带 ref 时查询串是空的")
    func rootRouteHasNoTrailingSlash() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        _ = try await makeEndpoint(harness: harness).contents(owner: "misoge", repo: "paneltkit")

        let url = try #require(harness.lastRequest?.url)
        // `/contents/` 与 `/contents` 都能返回，但它们是**两个不同的缓存键**
        #expect(url.path == "/repos/misoge/paneltkit/contents")
        // ⚠️ 不能写 `ref=` 空串：服务端对空 ref 的行为没有文档保证
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == nil)
    }

    @Test("子路径：拼进路由，ref 进查询串")
    func nestedRouteAndRef() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        _ = try await makeEndpoint(harness: harness)
            .contents(owner: "o", repo: "r", path: "docs/guide.md", ref: "feature/repo-hub")

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/repos/o/r/contents/docs/guide.md")

        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "ref" }?.value == "feature/repo-hub")
    }

    @Test("路径首尾的斜杠被吃掉 —— `/docs/` 与 `docs` 是同一个目录，只该有一个缓存键")
    func trimsSurroundingSlashes() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        _ = try await makeEndpoint(harness: harness).contents(owner: "o", repo: "r", path: "/docs/")

        #expect(harness.lastRequest?.url?.path == "/repos/o/r/contents/docs")
    }

    // MARK: - 两种响应形状

    @Test("目录响应（数组）⇒ .directory，条目字段逐个对")
    func decodesDirectoryEntries() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                [
                  {"name":"docs","path":"docs","sha":"tree-sha","size":0,"type":"dir"},
                  {"name":"README.md","path":"README.md","sha":"blob-sha","size":1234,"type":"file"},
                  {"name":"link","path":"link","sha":"l-sha","size":11,"type":"symlink"}
                ]
                """
            )
        )

        let payload = try await makeEndpoint(harness: harness)
            .contents(owner: "o", repo: "r")

        let entries = payload.entries
        #expect(payload.file == nil)
        #expect(entries.count == 3)

        // ⚠️ GitHub 对目录发的是 `"type":"dir"`（不是 `"directory"`）——
        //    照官方文档的措辞写 `directory` 会一条都认不出来
        #expect(entries[0].type == .directory)
        #expect(entries[0].name == "docs")
        #expect(entries[0].path == "docs")
        #expect(entries[0].sha == "tree-sha")

        #expect(entries[1].type == .file)
        #expect(entries[1].size == 1234)

        // symlink 不是文件：它的 content 是链接目标那串文本，当文件打开会显示出错的东西
        #expect(entries[2].type == .symlink)
        #expect(entries[2].type.isFile == false)
    }

    @Test("认不出的 type ⇒ .unknown（**不是** .file，也不是解码失败）")
    func unknownTypeFallsBackWithoutFailing() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(#"[{"name":"x","path":"x","sha":"s","size":1,"type":"worktree"}]"#)
        )

        let entries = try await makeEndpoint(harness: harness).contents(owner: "o", repo: "r").entries

        #expect(entries.first?.type == .unknown)
        // 兜底成 .file 会让用户看到"内容"，而那是它自己的链接目标 / 未知形态
        #expect(entries.first?.type.isFile == false)
    }

    @Test("目录条目的 size 缺席 ⇒ nil（**不补 0**，也不失败）")
    func missingEntrySizeIsNil() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"[{"name":"d","path":"d","sha":"s","type":"dir"}]"#))

        let entries = try await makeEndpoint(harness: harness).contents(owner: "o", repo: "r").entries

        #expect(entries.first?.size == nil)
    }

    @Test("单文件响应（对象）⇒ .file，base64 内容与编码原样带出")
    func decodesSingleFilePayload() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                {"name":"README.md","path":"README.md","sha":"blob-sha","size":42,
                 "type":"file","encoding":"base64","content":"aGVsbG8K"}
                """
            )
        )

        let payload = try await makeEndpoint(harness: harness)
            .contents(owner: "o", repo: "r", path: "README.md")

        let file = try #require(payload.file)
        #expect(payload.entries.isEmpty)
        #expect(file.name == "README.md")
        #expect(file.size == 42)
        #expect(file.encoding == "base64")
        #expect(file.content == "aGVsbG8K")
        #expect(file.isContentOmitted == false)
    }

    // MARK: - 大文件（决策 #54 的靶心）

    @Test("⚠️ >1MB：HTTP 200 + `encoding:\"none\"` + 空 content ⇒ isContentOmitted")
    func omittedContentIsRecognised() async throws {
        let harness = StubURLProtocol.makeHarness()
        // 实测形状：kubernetes/kubernetes 的 api/openapi-spec/swagger.json，size = 4,280,356
        harness.stub(
            .json(
                """
                {"name":"swagger.json","path":"api/openapi-spec/swagger.json","sha":"big-sha",
                 "size":4280356,"type":"file","encoding":"none","content":""}
                """
            )
        )

        let payload = try await makeEndpoint(harness: harness)
            .contents(owner: "o", repo: "r", path: "api/openapi-spec/swagger.json")

        let file = try #require(payload.file)
        #expect(file.size == 4_280_356)
        // 只看 HTTP 状态码是 200 ⇒ 会以为"拿到了内容"，而这内容是空串
        #expect(file.isContentOmitted)
    }

    @Test("⚠️ 真空文件（一致的空串，但 encoding 仍是 base64）**不算**内容被省略")
    func emptyFileIsNotOmitted() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"{"name":".gitkeep","path":".gitkeep","sha":"s","size":0,"type":"file","encoding":"base64","content":""}"#
            )
        )

        let file = try #require(
            try await makeEndpoint(harness: harness)
                .contents(owner: "o", repo: "r", path: ".gitkeep").file
        )

        // 判据只有 `encoding == "none"` 一条：把"空串"也算成省略，
        // 一个真正的空文件就会被显示成"内容太大、去看网页端"
        #expect(file.isContentOmitted == false)
    }

    // MARK: - raw 通道

    @Test("rawFile：Accept 换成裸内容，响应原样返回（不解析、不改写）")
    func rawFileUsesRawAccept() async throws {
        let harness = StubURLProtocol.makeHarness()
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        harness.stub(
            StubURLProtocol.Response(
                status: 200,
                body: bytes,
                headers: ["Content-Type": "application/octet-stream"]
            )
        )

        let data = try await makeEndpoint(harness: harness)
            .rawFile(owner: "o", repo: "r", path: "logo.png", ref: "main")

        #expect(data == bytes)
        #expect(harness.lastRequest?.value(forHTTPHeaderField: "Accept") == "application/vnd.github.raw")

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/repos/o/r/contents/logo.png")
        #expect(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "ref" }?.value == "main"
        )
        // ⚠️ 别按响应的 content-type 判内容类型 —— 它会把请求里那个串原样回带
        #expect(harness.lastRequest?.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test("⚠️ raw 与 JSON 是同一 URL 的两种表示：JSON 那次的 ETag **不得**串到 raw 上")
    func rawDoesNotReuseJSONCacheEntry() async throws {
        let harness = StubURLProtocol.makeHarness()
        let json = #"{"name":"logo.png","path":"logo.png","sha":"s","size":6,"type":"file","encoding":"base64","content":"iVBORw0KGgo="}"#
        harness.stub(StubURLProtocol.Response.json(json, headers: ["ETag": "\"v1\""]))
        let endpoint = makeEndpoint(harness: harness)

        // ① 先用 JSON 表示取同一个路径（`LoadFileContent` 在"不知道 sha/size"时就是这么干的）。
        _ = try await endpoint.contents(owner: "o", repo: "r", path: "logo.png")

        // ② 再按 raw 表示取同一个路径。
        harness.stub(StubURLProtocol.Response(
            status: 200,
            body: Data([0x89, 0x50, 0x4E, 0x47]),
            headers: ["Content-Type": "application/octet-stream"]
        ))
        let data = try await endpoint.rawFile(owner: "o", repo: "r", path: "logo.png")

        // 两条表示的缓存键若没分开，这一步会带上 ① 的 ETag ⇒ 服务端答 304
        // ⇒ transport 把缓存里的 **JSON** 当文件字节返回（图片显示加载失败）。
        #expect(harness.lastRequest?.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(data == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("同一种表示的第二次请求照旧带 `If-None-Match`（修的是撞键，不是把条件请求关掉）")
    func sameVariantStillRevalidates() async throws {
        let harness = StubURLProtocol.makeHarness()
        let json = #"{"name":"logo.png","path":"logo.png","sha":"s","size":6,"type":"file","encoding":"base64","content":"iVBORw0KGgo="}"#
        harness.stub(StubURLProtocol.Response.json(json, headers: ["ETag": "\"v1\""]))
        let endpoint = makeEndpoint(harness: harness)

        _ = try await endpoint.contents(owner: "o", repo: "r", path: "logo.png")
        _ = try await endpoint.contents(owner: "o", repo: "r", path: "logo.png")

        #expect(harness.lastRequest?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
    }

    // MARK: - README

    @Test("readme：带 ref、走裸内容媒体类型")
    func readmeRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            StubURLProtocol.Response(
                status: 200,
                body: Data("# GitDuo\n".utf8),
                headers: ["Content-Type": "application/vnd.github.raw; charset=utf-8"]
            )
        )

        let text = try await makeEndpoint(harness: harness)
            .readme(owner: "o", repo: "r", ref: "dev")

        #expect(text == "# GitDuo\n")
        #expect(harness.lastRequest?.value(forHTTPHeaderField: "Accept") == "application/vnd.github.raw")

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/repos/o/r/readme")
        #expect(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "ref" }?.value == "dev"
        )
    }

    @Test("⚠️ 404 ⇒ nil（没有 README，不是加载失败）")
    func readmeNotFoundBecomesNil() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"message":"Not Found"}"#, status: 404))

        let text = try await makeEndpoint(harness: harness).readme(owner: "o", repo: "r")

        #expect(text == nil)
    }

    @Test("⚠️ 500 **不能**吞成 nil —— 那会把断网 / 服务端故障说成「这个仓库没有 README」")
    func readmeServerErrorIsNotSwallowed() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"message":"boom"}"#, status: 500))

        await #expect(throws: GitHubError.serverError(status: 500)) {
            _ = try await makeEndpoint(harness: harness).readme(owner: "o", repo: "r")
        }
    }

    @Test("非 UTF-8 的 README ⇒ 解码错误（**不返回空串** —— 空串会被读成「README 是空的」）")
    func nonUTF8ReadmeThrows() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            StubURLProtocol.Response(
                status: 200,
                body: Data([0xFF, 0xFE, 0x00]),
                headers: ["Content-Type": "text/plain"]
            )
        )

        await #expect(throws: GitHubError.self) {
            _ = try await makeEndpoint(harness: harness).readme(owner: "o", repo: "r")
        }
    }
}
