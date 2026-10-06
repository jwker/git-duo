import Foundation

/// 分桶限流器 —— 把"别把配额打爆"从纪律变成不变量（TECH_SPEC §4.5 处置策略 2）。
///
/// **为什么需要它**：搜索类端点是**独立且极紧**的配额（30/分钟，代码搜索约 10/分钟），
/// 而它们又都在用户"边输边搜""连点切榜"这种高频路径上。只靠防抖挡不住全部情形，
/// 所以还需要一个在**发请求之前**就能拦住的地方。
///
/// **模型**：容量 1 的令牌桶 —— 等价于"两次同桶请求之间至少间隔 `minimumInterval`"。
/// 之所以不做多容量令牌桶：本项目的突发场景（连点切榜）已经由防抖 + 取消 + 缓存三件事
/// 吸收掉了（§13.2），再引入容量只会让"此刻能不能发"变得难以推理。
///
/// **串行**：`withSlot` 额外的保证"同一个桶同时只有一个操作在跑"（§4.5 要求代码搜索串行）。
/// 间隔控制与串行是两件事 —— 前者管速率，后者管并发，都需要。
///
/// ⚠️ **时钟与 sleep 都可注入**：否则测试要么真的等（搜索桶间隔是秒级，几个用例就能拖垮套件），
/// 要么只能靠"跑得快"来间接验证（那等于没验）。
public actor RateLimiter {

    /// 取当前时刻。注入而非直接 `Date()`。
    public typealias Clock = @Sendable () -> Date

    /// 挂起指定时长。注入而非直接 `Task.sleep` —— 见类型说明。
    public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    public enum Bucket: Hashable, Sendable {
        case core
        case search
        case codeSearch
        case graphql
    }

    /// 一个桶的速率策略。
    ///
    /// `minimumInterval == 0` 表示不限速 —— 用于那些"靠 ETag 与业务缓存自然压住"的桶。
    public struct Policy: Sendable, Equatable {

        public let minimumInterval: TimeInterval

        public init(minimumInterval: TimeInterval) {
            self.minimumInterval = minimumInterval
        }

        /// §4.5 的默认策略。
        public static let defaults: [Bucket: Policy] = [
            // REST 主桶 5,000/小时，摊到秒上远低于任何真实点击速率 ⇒ 不需要人工限速，
            // 真正压住它的是 ETag 条件请求（304 不计配额）。
            .core: Policy(minimumInterval: 0),
            // Search 桶 30 次/分钟 ⇒ 2 秒一次
            .search: Policy(minimumInterval: 60.0 / 30.0),
            // 代码搜索官方有 9/10 两种说法，**按 9 保守预算**（§4.5）
            .codeSearch: Policy(minimumInterval: 60.0 / 9.0),
            // GraphQL 按点计费而非请求数，点数纪律在查询设计里（§13.2），不在这一层
            .graphql: Policy(minimumInterval: 0),
        ]
    }

    private let policies: [Bucket: Policy]
    private let clock: Clock
    private let sleeper: Sleeper

    /// 每个桶"下一次允许发出的时刻"。
    private var nextAllowed: [Bucket: Date] = [:]

    /// 每个桶的串行闸门（容量 1 信号量），惰性创建。
    private var gates: [Bucket: AsyncSemaphore] = [:]

    public init(
        policies: [Bucket: Policy] = Policy.defaults,
        clock: @escaping Clock = { Date() },
        sleeper: @escaping Sleeper = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.policies = policies
        self.clock = clock
        self.sleeper = sleeper
    }

    /// 取一次许可；若距上次同桶请求不足 `minimumInterval`，**挂起直到够了为止**。
    ///
    /// - Throws: `CancellationError`（等待期间任务被取消 —— 搜索防抖依赖这条取消链）。
    public func acquire(_ bucket: Bucket) async throws {
        guard let policy = policies[bucket], policy.minimumInterval > 0 else { return }

        let now = clock()
        if let next = nextAllowed[bucket], next > now {
            try await sleeper(next.timeIntervalSince(now))
        }

        // ⚠️ sleep 之后**重新取时刻**：注入的 sleeper 在测试里可能什么都不做，
        //    此时若沿用 sleep 前的 `now`，间隔就永远不会前进（限流形同虚设）。
        nextAllowed[bucket] = clock().addingTimeInterval(policy.minimumInterval)
    }

    /// 串行 + 限速地执行一次操作：同桶操作**一个接一个**，且相邻两次不短于 `minimumInterval`。
    ///
    /// 用它的地方是"并发会真的坏事"的桶（代码搜索）；普通列表请求用 `acquire` 就够。
    public func withSlot<T: Sendable>(
        _ bucket: Bucket,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        let gate = gate(for: bucket)

        await gate.wait()
        do {
            try await acquire(bucket)
            let result = try await operation()
            await gate.signal()
            return result
        } catch {
            // ⚠️ 任何出口都必须放行 —— 漏掉这一条，一次失败就把该桶**永久卡死**
            //    （后来的请求全部堆在 `wait()` 上，且没有超时）。
            await gate.signal()
            throw error
        }
    }

    /// 供测试与调试读取"该桶下次允许发出的时刻"。
    public func nextAllowedAt(_ bucket: Bucket) -> Date? {
        nextAllowed[bucket]
    }

    private func gate(for bucket: Bucket) -> AsyncSemaphore {
        if let existing = gates[bucket] { return existing }
        let created = AsyncSemaphore(value: 1)
        gates[bucket] = created
        return created
    }
}

// MARK: - 响应头里的桶名 ↔ 限流器的桶

extension RateLimiter.Bucket {

    /// 由 `RateLimitResource`（响应头 `x-ratelimit-resource` 的取值）映射过来。
    ///
    /// ⚠️ **认不出来就返回 `nil`（不限速），不要落回 `.core`**：未知桶意味着我们对它的
    ///    限额一无所知，套用主桶的"不限速"只是恰好无害；但若将来某个新桶比主桶紧，
    ///    默默当主桶就会把配额打爆。`nil` 让调用方显式地"什么都不做"，语义诚实。
    public init?(_ resource: RateLimitResource) {
        switch resource {
        case .core:
            self = .core
        case .search:
            self = .search
        case .codeSearch:
            self = .codeSearch
        case .graphql:
            self = .graphql
        case .other:
            return nil
        }
    }

    /// 该桶是否必须**串行**执行。
    ///
    /// 依据 §4.5 处置策略 2 的原文："代码搜索**串行** + 手动间隔，绝不象普通请求那样并发"。
    /// 串行与限速是两件事 —— 前者防"同时撞上硬限后互相加剧失败"，后者防"总体打得太快"。
    var requiresSerialization: Bool { self == .codeSearch }
}

/// 容量固定的异步信号量。自建 —— 本项目零第三方依赖（决策 #12），
/// 而 Swift 标准库里没有这个原语。
///
/// 只实现"容量 1 的互斥"所需的两个操作，不做通用的多值信号量：
/// 用不到的能力不写，也就不会有人误用。
actor AsyncSemaphore {

    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.available = max(1, value)
    }

    func wait() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if waiters.isEmpty {
            available += 1
        } else {
            // 直接移交给下一个等待者，不经过 `available` —— 避免"刚加回去就被别人抢走"
            // 造成的插队。
            waiters.removeFirst().resume()
        }
    }
}
