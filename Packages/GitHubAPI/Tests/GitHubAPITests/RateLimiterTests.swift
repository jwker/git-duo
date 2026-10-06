import Foundation
import Testing

@testable import GitHubAPI

@Suite("限流器（§4.5）")
struct RateLimiterTests {

    // MARK: - 测试替身

    /// 可手动推进的时钟。
    final class ManualClock: @unchecked Sendable {
        private let lock = NSLock()
        private var now: Date

        init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
            self.now = start
        }

        var current: Date { lock.withLock { now } }

        func advance(_ seconds: TimeInterval) {
            lock.withLock { now += seconds }
        }
    }

    /// 只记录"被要求睡多久"，真的不睡 —— 否则搜索桶的秒级间隔会把套件拖慢到不可用。
    final class SleeperSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [TimeInterval] = []

        var durations: [TimeInterval] { lock.withLock { recorded } }

        func record(_ seconds: TimeInterval) {
            lock.withLock { recorded.append(seconds) }
        }
    }

    /// 记录并发峰值 —— 用来验"串行"是不是真的串行。
    final class ConcurrencyTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var active = 0
        private var peak = 0

        var maxConcurrent: Int { lock.withLock { peak } }

        func enter() {
            lock.withLock {
                active += 1
                peak = max(peak, active)
            }
        }

        func exit() {
            lock.withLock { active -= 1 }
        }
    }

    private struct Boom: Error {}

    private func makeLimiter(
        policies: [RateLimiter.Bucket: RateLimiter.Policy],
        clock: ManualClock,
        sleeper: SleeperSpy
    ) -> RateLimiter {
        RateLimiter(
            policies: policies,
            clock: { clock.current },
            sleeper: { seconds in sleeper.record(seconds) }
        )
    }

    // MARK: - 默认策略

    @Test("默认策略与 §4.5 的配额一致：search 30/min、codeSearch 按 9/min 保守")
    func defaultPolicies() {
        let defaults = RateLimiter.Policy.defaults

        #expect(defaults[.search]?.minimumInterval == 2.0)

        // 60 / 9 ≈ 6.67 —— 用近似比较，别把浮点表示误差当成规格漂移
        let codeInterval = defaults[.codeSearch]?.minimumInterval ?? 0
        #expect(abs(codeInterval - 60.0 / 9.0) < 0.001)

        // core / graphql 不限速：前者靠 ETag（304 不计配额），后者按点计费（§13.2）
        #expect(defaults[.core]?.minimumInterval == 0)
        #expect(defaults[.graphql]?.minimumInterval == 0)
    }

    // MARK: - 间隔控制

    @Test("不限速的桶：连续取许可，一次都不睡")
    func unrestrictedBucketNeverSleeps() async throws {
        let clock = ManualClock()
        let sleeper = SleeperSpy()
        let limiter = makeLimiter(policies: [.core: .init(minimumInterval: 0)], clock: clock, sleeper: sleeper)

        try await limiter.acquire(.core)
        try await limiter.acquire(.core)

        #expect(sleeper.durations.isEmpty)
    }

    @Test("请求头里没配的桶：视为不限速（而不是崩或永久拒绝）")
    func unconfiguredBucketIsUnrestricted() async throws {
        let clock = ManualClock()
        let sleeper = SleeperSpy()
        let limiter = makeLimiter(policies: [:], clock: clock, sleeper: sleeper)

        try await limiter.acquire(.search)

        #expect(sleeper.durations.isEmpty)
    }

    @Test("首次取许可不睡；紧接着的第二次必须等到间隔满（search = 2s）")
    func secondAcquireWaitsFullInterval() async throws {
        let clock = ManualClock()
        let sleeper = SleeperSpy()
        let limiter = makeLimiter(policies: [.search: .init(minimumInterval: 2)], clock: clock, sleeper: sleeper)

        try await limiter.acquire(.search)
        #expect(sleeper.durations.isEmpty)

        try await limiter.acquire(.search)

        #expect(sleeper.durations.count == 1)
        #expect(sleeper.durations.first == 2.0)
    }

    @Test("时钟已推进足够久 ⇒ 不需要睡（间隔是「至少」，不是「每次都等」）")
    func noWaitWhenEnoughTimePassed() async throws {
        let clock = ManualClock()
        let sleeper = SleeperSpy()
        let limiter = makeLimiter(policies: [.search: .init(minimumInterval: 2)], clock: clock, sleeper: sleeper)

        try await limiter.acquire(.search)
        clock.advance(3)

        try await limiter.acquire(.search)

        #expect(sleeper.durations.isEmpty)
    }

    @Test("时钟只推进一半 ⇒ 只补差额，不重新等满")
    func waitsOnlyTheRemainder() async throws {
        let clock = ManualClock()
        let sleeper = SleeperSpy()
        let limiter = makeLimiter(policies: [.search: .init(minimumInterval: 2)], clock: clock, sleeper: sleeper)

        try await limiter.acquire(.search)
        clock.advance(0.5)

        try await limiter.acquire(.search)

        #expect(sleeper.durations.count == 1)
        #expect(sleeper.durations.first == 1.5)
    }

    @Test("桶之间互不影响：search 的等待不牵连 core")
    func bucketsAreIndependent() async throws {
        let clock = ManualClock()
        let sleeper = SleeperSpy()
        let limiter = makeLimiter(
            policies: [.search: .init(minimumInterval: 2), .core: .init(minimumInterval: 0)],
            clock: clock,
            sleeper: sleeper
        )

        try await limiter.acquire(.search)
        try await limiter.acquire(.core)

        #expect(sleeper.durations.isEmpty)
    }

    @Test("nextAllowedAt 反映记录的放行时刻（供调试与 UI 用）")
    func exposesNextAllowed() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = ManualClock(start)
        let sleeper = SleeperSpy()
        let limiter = makeLimiter(policies: [.search: .init(minimumInterval: 2)], clock: clock, sleeper: sleeper)

        try await limiter.acquire(.search)

        #expect(await limiter.nextAllowedAt(.search) == start.addingTimeInterval(2))
    }

    // MARK: - 串行

    @Test("withSlot：同桶操作串行，峰值并发恒为 1")
    func withSlotSerializesSameBucket() async throws {
        let clock = ManualClock()
        let sleeper = SleeperSpy()
        let limiter = makeLimiter(policies: [.codeSearch: .init(minimumInterval: 0)], clock: clock, sleeper: sleeper)
        let tracker = ConcurrencyTracker()

        async let first = limiter.withSlot(.codeSearch) {
            tracker.enter()
            try? await Task.sleep(nanoseconds: 20_000_000)
            tracker.exit()
            return 1
        }
        async let second = limiter.withSlot(.codeSearch) {
            tracker.enter()
            try? await Task.sleep(nanoseconds: 20_000_000)
            tracker.exit()
            return 2
        }

        let a = try await first
        let b = try await second

        #expect([a, b].sorted() == [1, 2])
        #expect(tracker.maxConcurrent == 1)
    }

    @Test("withSlot：不同桶可并发（串行是按桶的，不是全局锁）")
    func withSlotAllowsDifferentBucketsConcurrently() async throws {
        let clock = ManualClock()
        let sleeper = SleeperSpy()
        let limiter = makeLimiter(
            policies: [.search: .init(minimumInterval: 0), .codeSearch: .init(minimumInterval: 0)],
            clock: clock,
            sleeper: sleeper
        )
        let tracker = ConcurrencyTracker()

        async let first = limiter.withSlot(.search) {
            tracker.enter()
            try? await Task.sleep(nanoseconds: 30_000_000)
            tracker.exit()
            return 1
        }
        async let second = limiter.withSlot(.codeSearch) {
            tracker.enter()
            try? await Task.sleep(nanoseconds: 30_000_000)
            tracker.exit()
            return 2
        }

        _ = try await (first, second)

        #expect(tracker.maxConcurrent == 2)
    }

    @Test("withSlot：操作抛错也必须放行闸门（否则该桶永久卡死）")
    func withSlotReleasesGateOnFailure() async throws {
        let clock = ManualClock()
        let sleeper = SleeperSpy()
        let limiter = makeLimiter(policies: [.codeSearch: .init(minimumInterval: 0)], clock: clock, sleeper: sleeper)

        var didThrow = false
        do {
            _ = try await limiter.withSlot(.codeSearch) { () -> Int in throw Boom() }
        } catch {
            didThrow = true
        }
        #expect(didThrow)

        // 关键断言：失败之后仍然进得去。若闸门漏放行，这一句会**永久挂起**（没有超时）。
        let value = try await limiter.withSlot(.codeSearch) { 42 }
        #expect(value == 42)
    }

    @Test("withSlot：返回值原样透传")
    func withSlotPassesValueThrough() async throws {
        let clock = ManualClock()
        let sleeper = SleeperSpy()
        let limiter = makeLimiter(policies: [.search: .init(minimumInterval: 0)], clock: clock, sleeper: sleeper)

        let value = try await limiter.withSlot(.search) { "ok" }

        #expect(value == "ok")
    }
}
