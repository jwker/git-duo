import Foundation
import Testing

/// 桩件**自身**的规格 —— 命名空间隔离，以及"忘了用 harness 会响亮地失败"。
///
/// 为什么值得给测试基础设施写测试：本桩件早期是**进程级静态路由表** + 套件 `.serialized`。
/// 那是错的 —— Swift Testing 默认让不同套件并行，而 `.serialized` 只管套件内部 ⇒
/// 第二个用桩件的套件会和 `AuthCoordinatorTests` 互相覆盖，症状"单跑全绿、全量跑挂"。
///
/// 下面三条把修复钉住：
/// - 谁把全局状态加回来 ⇒ `harnessesAreIndependent` 红；
/// - 谁把"没有命名空间就放行"加回来 ⇒ `sessionWithoutHarnessFailsLoudly` 红；
/// - 谁把"规则不命中就放行"加回来 ⇒ `unmatchedRuleFailsLoudly` 红。
///
/// 这套件**故意不加 `.serialized`** —— 它本身就是"并行安全"这条主张的证据。
@Suite("StubURLProtocol · 命名空间隔离与路由")
struct StubURLProtocolIsolationTests {

    private struct Payload: Decodable, Equatable {
        let v: Int
    }

    private func fetch(_ harness: StubURLProtocol.Harness, path: String = "/x") async throws -> Int {
        let (data, _) = try await harness.makeSession().data(from: URL(string: "https://api.github.com\(path)")!)
        return try JSONDecoder().decode(Payload.self, from: data).v
    }

    @Test("两套 harness 互不干扰：各自的路由表只喂给自己的会话")
    func harnessesAreIndependent() async throws {
        let first = StubURLProtocol.makeHarness()
        let second = StubURLProtocol.makeHarness()
        first.setStubs([.response("GET", "/x", #"{"v":1}"#)])
        second.setStubs([.response("GET", "/x", #"{"v":2}"#)])

        // 交错取用：若状态还是全局的，第二次会把 first 的路由表换掉
        #expect(try await fetch(first) == 1)
        #expect(try await fetch(second) == 2)
        #expect(try await fetch(first) == 1, "用过 second 之后 first 的路由必须还在")

        #expect(first.count(method: "GET", path: "/x") == 2)
        #expect(second.count(method: "GET", path: "/x") == 1, "各自只记录自己的请求")
    }

    @Test("路由按方法 + 路径命中，不命中的那条不会被误用")
    func routingRespectsMethodAndPath() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.setStubs([
            .response("POST", "/x", #"{"v":9}"#),
            .response("GET", "/x", #"{"v":1}"#)
        ])

        #expect(try await fetch(harness) == 1, "GET 不该命中前面的 POST 规则")
        #expect(harness.count(method: "GET", path: "/x") == 1)
        #expect(harness.count(method: "POST", path: "/x") == 0)
    }

    @Test("规则不命中 ⇒ 请求失败，不静默放行")
    func unmatchedRuleFailsLoudly() async {
        let harness = StubURLProtocol.makeHarness()
        harness.setStubs([.response("GET", "/somewhere-else", "")])

        await #expect(throws: (any Error).self) {
            _ = try await fetch(harness)
        }
    }

    @Test("没走 harness 装配的会话：请求失败，不静默放行")
    func sessionWithoutHarnessFailsLoudly() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        // 静默放行会把"忘了用 harness"伪装成"拿到了一个意外的响应"——
        // 那种缺陷要靠猜才能定位，所以这里要求它**当场炸**。
        await #expect(throws: (any Error).self) {
            _ = try await session.data(from: URL(string: "https://api.github.com/user")!)
        }
    }
}
