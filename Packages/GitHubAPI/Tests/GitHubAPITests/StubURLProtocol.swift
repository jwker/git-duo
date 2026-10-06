import Foundation

/// `URLSession` 的桩件 —— 让网络测试既不真的出网，也能**断言实际发出的请求**。
///
/// 依据：TECH_SPEC §12.2（网络层测试用 `URLProtocol` 桩件断言请求头 / 请求体）。
///
/// ⚠️ 两个必须处理的坑（不处理的话断言会"莫名"看不到内容）：
/// 1. **`URLProtocol` 拿到的 `request.httpBody` 通常是 `nil`** —— URLSession 会把 body
///    转换成 `httpBodyStream`。要断言请求体，必须先把它读出来（见 `bodyData(of:)`）。
/// 2. **静态状态在 Swift 6 严格并发下必须显式保护** —— 这里用 `NSLock` + `nonisolated(unsafe)`。
///    因此用到本桩件的测试套件**必须 `.serialized`**，否则会互相覆盖桩响应。
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    /// 一次桩响应
    struct Response: Sendable {
        var status: Int
        var body: Data
        var headers: [String: String]

        static func json(_ raw: String, status: Int = 200) -> Response {
            Response(status: status,
                     body: Data(raw.utf8),
                     headers: ["Content-Type": "application/json"])
        }

        static func empty(status: Int) -> Response {
            Response(status: status, body: Data(), headers: [:])
        }
    }

    private struct State {
        var response: Response?
        var requests: [URLRequest] = []
        var bodies: [Data?] = []
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var state = State()

    // MARK: - 测试侧控制

    /// 设置下一次（及后续）请求的桩响应，并清空已记录的请求。
    static func stub(_ response: Response) {
        lock.lock()
        defer { lock.unlock() }
        state = State()
        state.response = response
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        state = State()
    }

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return state.requests.count
    }

    static var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return state.requests.last
    }

    static var lastBody: Data? {
        lock.lock()
        defer { lock.unlock() }
        return state.bodies.last ?? nil
    }

    /// 用本桩件装配一个 session（每个用例建一个，避免共享状态）。
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
        let stubbed = StubURLProtocol.state.response
        StubURLProtocol.lock.unlock()

        guard let stubbed, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
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
