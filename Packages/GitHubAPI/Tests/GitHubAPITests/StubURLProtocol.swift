import Foundation

/// `URLSession` 的桩件 —— 让网络测试既不真的出网，也能**断言实际发出的请求**。
///
/// 依据：TECH_SPEC §12.2（网络层测试用 `URLProtocol` 桩件断言请求头 / 请求体）。
///
/// ⚠️ 两个必须处理的坑（不处理的话断言会"莫名"看不到内容）：
/// 1. **`URLProtocol` 拿到的 `request.httpBody` 通常是 `nil`** —— URLSession 会把 body
///    转换成 `httpBodyStream`。要断言请求体，必须先把它读出来（见 `bodyData(of:)`）。
/// 2. **静态状态在 Swift 6 严格并发下必须显式保护** —— 用 `NSLock` + `nonisolated(unsafe)`。
///
/// ⚠️⚠️ **第三个坑（2026-10-06 真吃过，代价是"单跑全绿、全量跑挂"）**：
/// Swift Testing **默认让不同套件并行执行**，而 `.serialized` 只保证**套件内部**串行 ——
/// 于是两个用桩件的套件会互相覆盖桩响应：A 设好响应，B 一句 `stub(...)` 就把它清掉，
/// A 拿到的请求数变成 0、或解出 `invalidResponse`。**症状像代码坏了，其实是测试互相踩**。
/// 解法：**每个套件自持一个 `Harness`**（下方），状态按命名空间隔离，天然可并行。
///
/// **只有一种用法**：`private let harness = StubURLProtocol.makeHarness()`，
/// 之后 `harness.makeSession()` / `harness.stub(_:)` / `harness.requestCount` …
///
/// ⚠️ 2026-10-06 之前本类型还留着一套**进程级静态入口**（转发到"默认 harness"），
/// 理由是"一个包里只有一个套件用它时照旧能跑"。那是**半个补丁**：只要再有第二个套件
/// 图省事用了它，上面的事故就原封不动回来。所以整套删掉 —— 连"写得出"都不允许。
/// 现在会话若不带命名空间头，请求一律失败（见 `startLoading`），
/// 把"忘了用 harness"立刻变成一个红测试，而不是一个靠猜的偶发。
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    /// 命名空间标记 —— 挂在会话的附加请求头上，`startLoading` 据此找回所属桩状态。
    /// 桩会话的 `protocolClasses` 只含本类，请求不会真的出网，所以这个头不会外泄。
    fileprivate static let namespaceHeader = "X-Stub-Harness"

    /// 一次桩响应
    struct Response: Sendable {
        var status: Int
        var body: Data
        var headers: [String: String]
        /// 非 nil 时改为**让请求失败**（模拟断网、超时这类网络层错误）。
        var failure: URLError?

        static func json(_ raw: String, status: Int = 200, headers: [String: String] = [:]) -> Response {
            var merged = headers
            merged["Content-Type"] = merged["Content-Type"] ?? "application/json"
            return Response(status: status, body: Data(raw.utf8), headers: merged)
        }

        static func empty(status: Int, headers: [String: String] = [:]) -> Response {
            Response(status: status, body: Data(), headers: headers)
        }

        /// 请求在**网络层**失败（拿不到响应）—— 与 5xx 是两回事。
        static func failing(_ code: URLError.Code) -> Response {
            Response(status: 0, body: Data(), headers: [:], failure: URLError(code))
        }
    }

    // MARK: - Harness：一套彼此独立的桩状态

    /// 一个测试套件（或一个用例）自持一套，彼此不干扰。
    final class Harness: @unchecked Sendable {

        fileprivate let namespace: String
        private let lock = NSLock()
        private var responses: [Response] = []
        private var recordedRequests: [URLRequest] = []
        private var recordedBodies: [Data?] = []

        fileprivate init(namespace: String) {
            self.namespace = namespace
        }

        /// 用本套桩件装配 session（每个用例建一个，避免共享状态）。
        func makeSession() -> URLSession {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            configuration.httpAdditionalHeaders = [StubURLProtocol.namespaceHeader: namespace]
            return URLSession(configuration: configuration)
        }

        /// 设置桩响应：**该响应会被后续每次请求重复使用**，并清空已记录的请求。
        func stub(_ response: Response) {
            stub([response])
        }

        /// 设置一串桩响应：按顺序消费，**最后一个会被重复使用**。
        ///
        /// 用于"第一次 401、第二次 200"这类必须区分次序的用例（如 401→刷新→重放）。
        /// 单响应版本其实是这个的特例，`stub(_ response:)` 转发到这里。
        func stub(_ sequence: [Response]) {
            lock.withLock {
                responses = sequence
                recordedRequests = []
                recordedBodies = []
            }
        }

        func reset() {
            lock.withLock {
                responses = []
                recordedRequests = []
                recordedBodies = []
            }
        }

        var requests: [URLRequest] { lock.withLock { recordedRequests } }

        var requestCount: Int { lock.withLock { recordedRequests.count } }

        var lastRequest: URLRequest? { lock.withLock { recordedRequests.last } }

        var lastBody: Data? { lock.withLock { recordedBodies.last ?? nil } }

        fileprivate func record(_ request: URLRequest, body: Data?) -> Response? {
            lock.withLock {
                recordedRequests.append(request)
                recordedBodies.append(body)

                guard let next = responses.first else { return nil }
                if responses.count > 1 { responses.removeFirst() }
                return next
            }
        }
    }

    // MARK: - 注册表（命名空间 → harness）

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var harnesses: [String: Harness] = [:]

    /// 新建一套独立桩状态 —— **唯一**的入口。
    static func makeHarness() -> Harness {
        let harness = Harness(namespace: UUID().uuidString)
        registryLock.withLock { harnesses[harness.namespace] = harness }
        return harness
    }

    private static func harness(for request: URLRequest) -> Harness? {
        guard let namespace = request.value(forHTTPHeaderField: namespaceHeader) else { return nil }
        return registryLock.withLock { harnesses[namespace] }
    }

    /// 把请求体读出来 —— `httpBody` 常为 `nil`，真实数据在 `httpBodyStream` 上。
    static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = StubURLProtocol.bodyData(of: request)

        // 没有命名空间（= 会话不是 harness 装的）或响应没设 ⇒ **让请求失败**。
        // 绝不静默放行：那会把"忘了用 harness"伪装成"拿到了一个意外的响应"。
        let stubbed = StubURLProtocol.harness(for: request)?.record(request, body: body)

        guard let stubbed, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if let failure = stubbed.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        guard let http = HTTPURLResponse(
            url: url,
            statusCode: stubbed.status,
            httpVersion: "HTTP/1.1",
            headerFields: stubbed.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        if !stubbed.body.isEmpty {
            client?.urlProtocol(self, didLoad: stubbed.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
