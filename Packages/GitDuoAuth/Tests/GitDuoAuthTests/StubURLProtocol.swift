import Foundation

/// `URLSession` 桩件 —— 支持**按端点路由**与**延迟响应**，且状态**按命名空间隔离**。
///
/// 依据：TECH_SPEC §12.2（网络层测试用 `URLProtocol` 桩件断言请求头 / 请求体）。
///
/// 与 `GitHubAPITests` 里那份的区别，正是编排测试的需要：
/// 1. **路由**：一次授权要连着打三个不同端点（换令牌 → `GET /user` → 撤销），
///    单一响应无法表达 ⇒ 本版是"命中即用"的**路由表**（自上而下取第一条命中，
///    且该规则会被后续请求**重复使用**，不是一次性的序列）；
/// 2. **延迟**：验证 single-flight 必须制造"请求还没回来"的窗口，
///    否则并发调用会各自等到结果，测不出共享。
///
/// ## ⚠️ 为什么这里**没有**任何进程级状态
///
/// 早期版本把路由表放在**进程级静态变量**里，靠套件 `.serialized` 硬扛。那是错的：
/// Swift Testing **默认让不同套件并行**，而 `.serialized` 只保证**套件内部**串行 ——
/// 于是两个用桩件的套件会互相覆盖（A 刚设好路由，B 一句 `setStubs` 就把它清掉），
/// 症状是"**单跑全绿、全量跑挂**"，看着像实现坏了，其实是测试互相踩。
/// （2026-10-06 在 `GitHubAPITests` 真吃过一次。）
///
/// 现在每个 `Harness` 是一个独立命名空间：会话把命名空间挂在**附加请求头**上，
/// `startLoading` 据此找回属于自己那一份状态 ⇒ 天然可并行，**不需要 `.serialized`**。
/// 本类型**不提供任何进程级入口**（没有默认 harness、没有静态 `setStubs`），
/// 所以那次事故在结构上不可能重演 —— 不是靠纪律避免，是写不出来。
///
/// ⚠️ 还有一个必须处理的坑：`URLProtocol` 拿到的 `request.httpBody` 通常是 `nil`，
/// 真实数据在 `httpBodyStream` 上（见 `bodyData(of:)`）。
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    /// 命名空间标记 —— 挂在桩会话的附加请求头上，`startLoading` 据此找回所属桩状态。
    /// 桩会话的 `protocolClasses` 只含本类，请求不会真的出网，所以这个头不会外泄。
    fileprivate static let namespaceHeader = "X-Stub-Harness"

    /// 一条路由规则。`method` / `path` 为 `nil` 表示"任意"。
    struct Stub: Sendable {
        var method: String?
        var path: String?
        var status: Int
        var body: String
        var delay: TimeInterval

        static func response(
            _ method: String?,
            _ path: String?,
            _ body: String = "",
            status: Int = 200,
            delay: TimeInterval = 0
        ) -> Stub {
            Stub(method: method, path: path, status: status, body: body, delay: delay)
        }
    }

    // MARK: - Harness：一套彼此独立的桩状态

    /// 一个测试套件（或一个用例）自持一套，彼此不干扰。
    final class Harness: @unchecked Sendable {

        fileprivate let namespace: String
        private let lock = NSLock()
        private var stubs: [Stub] = []
        private var recordedRequests: [URLRequest] = []
        private var recordedBodies: [Data?] = []

        fileprivate init(namespace: String) {
            self.namespace = namespace
        }

        /// 用**本套**桩件装配 session（每个用例建一个，避免共享状态）。
        func makeSession() -> URLSession {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            configuration.httpAdditionalHeaders = [StubURLProtocol.namespaceHeader: namespace]
            return URLSession(configuration: configuration)
        }

        /// 安装路由表并清空已记录的请求。匹配**自上而下取第一条命中**，因此把特殊规则放前面。
        func setStubs(_ stubs: [Stub]) {
            lock.withLock {
                self.stubs = stubs
                recordedRequests = []
                recordedBodies = []
            }
        }

        func reset() {
            lock.withLock {
                stubs = []
                recordedRequests = []
                recordedBodies = []
            }
        }

        var requests: [URLRequest] { lock.withLock { recordedRequests } }

        var bodies: [Data?] { lock.withLock { recordedBodies } }

        /// 命中了多少次「某方法 + 某路径」——single-flight 的关键断言就靠它。
        func count(method: String, path: String) -> Int {
            lock.withLock {
                recordedRequests.filter {
                    $0.httpMethod == method && $0.url?.path == path
                }.count
            }
        }

        /// 记录一次请求，并返回命中的规则（`nil` = 无规则命中 ⇒ 让请求失败）。
        fileprivate func record(_ request: URLRequest, body: Data?) -> Stub? {
            lock.withLock {
                recordedRequests.append(request)
                recordedBodies.append(body)
                return stubs.first { stub in
                    (stub.method == nil || stub.method == request.httpMethod)
                        && (stub.path == nil || stub.path == request.url?.path)
                }
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
    ///
    /// 无状态的纯工具，故留在类型上（不必先有 harness 才能用）。
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

        // 没有命名空间（= 会话不是 harness 装的）或规则没命中 ⇒ **让请求失败**。
        // 绝不静默放行：静默放行会把"忘了用 harness"伪装成"拿到了一个意外的响应"，
        // 而那种缺陷要靠猜才能定位。
        guard let matched = StubURLProtocol.harness(for: request)?.record(request, body: body)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        let respond: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            guard let url = self.request.url,
                  let http = HTTPURLResponse(
                      url: url,
                      statusCode: matched.status,
                      httpVersion: "HTTP/1.1",
                      headerFields: ["Content-Type": "application/json"]
                  )
            else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            let data = Data(matched.body.utf8)
            if !data.isEmpty {
                self.client?.urlProtocol(self, didLoad: data)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }

        if matched.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + matched.delay, execute: respond)
        } else {
            respond()
        }
    }

    override func stopLoading() {}
}
