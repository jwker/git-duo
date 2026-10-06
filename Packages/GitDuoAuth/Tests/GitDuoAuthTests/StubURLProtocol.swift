import Foundation

/// `URLSession` 桩件 —— 支持**按端点路由**与**延迟响应**。
///
/// 依据：TECH_SPEC §12.2（网络层测试用 `URLProtocol` 桩件断言请求头 / 请求体）。
///
/// 与 `GitHubAPITests` 里那份（一个响应应答所有请求）的区别，正是编排测试的需要：
/// 1. **路由**：一次授权要连着打三个不同端点（换令牌 → `GET /user` → 撤销），
///    单一响应无法表达；
/// 2. **延迟**：验证 single-flight 必须制造"请求还没回来"的窗口，
///    否则并发调用会各自等到结果，测不出共享。
///
/// ⚠️ 两个坑同前：
/// - `URLProtocol` 拿到的 `request.httpBody` 通常是 `nil`，真实数据在 `httpBodyStream`
///   （见 `bodyData(of:)`）。
/// - 静态状态在 Swift 6 严格并发下必须显式保护 ⇒ 用到本桩件的套件**必须 `.serialized`**。
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

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

    private struct State {
        var stubs: [Stub] = []
        var requests: [URLRequest] = []
        var bodies: [Data?] = []
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var state = State()

    // MARK: - 测试侧控制

    /// 安装路由表并清空已记录的请求。匹配**自上而下取第一条命中**，因此把特殊规则放前面。
    static func setStubs(_ stubs: [Stub]) {
        lock.lock()
        defer { lock.unlock() }
        state = State()
        state.stubs = stubs
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        state = State()
    }

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return state.requests
    }

    static var bodies: [Data?] {
        lock.lock()
        defer { lock.unlock() }
        return state.bodies
    }

    /// 命中了多少次「某方法 + 某路径」——single-flight 的关键断言就靠它。
    static func count(method: String, path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return state.requests.filter {
            $0.httpMethod == method && $0.url?.path == path
        }.count
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
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

        StubURLProtocol.lock.lock()
        StubURLProtocol.state.requests.append(request)
        StubURLProtocol.state.bodies.append(body)
        let matched = StubURLProtocol.state.stubs.first { stub in
            (stub.method == nil || stub.method == request.httpMethod)
                && (stub.path == nil || stub.path == request.url?.path)
        }
        StubURLProtocol.lock.unlock()

        guard let matched else {
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
