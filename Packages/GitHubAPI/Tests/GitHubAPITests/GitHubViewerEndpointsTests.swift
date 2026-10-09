import Foundation
import Testing

@testable import GitHubAPI

/// 「我的」页的资料头部 —— `GET /user`（TECH_SPEC §9.14、PRD §4.17、决策 #76）。
///
/// 本套件盯三件事：
/// 1. **请求形状**：普通 `GET /user`、主桶、**缓存开着**（与登录路径那个
///    `GitHubUserEndpoint` 有意相反 —— 那个 `cachesResponse: false`）；
/// 2. **解码**：`name` / `bio` 可为 `null`，而 `followers` 缺了不许静默给 0；
/// 3. **错误原样抛**：401 归一到 `.unauthorized`（凭据失效 ⇒ 上层登出），
///    404 / 5xx 也各自带着自己的 case 出去，不在这里被折叠成"这一块加载失败"。
@Suite("GitHubViewerProfileEndpoint · GET /user（我的页资料）")
struct GitHubViewerProfileEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEndpoint(harness: StubURLProtocol.Harness) -> GitHubViewerProfileEndpoint {
        let clock = now
        return GitHubViewerProfileEndpoint(
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

    private let profileJSON = #"""
    {"login":"octocat","name":"小明","bio":"写 Swift 的","followers":126,
     "avatar_url":"https://example.com/a.png","public_repos":42}
    """#

    // MARK: - 请求形状

    @Test("请求形状：GET /user，版本头由 transport 统一注入（§4.2）")
    func buildsRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(profileJSON))

        _ = try await makeEndpoint(harness: harness).loadProfile()

        let request = try #require(harness.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.github.com/user")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
        // 首屏没有本地副本，所以不该带条件请求头（带了也只是白问一次）
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test("⚠️ 缓存**开着**：第二次请求带 `If-None-Match`（304 不计配额，决策 #32 的自建缓存）")
    func secondCallSendsIfNoneMatch() async throws {
        // 与 `GitHubUserEndpoint`（登录第 8 步的一次性校验，`cachesResponse: false`）
        // 有意相反：这里是页面内容，命中 304 就白拿一份最新数据。
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(profileJSON, headers: ["ETag": #""abc123""#]))

        let endpoint = makeEndpoint(harness: harness)
        _ = try await endpoint.loadProfile()
        _ = try await endpoint.loadProfile()

        #expect(harness.requestCount == 2, "本地有副本 ⇒ 第二次仍然要问一次，但带条件头")
        // ⚠️ 断言的是**第二次**那个请求（第一次必然没有这个头）。
        let second = try #require(harness.requests.last)
        #expect(second.value(forHTTPHeaderField: "If-None-Match") == #""abc123""#)
    }

    // MARK: - 解码

    @Test("解码：登录名 / 昵称 / 简介 / 关注者数（多余的字段被忽略）")
    func decodesProfile() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(profileJSON))

        let dto = try await makeEndpoint(harness: harness).loadProfile()

        #expect(dto.login == "octocat")
        #expect(dto.name == "小明")
        #expect(dto.bio == "写 Swift 的")
        #expect(dto.followers == 126)
    }

    @Test("⚠️ `name` / `bio` 为 `null` ⇒ `nil`，不是空串（PRD §4.17：整行不渲染）")
    func nullNameAndBioDecodeToNil() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"login":"octocat","name":null,"bio":null,"followers":3}"#))

        let dto = try await makeEndpoint(harness: harness).loadProfile()

        #expect(dto.name == nil)
        #expect(dto.bio == nil)
    }

    @Test("⚠️ 少了 `followers` ⇒ 抛 `.decoding`（**不许静默给 0**）")
    func missingFollowersThrowsDecoding() async {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"login":"octocat","name":"小明","bio":null}"#))

        await #expect(throws: GitHubError.self) {
            _ = try await self.makeEndpoint(harness: harness).loadProfile()
        }
    }

    // MARK: - 错误

    @Test("⚠️ 401 归一成 `.unauthorized`（凭据失效 ⇒ 上层登出），不被吞成「这一块失败」")
    func carriesUnauthorizedVerbatim() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"message":"Bad credentials"}"#, status: 401))

        // 归一化只有一处（数据层的令牌出口，决策 #33）。在这里再包一层的话，
        // "令牌失效"会退化成"我的页加载失败"，而用户会一直停在一个再也登不出去的状态里。
        await #expect(throws: GitHubError.unauthorized) {
            _ = try await self.makeEndpoint(harness: harness).loadProfile()
        }
    }

    @Test("404 / 5xx 各自带着自己的 case 出去（不在这里编造结论）")
    func carriesOtherErrorsVerbatim() async throws {
        let notFound = StubURLProtocol.makeHarness()
        notFound.stub(.json(#"{"message":"Not Found"}"#, status: 404))
        await #expect(throws: GitHubError.notFound) {
            _ = try await self.makeEndpoint(harness: notFound).loadProfile()
        }

        let server = StubURLProtocol.makeHarness()
        server.stub(.json(#"{"message":"boom"}"#, status: 503))
        await #expect(throws: GitHubError.serverError(status: 503)) {
            _ = try await self.makeEndpoint(harness: server).loadProfile()
        }
    }
}

/// 「我的」页的热力图 + 两个计数 —— **一次** GraphQL 查询（TECH_SPEC §13.2、决策 #74 / #76）。
///
/// 本套件盯的是"这一次花几点"这件事本身：查询文本里任何一个 `first:` 写错
/// （`1` 写成 `100`、或者给数组硬塞一个 `first:`），**都不会报错**，
/// 只会让点数悄悄变成 100 点、或者让服务端直接拒。
@Suite("GitHubViewerActivityEndpoint · GraphQL（热力图 + 两个计数）")
struct GitHubViewerActivityEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEndpoint(harness: StubURLProtocol.Harness) -> GitHubViewerActivityEndpoint {
        let clock = now
        return GitHubViewerActivityEndpoint(
            client: GitHubGraphQLClient(
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

    /// 一个形状齐全的响应（字段名逐个对着 `ViewerActivityDTO` 抄）。
    private let viewerJSON = #"""
    {"contributionsCollection":{"contributionCalendar":{"totalContributions":1024,"weeks":[
       {"firstDay":"2026-01-01","contributionDays":[
         {"date":"2026-01-01","contributionCount":0,"contributionLevel":"NONE","weekday":4}
       ]},
       {"firstDay":"2026-01-04","contributionDays":[
         {"date":"2026-01-04","contributionCount":7,"contributionLevel":"FOURTH_QUARTILE","weekday":0},
         {"date":"2026-01-05","contributionCount":1,"contributionLevel":"FIRST_QUARTILE","weekday":1},
         {"date":"2026-01-06","contributionCount":2,"contributionLevel":"SECOND_QUARTILE","weekday":2},
         {"date":"2026-01-07","contributionCount":5,"contributionLevel":"THIRD_QUARTILE","weekday":3},
         {"date":"2026-01-08","contributionCount":0,"contributionLevel":"NONE","weekday":4},
         {"date":"2026-01-09","contributionCount":1,"contributionLevel":"FIRST_QUARTILE","weekday":5},
         {"date":"2026-01-10","contributionCount":9,"contributionLevel":"FOURTH_QUARTILE","weekday":6}
       ]}
     ]}},"starredRepositories":{"totalCount":318},"repositories":{"totalCount":42}}
    """#

    private func envelope(_ viewer: String) -> String {
        #"{"data":{"viewer":"# + viewer + #"}}"#
    }

    // MARK: - 查询形状

    @Test("请求形状：POST /graphql，**没有变量**（`first: 1` 与 affiliations 都在文本里）")
    func buildsQueryShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(viewerJSON)))

        _ = try await makeEndpoint(harness: harness).loadActivity()

        let request = try #require(harness.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.github.com/graphql")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")

        let body = try #require(harness.lastBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let query = try #require(json["query"] as? String)

        // ⚠️ 一次查询 = 1 点。`first` 进变量就等于留了一个"传 100 就变 100 点"的入口，
        //    而 `totalCount` 在 `first: 1` 与 `first: 100` 下**完全一样**。
        #expect(!query.contains("$first"), "两个计数的 `first:` 不进变量 —— 它是点数预算的边界")
        #expect(
            query.components(separatedBy: "first: 1").count - 1 == 2,
            "恰好两个计数连接，且各写死 `first: 1`"
        )
        #expect(json["variables"] is [String: Any], "没有变量 ⇒ 空对象，不是缺键")

        // ⚠️ 决策 #76：默认只算 OWNER，不写全就会与仓库列表（决策 #35）静默对不上。
        #expect(
            query.contains("affiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER]"),
            "少了这个，我的页的「仓库」数会小于仓库列表里的条数"
        )
        #expect(query.contains("starredRepositories(first: 1)"))

        // ⚠️ §13.2 那处已修的错：这两个是**数组**，带 `first:` 会被服务端直接拒。
        #expect(!query.contains("weeks(first"), "`weeks` 是 `[X!]!`，不是连接")
        #expect(!query.contains("contributionDays(first"), "`contributionDays` 同理")

        // 字段名逐个钉住（改一处就要同时改 `ContributionCalendarDTO`）。
        for field in ["totalContributions", "firstDay", "date",
                      "contributionCount", "contributionLevel", "weekday"] {
            #expect(query.contains(field), "查询文本里少了一个 `ContributionCalendarDTO` 的字段名")
        }
    }

    // MARK: - 解码

    @Test("解码：`viewer` 下三个字段一次拿回（两块都在同一个信封里）")
    func decodesViewer() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(viewerJSON)))

        let dto = try await makeEndpoint(harness: harness).loadActivity()

        #expect(dto.contributionsCollection.contributionCalendar.totalContributions == 1_024)
        #expect(dto.starredRepositories.totalCount == 318)
        #expect(dto.repositories.totalCount == 42)

        let weeks = dto.contributionsCollection.contributionCalendar.weeks
        #expect(weeks.count == 2)
        #expect(weeks[0].contributionDays.count == 1, "头尾两周不足 7 天是正常形状")
        #expect(weeks[1].contributionDays.count == 7)
        #expect(weeks[1].contributionDays[0].date == "2026-01-04")
        #expect(weeks[1].contributionDays[0].contributionLevel == "FOURTH_QUARTILE")
        #expect(weeks[1].contributionDays[0].weekday == 0)
    }

    // MARK: - GraphQL 的两种失败

    @Test("⚠️ 部分成功（`data` + `errors` 并存）⇒ **抛错**，不打捞那份 `partialData`")
    func partialSuccessThrows() async throws {
        // 这不是"服务端坏了"，而是 GraphQL 的合法响应形状（§4.3 第 2 条）。
        // 本期选择不打捞：这一页没有任何位置能说明"两个计数准、日历缺了几天"，
        // 而重试一次只要 1 点（`GitHubViewerActivityEndpoint.loadActivity` 的说明记着这条代价）。
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"""
        {"data":{"viewer":{"contributionsCollection":null,"starredRepositories":{"totalCount":1},
         "repositories":{"totalCount":2}}},"errors":[{"message":"contributions are not available"}]}
        """#))

        await #expect(throws: GitHubError.self) {
            _ = try await self.makeEndpoint(harness: harness).loadActivity()
        }
    }

    @Test("只有 `errors`（没有 `data`）⇒ 抛 `.graphQLErrors`，`partialData` 为 `nil`")
    func errorsOnlyThrows() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"errors":[{"message":"Something went wrong"}]}"#))

        do {
            _ = try await makeEndpoint(harness: harness).loadActivity()
            Issue.record("本该抛错")
        } catch let error as GitHubError {
            guard case let .graphQLErrors(messages, partialData) = error else {
                Issue.record("应当是 .graphQLErrors，实际是 \(error)")
                return
            }
            #expect(messages == ["Something went wrong"])
            #expect(partialData == nil, "没有 data ⇒ 没有可打捞的部分")
        }
    }

    @Test("网络层失败 ⇒ `.transport`（不是「这一块加载失败」那种笼统话）")
    func transportFailureSurfaces() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.failing(.notConnectedToInternet))

        await #expect(throws: GitHubError.self) {
            _ = try await self.makeEndpoint(harness: harness).loadActivity()
        }
    }
}
