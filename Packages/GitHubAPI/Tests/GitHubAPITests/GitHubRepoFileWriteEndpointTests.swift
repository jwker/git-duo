import Foundation
import Testing

@testable import GitHubAPI

/// 文件写通道的数据层 —— `PUT` / `DELETE /repos/{o}/{r}/contents/{path}`。
/// TECH_SPEC §9.6.1 / §9.6.2 / §9.6.5、决策 #65 与 #66。
///
/// 靶心是**两处「错了都不报错」**：
///
/// 1. **`branch` 不传** ⇒ 官方默认值是**仓库的默认分支** ⇒
///    用户在 `feature/x` 上编辑、**提交却落到 `main`**，而全程没有任何错误信号
///    （界面显示"已提交"、分支也对，只是提交去了别处）；
/// 2. **两个 sha 混用** —— `content.sha`（文件的新 blob）与 `commit.sha`（这次提交）
///    混了 ⇒ 第二次编辑必然 409，而那个 409 看起来像"别人在改这个文件"。
///
/// 另两条必须在这一层钉住的：
///
/// 3. **base64 只在这里做**（领域层交过来的是原始字节）—— 它错了的表现是**内容损坏**；
/// 4. **写成功后 contents / commits / branches 三类缓存必须失效，且只清本仓库**。
@Suite("GitHubRepoContentEndpoint · 写通道（PUT / DELETE）")
struct GitHubRepoFileWriteEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEndpoint(
        harness: StubURLProtocol.Harness,
        cache: HTTPResponseCache = HTTPResponseCache(configuration: .memoryOnly()),
        retryPolicy: RetryPolicy = .none
    ) -> GitHubRepoContentEndpoint {
        GitHubRepoContentEndpoint(client: makeClient(
            harness: harness, cache: cache, retryPolicy: retryPolicy
        ))
    }

    /// 让分支 / 提交两个端点也共用同一份会话与缓存 ——
    /// 用来断言"写一次会连带清掉 contents / commits / branches 三类"。
    private func makeClient(
        harness: StubURLProtocol.Harness,
        cache: HTTPResponseCache,
        retryPolicy: RetryPolicy = .none
    ) -> GitHubRESTClient {
        let clock = now
        return GitHubRESTClient(
            credentials: credentials,
            transport: HTTPTransport(
                credentials: credentials,
                session: harness.makeSession(),
                cache: cache,
                retryPolicy: retryPolicy,
                clock: { clock },
                sleeper: { _ in }
            )
        )
    }

    /// 请求体解成字典 —— `URLRequest.httpBody` 常为 nil，桩件已经把 stream 读出来了。
    private func bodyJSON(_ harness: StubURLProtocol.Harness) throws -> [String: String] {
        let body = try #require(harness.lastBody)
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
    }

    // MARK: - 桩件载荷

    /// `PUT` 的响应（201 = 新建、200 = 更新，形状一样）。
    ///
    /// ⚠️ 两个 `sha` **有意写成不同的值** —— 测试要能看出它们不是一回事。
    private static let writeResultJSON = StubURLProtocol.Response.json(
        """
        {"content":{"name":"a.md","path":"docs/a.md","sha":"blob-new","size":3,
                    "type":"file","encoding":"base64","content":"aGk="},
         "commit":{"sha":"commit-new","message":"update via GitDuo"}}
        """,
        status: 201
    )

    private static let fileJSON = StubURLProtocol.Response.json(
        #"{"name":"a.md","path":"docs/a.md","sha":"blob-1","size":3,"type":"file","encoding":"base64","content":"aGk="}"#
    )
    private static let branchListJSON = StubURLProtocol.Response.json(
        #"[{"name":"main","commit":{"sha":"s"},"protected":false}]"#
    )
    private static let commitListJSON = StubURLProtocol.Response.json(
        #"[{"sha":"s","commit":{"message":"m","author":{"date":"2026-10-05T08:00:00Z"}},"author":null}]"#
    )

    // MARK: - 新建 / 更新

    @Test("新建：`PUT` + 路径拼对 + 请求体恰好三个键（**没有 sha**，不是写 null）")
    func createSendsThreeKeysWithoutSHA() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(Self.writeResultJSON)

        _ = try await makeEndpoint(harness: harness).putFile(
            owner: "misoge",
            repo: "paneltkit",
            path: "docs/a.md",
            message: "update via GitDuo",
            content: Data("hi".utf8),
            sha: nil,
            branch: "feature/x"
        )

        #expect(harness.lastRequest?.httpMethod == "PUT")
        #expect(harness.lastRequest?.url?.path == "/repos/misoge/paneltkit/contents/docs/a.md")

        let body = try bodyJSON(harness)
        #expect(
            body == [
                "message": "update via GitDuo",
                "content": Data("hi".utf8).base64EncodedString(),
                "branch": "feature/x",
            ]
        )
        // ⚠️ 整条键不写 —— 官方对 `"sha": null` 的行为没有文档保证
        #expect(body["sha"] == nil)
    }

    @Test("更新：带 sha ⇒ 请求体里的 sha 就是**用户读到的那一版**（乐观锁的基准，决策 #64）")
    func updateSendsTheReaderVersion() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(Self.writeResultJSON)

        _ = try await makeEndpoint(harness: harness).putFile(
            owner: "o",
            repo: "r",
            path: "docs/a.md",
            message: "m",
            content: Data("hi".utf8),
            sha: "blob-user-read",
            branch: "main"
        )

        let body = try bodyJSON(harness)
        #expect(body["sha"] == "blob-user-read")
    }

    // MARK: - 本套件的第一个靶心：branch 恒在

    @Test("⚠️ 不带 branch 的请求**发不出去** —— 两个写方法的请求体里 branch 恒在，且就是调用方那条")
    func branchIsMandatoryOnBothWrites() async throws {
        // 「发不出去」的**上半句由签名保证**：`branch: String` **没有默认值**，
        // 少传一个参数直接编译不过（这条断言写不出来，因为它不是一个运行时事实）。
        // 下面断言的是**下半句**："值真的是它"。
        // 少了这一条，`branch` 掉成服务端默认分支时**不会有任何报错**（决策 #65）——
        // 表现是"用户在 feature/x 上编辑、提交却落到了 main"。

        let putHarness = StubURLProtocol.makeHarness()
        putHarness.stub(Self.writeResultJSON)
        _ = try await makeEndpoint(harness: putHarness).putFile(
            owner: "o", repo: "r", path: "docs/a.md", message: "m",
            content: Data("hi".utf8), sha: nil, branch: "feature/x"
        )
        let putBody = try bodyJSON(putHarness)
        #expect(putBody["branch"] == "feature/x")
        #expect(
            putBody["branch"] != "main",
            "branch 掉成了默认分支 —— 这正是决策 #65 那条静默错"
        )

        let deleteHarness = StubURLProtocol.makeHarness()
        deleteHarness.stub(.empty(status: 204))
        try await makeEndpoint(harness: deleteHarness).deleteFile(
            owner: "o", repo: "r", path: "docs/a.md", message: "m",
            sha: "blob-1", branch: "feature/x"
        )
        let deleteBody = try bodyJSON(deleteHarness)
        #expect(deleteBody["branch"] == "feature/x")
    }

    // MARK: - 本套件的第二个靶心：两个 sha

    @Test("解码：`blobSHA` 与 `commitSHA` 是**两个 sha**（混用 ⇒ 第二次编辑必然 409）")
    func decodesBothSHAs() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(Self.writeResultJSON)

        let result = try await makeEndpoint(harness: harness).putFile(
            owner: "o", repo: "r", path: "docs/a.md", message: "m",
            content: Data("hi".utf8), sha: nil, branch: "main"
        )

        // 下一次更新要拿 blobSHA 当基准；commitSHA 是"这次提交真的产生了"的凭据
        #expect(result.blobSHA == "blob-new")
        #expect(result.commitSHA == "commit-new")
        #expect(result.blobSHA != result.commitSHA)
        // 服务端回显的提交信息 —— 空信息时它就是我们发出去的默认信息
        #expect(result.commit.message == "update via GitDuo")
        #expect(result.content.path == "docs/a.md")
    }

    // MARK: - base64

    @Test("base64：中文 / 换行 / 非 UTF-8 字节都**逐字节**还原，且不带换行")
    func base64RoundTripsRawBytes() async throws {
        // 上传的图片走的是同一条路（决策 #70③：不重编码）—— 这里用 PNG 的魔数当代表
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0xFF, 0x00])

        for payload in [Data("中文\n第二行\n".utf8), pngHeader] {
            let harness = StubURLProtocol.makeHarness()
            harness.stub(Self.writeResultJSON)

            _ = try await makeEndpoint(harness: harness).putFile(
                owner: "o", repo: "r", path: "docs/a.md", message: "m",
                content: payload, sha: nil, branch: "main"
            )

            let sent = try #require(try bodyJSON(harness)["content"])
            #expect(Data(base64Encoded: sent) == payload, "编错了的表现是内容损坏，不是少一个字段")
            // MIME 那种带换行的形式服务端也收，但不带换行是唯一没有歧义的一种
            #expect(!sent.contains("\n"))
        }
    }

    // MARK: - 失败不翻译

    @Test("409（sha 已过期）⇒ `conflict`，**原样抛出**（两个出口是界面的事，§9.6.4）")
    func staleSHASurfacesAsConflict() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"message":"sha does not match"}"#, status: 409))

        await #expect(throws: GitHubError.conflict) {
            _ = try await makeEndpoint(harness: harness).putFile(
                owner: "o", repo: "r", path: "docs/a.md", message: "m",
                content: Data("hi".utf8), sha: "stale", branch: "main"
            )
        }
    }

    @Test("不带 sha 去写一个**已存在**的路径 ⇒ 422 ⇒ `validation`（**不静默覆盖**，决策 #70⑤）")
    func writingExistingPathWithoutSHASurfacesValidation() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"{"message":"Invalid request","errors":[{"resource":"Content","code":"missing"}]}"#,
                status: 422
            )
        )

        // ⚠️ 断言的是**分类**而不是文案：422 的 `errors[]` 形状不固定（`field` / `resource` / `code`
        //    可有可无），而"给用户看什么话"由领域层 `FileWriteFailure.destinationExists` 决定 ——
        //    它本来就**不依赖服务端那句话**（否则文案会随服务端措辞漂移）。
        do {
            _ = try await makeEndpoint(harness: harness).putFile(
                owner: "o", repo: "r", path: "docs/a.md", message: "m",
                content: Data("hi".utf8), sha: nil, branch: "main"
            )
            Issue.record("422 应当抛错")
        } catch let error as GitHubError {
            guard case .validation = error else {
                Issue.record("422 应当归成 `.validation`（不是 conflict、也不是 serverError），实际是 \(error)")
                return
            }
        }
    }

    @Test("删一个不存在的路径 ⇒ 404 ⇒ `notFound` **照抛**（翻译成「已经不在了」是领域层的事）")
    func deletingMissingPathSurfacesNotFound() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"message":"Not Found"}"#, status: 404))

        await #expect(throws: GitHubError.notFound) {
            try await makeEndpoint(harness: harness).deleteFile(
                owner: "o", repo: "r", path: "docs/a.md", message: "m",
                sha: "blob-1", branch: "main"
            )
        }
    }

    // MARK: - 删除

    @Test("删除：`DELETE` + 请求体三个键，成功是 204 **无响应体** ⇒ 返回 Void")
    func deleteSendsThreeKeys() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 204))

        try await makeEndpoint(harness: harness).deleteFile(
            owner: "o",
            repo: "r",
            path: "docs/a.md",
            message: "update via GitDuo",
            sha: "blob-1",
            branch: "main"
        )

        #expect(harness.lastRequest?.httpMethod == "DELETE")
        #expect(harness.lastRequest?.url?.path == "/repos/o/r/contents/docs/a.md")

        let body = try bodyJSON(harness)
        // `message` 与 `sha` 两个都是官方 `(required)`（决策 #66②）
        #expect(
            body == [
                "message": "update via GitDuo",
                "sha": "blob-1",
                "branch": "main",
            ]
        )
    }

    // MARK: - 写后缓存失效

    @Test("写成功后失效 contents / commits / branches 三条缓存，**且只清本仓库**")
    func writeInvalidatesHeadDependentPaths() async throws {
        let harness = StubURLProtocol.makeHarness()
        let cache = HTTPResponseCache(configuration: .memoryOnly())
        let endpoint = makeEndpoint(harness: harness, cache: cache)
        let shared = makeClient(harness: harness, cache: cache)

        // 本仓库三条（正是要清的那三条）+ 另一个仓库一条（**不能被误伤**）
        harness.stub(Self.fileJSON)
        _ = try await endpoint.contents(owner: "o", repo: "r", path: "docs/a.md")
        harness.stub(Self.branchListJSON)
        _ = try await GitHubRepoBranchEndpoint(client: shared).branches(owner: "o", repo: "r")
        harness.stub(Self.commitListJSON)
        _ = try await GitHubRepoCommitEndpoint(client: shared).commits(owner: "o", repo: "r")
        harness.stub(Self.fileJSON)
        _ = try await endpoint.contents(owner: "o", repo: "other", path: "docs/a.md")
        #expect(await cache.memoryEntryCount == 4)

        harness.stub(Self.writeResultJSON)
        _ = try await endpoint.putFile(
            owner: "o", repo: "r", path: "docs/a.md", message: "m",
            content: Data("hi".utf8), sha: nil, branch: "main"
        )

        // ⚠️ 前缀匹配按 URL 的 **path** 比 ⇒ `/repos/o/r/contents` 会带走
        //    `/repos/o/r/contents/docs/a.md`，但碰不到 `/repos/o/other/...`。
        //    少清任何一条的表现都是"提交完直接返回上一页，看到的还是旧内容"
        //    （而下拉刷新走 `forcesReload` 绕过缓存，**看不出问题**）。
        #expect(await cache.memoryEntryCount == 1)
    }

    @Test("删除成功后同样失效那三条（删掉一个文件 = 内容 / 提交 / HEAD 全变了）")
    func deleteInvalidatesHeadDependentPaths() async throws {
        let harness = StubURLProtocol.makeHarness()
        let cache = HTTPResponseCache(configuration: .memoryOnly())
        let endpoint = makeEndpoint(harness: harness, cache: cache)

        harness.stub(Self.fileJSON)
        _ = try await endpoint.contents(owner: "o", repo: "r", path: "docs/a.md")
        #expect(await cache.memoryEntryCount == 1)

        harness.stub(.empty(status: 204))
        try await endpoint.deleteFile(
            owner: "o", repo: "r", path: "docs/a.md", message: "m",
            sha: "blob-1", branch: "main"
        )

        #expect(await cache.memoryEntryCount == 0)
    }

    // MARK: - 写操作不自动重试

    @Test("⚠️ `PUT` / `DELETE` **一次都不重试**（对照：同一套桩件下 GET 会重试一次）")
    func writesAreNeverRetriedButGetsAre() async throws {
        // 写操作重放的后果不是"多一次请求"，而是**假失败**：
        // 重放 PUT 会因 `sha` 已过期回 409（而第一次其实成功了），
        // 重放 DELETE 会回 404。用户看到"提交失败"，事实是提交成功了。

        let writeHarness = StubURLProtocol.makeHarness()
        writeHarness.stub([
            .json(#"{"message":"boom"}"#, status: 500),
            Self.writeResultJSON,
        ])
        await #expect(throws: GitHubError.serverError(status: 500)) {
            _ = try await makeEndpoint(harness: writeHarness, retryPolicy: .standard).putFile(
                owner: "o", repo: "r", path: "docs/a.md", message: "m",
                content: Data("hi".utf8), sha: nil, branch: "main"
            )
        }
        #expect(writeHarness.requestCount == 1, "写操作被自动重试了")

        // ── 对照组：同一条路径、同一套桩件，只把方法换成 GET。
        //    没有这一组，"requestCount == 1"可能只是因为这套桩件压根不重试任何东西。
        let readHarness = StubURLProtocol.makeHarness()
        readHarness.stub([
            .json(#"{"message":"boom"}"#, status: 500),
            Self.fileJSON,
        ])
        _ = try? await makeEndpoint(harness: readHarness, retryPolicy: .standard)
            .contents(owner: "o", repo: "r", path: "docs/a.md")
        #expect(readHarness.requestCount == 2, "幂等 GET 应当重试一次（这条不成立则上面那条证明不了什么）")
    }
}
