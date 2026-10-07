import Foundation
import Testing

@testable import GitHubAPI

/// 分支管理的数据层 —— 列表 / 单分支 / compare / 建 / 删 / 合并。
/// TECH_SPEC §9.7.1、决策 #52 与 #53。
///
/// 靶心是四处**「成功也可能是失败 / 失败也可能是成功」**的地方：
/// ① `compare` 路由里的 `...` 不能被百分号编码；
/// ② 建分支的请求体与响应体**形状不同**；
/// ③ 合并的 **204 不是失败**（"没有东西可合"）；
/// ④ 写操作之后缓存必须失效（否则会继续按已不存在的 ref 请求而 404）。
@Suite("GitHubRepoBranchEndpoint · 列表 / 比较 / 建删合并")
struct GitHubRepoBranchEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEndpoint(
        harness: StubURLProtocol.Harness,
        cache: HTTPResponseCache = HTTPResponseCache(configuration: .memoryOnly())
    ) -> GitHubRepoBranchEndpoint {
        let clock = now
        return GitHubRepoBranchEndpoint(
            client: GitHubRESTClient(
                credentials: credentials,
                transport: HTTPTransport(
                    credentials: credentials,
                    session: harness.makeSession(),
                    cache: cache,
                    retryPolicy: .none,
                    clock: { clock },
                    sleeper: { _ in }
                )
            )
        )
    }

    /// 请求体解成字典 —— `URLRequest.httpBody` 常为 nil，桩件已经把 stream 读出来了。
    private func bodyJSON(_ harness: StubURLProtocol.Harness) throws -> [String: String] {
        let body = try #require(harness.lastBody)
        return try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: String]
        )
    }

    // MARK: - 列表

    @Test("列表：per_page=100（端点上限，一页取回）")
    func listRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        _ = try await makeEndpoint(harness: harness).branches(owner: "misoge", repo: "paneltkit")

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/repos/misoge/paneltkit/branches")
        #expect(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "per_page" }?.value == "100"
        )
    }

    @Test("列表：name / commit.sha / **protected** 逐个对（决策 #53 的判据来源）")
    func listDecodesProtected() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                [
                  {"name":"main","commit":{"sha":"head-sha","url":"u"},"protected":true},
                  {"name":"feature/repo-hub","commit":{"sha":"f-sha","url":"u"},"protected":false}
                ]
                """
            )
        )

        let page = try await makeEndpoint(harness: harness).branches(owner: "o", repo: "r")

        #expect(page.items.count == 2)
        #expect(page.items[0].name == "main")
        #expect(page.items[0].commitSHA == "head-sha")
        #expect(page.items[0].protected == true)
        #expect(page.items[1].name == "feature/repo-hub")
        #expect(page.items[1].protected == false)
        // 没有下一页 ⇒ 条目数**就是**精确总数（同决策 #40 的口径）
        #expect(page.hasMore == false)
    }

    @Test("列表：有下一页时 hasMore 为真（此时只能说「100 条以上」）")
    func listExposesHasMore() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"[{"name":"a","commit":{"sha":"s"},"protected":false}]"#,
                headers: ["Link": #"<https://api.github.com/repos/o/r/branches?page=2>; rel="next""#]
            )
        )

        let page = try await makeEndpoint(harness: harness).branches(owner: "o", repo: "r")

        #expect(page.hasMore)
    }

    // MARK: - 单分支

    @Test("单分支：带 `/` 的分支名照常当路径分段；多出来的字段被忽略")
    func singleBranchRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                {"name":"feature/repo-hub","commit":{"sha":"f-sha","url":"u"},
                 "protected":false,"protection_url":"p","_links":{"self":"s"}}
                """
            )
        )

        let branch = try await makeEndpoint(harness: harness)
            .branch(owner: "o", repo: "r", name: "feature/repo-hub")

        #expect(harness.lastRequest?.url?.path == "/repos/o/r/branches/feature/repo-hub")
        #expect(branch.commitSHA == "f-sha")
        #expect(branch.protected == false)
    }

    // MARK: - compare

    @Test("⚠️ compare：路由里的 `...` **不能被百分号编码**（它是这个路由的字面语法）")
    func compareKeepsTripleDotVerbatim() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"status":"identical","ahead_by":0,"behind_by":0,"total_commits":0}"#))

        _ = try await makeEndpoint(harness: harness)
            .compare(owner: "o", repo: "r", base: "feature/x", head: "main")

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/repos/o/r/compare/feature/x...main")
        // 编码成 %2E%2E%2E 的后果是服务端认不出这个路由 —— 而它不会明说，只会 404
        #expect(url.absoluteString.contains("..."))
        #expect(url.absoluteString.contains("%2E") == false)
    }

    @Test("compare：只解四个标量（commits / files 会被截断，**不声明它们**）")
    func compareDecodesFourScalars() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                {"status":"ahead","ahead_by":3,"behind_by":0,"total_commits":3,
                 "commits":[{"sha":"a"},{"sha":"b"},{"sha":"c"}],
                 "files":[{"filename":"x"}],
                 "base_commit":{"sha":"base"},"merge_base_commit":{"sha":"mb"}}
                """
            )
        )

        let comparison = try await makeEndpoint(harness: harness)
            .compare(owner: "o", repo: "r", base: "feature", head: "main")

        #expect(comparison.status == "ahead")
        #expect(comparison.aheadBy == 3)
        #expect(comparison.behindBy == 0)
        #expect(comparison.totalCommits == 3)
    }

    @Test("compare：两端相同 ⇒ status=identical，三个计数全是 0（实测口径）")
    func compareIdentical() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"status":"identical","ahead_by":0,"behind_by":0,"total_commits":0}"#))

        let comparison = try await makeEndpoint(harness: harness)
            .compare(owner: "o", repo: "r", base: "trunk", head: "trunk")

        #expect(comparison.status == "identical")
        #expect(comparison.aheadBy == 0)
    }

    // MARK: - 建分支

    @Test("⚠️ 建分支：请求体是 `{ref, sha}`（**没有** object 这一层），且 ref 带前缀")
    func createBranchBodyShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(#"{"ref":"refs/heads/feature/x","object":{"sha":"head-sha","type":"commit"}}"#, status: 201)
        )

        let reference = try await makeEndpoint(harness: harness)
            .createBranch(owner: "o", repo: "r", name: "feature/x", sha: "head-sha")

        let request = try #require(harness.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/repos/o/r/git/refs")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try bodyJSON(harness)
        #expect(body == ["ref": "refs/heads/feature/x", "sha": "head-sha"])

        // 响应里 sha 被包进 object —— 与请求体**形状不同**，所以不能共用一个类型
        #expect(reference.object.sha == "head-sha")
        #expect(reference.shortName == "feature/x")
    }

    @Test("建分支成功后**失效分支列表缓存**（否则建完返回列表看不到刚建的那条）")
    func createBranchInvalidatesBranchList() async throws {
        let harness = StubURLProtocol.makeHarness()
        let cache = HTTPResponseCache(configuration: .memoryOnly())

        harness.stub(.json("[]"))
        let endpoint = makeEndpoint(harness: harness, cache: cache)
        _ = try await endpoint.branches(owner: "o", repo: "r")
        #expect(await cache.memoryEntryCount == 1)

        harness.stub(
            .json(#"{"ref":"refs/heads/x","object":{"sha":"s"}}"#, status: 201)
        )
        _ = try await endpoint.createBranch(owner: "o", repo: "r", name: "x", sha: "s")

        #expect(await cache.memoryEntryCount == 0)
    }

    // MARK: - 删分支

    @Test("⚠️ 删分支：DELETE 到 git/refs/heads/{branch}，成功是 204（没有响应体）")
    func deleteBranchRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 204))

        try await makeEndpoint(harness: harness)
            .deleteBranch(owner: "o", repo: "r", name: "feature/x")

        let request = try #require(harness.lastRequest)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/repos/o/r/git/refs/heads/feature/x")
    }

    @Test("删分支后**三条缓存一起失效**（§9.7.1：删的若是当前分支，会继续按已不存在的 ref 请求而 404）")
    func deleteBranchInvalidatesContentsAndCommits() async throws {
        let harness = StubURLProtocol.makeHarness()
        let cache = HTTPResponseCache(configuration: .memoryOnly())
        let endpoint = makeEndpoint(harness: harness, cache: cache)

        harness.stub(.json("[]"))
        _ = try await endpoint.branches(owner: "o", repo: "r")
        _ = try await GitHubRepoContentEndpoint(client: endpointClient(harness: harness, cache: cache))
            .contents(owner: "o", repo: "r")
        _ = try await GitHubRepoCommitEndpoint(client: endpointClient(harness: harness, cache: cache))
            .commits(owner: "o", repo: "r")
        #expect(await cache.memoryEntryCount == 3)

        harness.stub(.empty(status: 204))
        try await endpoint.deleteBranch(owner: "o", repo: "r", name: "feature/x")

        #expect(await cache.memoryEntryCount == 0)
    }

    @Test("删受保护分支：服务端回 422 ⇒ `validation`（**不是** conflict，也不是权限错误）")
    func deleteProtectedBranchSurfaces422() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"{"message":"Protected branch can't be deleted","errors":[{"resource":"Branch","code":"protected"}]}"#,
                status: 422
            )
        )

        await #expect(throws: GitHubError.validation(["Branch: protected"])) {
            try await makeEndpoint(harness: harness)
                .deleteBranch(owner: "o", repo: "r", name: "main")
        }
    }

    // MARK: - 合并

    @Test("合并：base / head / commit_message 进请求体")
    func mergeBodyShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"{"sha":"merge-sha","merged":true,"message":"Merge made by the 'recursive' strategy."}"#,
                status: 201
            )
        )

        let outcome = try await makeEndpoint(harness: harness)
            .merge(owner: "o", repo: "r", base: "main", head: "feature/x", message: "Merge feature/x")

        let request = try #require(harness.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/repos/o/r/merges")

        let body = try bodyJSON(harness)
        #expect(body["base"] == "main")
        #expect(body["head"] == "feature/x")
        #expect(body["commit_message"] == "Merge feature/x")

        guard case .merged(let result) = outcome else {
            Issue.record("201 应当是 .merged，实际是 \(outcome)")
            return
        }
        #expect(result.sha == "merge-sha")
        #expect(result.merged)
    }

    @Test("合并：不带信息 ⇒ 请求体里**没有** commit_message（不写空串）")
    func mergeWithoutMessageOmitsField() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"sha":"s","merged":true}"#, status: 201))

        _ = try await makeEndpoint(harness: harness)
            .merge(owner: "o", repo: "r", base: "main", head: "topic")

        let body = try bodyJSON(harness)
        #expect(body["commit_message"] == nil)
    }

    @Test("⚠️ 合并 204 ⇒ `.nothingToMerge` —— **这不是失败**：head 已经合进 base 了")
    func mergeNothingToMergeIsNotAnError() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 204))

        let outcome = try await makeEndpoint(harness: harness)
            .merge(owner: "o", repo: "r", base: "main", head: "topic")

        // 当成失败会让用户反复点，而每次都是 204
        #expect(outcome == .nothingToMerge)
    }

    @Test("合并冲突：409 ⇒ `conflict`（客户端解决不了，按 PRD 引导去网页端）")
    func mergeConflictSurfaces409() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"message":"Merge conflict"}"#, status: 409))

        await #expect(throws: GitHubError.conflict) {
            _ = try await makeEndpoint(harness: harness)
                .merge(owner: "o", repo: "r", base: "main", head: "topic")
        }
    }

    @Test("合并成功后失效 branches / commits / contents 三条缓存（base 的 HEAD 动了）")
    func mergeInvalidatesHeadDependentPaths() async throws {
        let harness = StubURLProtocol.makeHarness()
        let cache = HTTPResponseCache(configuration: .memoryOnly())
        let endpoint = makeEndpoint(harness: harness, cache: cache)

        harness.stub(.json("[]"))
        _ = try await endpoint.branches(owner: "o", repo: "r")
        _ = try await GitHubRepoCommitEndpoint(client: endpointClient(harness: harness, cache: cache))
            .commits(owner: "o", repo: "r")
        #expect(await cache.memoryEntryCount == 2)

        harness.stub(.empty(status: 204))
        _ = try await endpoint.merge(owner: "o", repo: "r", base: "main", head: "topic")

        #expect(await cache.memoryEntryCount == 0)
    }

    // MARK: - 内部

    /// 让另外两个端点共用同一份会话与缓存 —— 用来断言"删分支会连带清掉 contents / commits"。
    private func endpointClient(
        harness: StubURLProtocol.Harness,
        cache: HTTPResponseCache
    ) -> GitHubRESTClient {
        let clock = now
        return GitHubRESTClient(
            credentials: credentials,
            transport: HTTPTransport(
                credentials: credentials,
                session: harness.makeSession(),
                cache: cache,
                retryPolicy: .none,
                clock: { clock },
                sleeper: { _ in }
            )
        )
    }
}
