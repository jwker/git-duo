import Foundation
import Testing

/// 桩件**自身**的规格 —— 命名空间隔离，以及"忘了用 harness 会响亮地失败"。
///
/// 为什么值得给测试基础设施写测试：2026-10-06 之前本桩件是**进程级静态状态**，
/// 两个套件并行时会互相覆盖桩响应 —— 症状是"**单跑全绿、全量跑挂**"，
/// 且失败信息指向别处，极难定位（那次真实代价：半天）。
///
/// 下面两条断言把当时的修复**钉住**：
/// - 谁要是把全局状态加回来 ⇒ `harnessesAreIndependent` 会红；
/// - 谁要是把"没有命名空间就放行"加回来 ⇒ `sessionWithoutHarnessFailsLoudly` 会红。
///
/// 一句话：**让复发变成编译期/测试期的显式失败，而不是偶发**。
@Suite("StubURLProtocol · 命名空间隔离")
struct StubURLProtocolIsolationTests {

    private struct Payload: Decodable, Equatable {
        let v: Int
    }

    private func fetch(_ harness: StubURLProtocol.Harness) async throws -> Int {
        let url = URL(string: "https://api.github.com/x")!
        let (data, _) = try await harness.makeSession().data(from: url)
        return try JSONDecoder().decode(Payload.self, from: data).v
    }

    @Test("两套 harness 互不干扰：各自的桩响应只喂给自己的会话")
    func harnessesAreIndependent() async throws {
        let first = StubURLProtocol.makeHarness()
        let second = StubURLProtocol.makeHarness()
        first.stub(.json(#"{"v":1}"#))
        second.stub(.json(#"{"v":2}"#))

        // 交错取用：若状态还是全局的，第二次会读到第一次的响应
        #expect(try await fetch(first) == 1)
        #expect(try await fetch(second) == 2)
        #expect(try await fetch(first) == 1, "用过 second 之后 first 的响应必须还在")

        #expect(first.requestCount == 2)
        #expect(second.requestCount == 1, "各自只记录自己的请求")
    }

    @Test("没走 harness 装配的会话：请求**失败**，不静默放行")
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
