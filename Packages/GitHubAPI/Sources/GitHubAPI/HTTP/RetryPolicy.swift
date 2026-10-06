import Foundation

/// 失败重试策略（TECH_SPEC §4.1 提到"重试"，本节是它的具体化）。
///
/// **只对幂等 GET 的"5xx / 瞬时网络故障"重试** —— 理由见 `HTTPMethod.isSafelyRetryable`
/// 与 `URLError.isTransient` 的说明。其余情形（401 / 403 / 404 / 422 / 409）
/// 重试一万次也是同一个结果，只会白白多烧几次配额并把错误延迟暴露给用户。
public struct RetryPolicy: Sendable {

    /// 最多重试几次（**不含**首次尝试）。0 表示不重试。
    public var maximumRetries: Int

    /// 首次退避时长；之后按 `multiplier` 递增。
    public var initialBackoff: TimeInterval

    /// 退避倍数。
    public var multiplier: Double

    public init(
        maximumRetries: Int = 2,
        initialBackoff: TimeInterval = 0.5,
        multiplier: Double = 2
    ) {
        self.maximumRetries = maximumRetries
        self.initialBackoff = initialBackoff
        self.multiplier = multiplier
    }

    /// 默认：最多 2 次，0.5s → 1s。
    public static let standard = RetryPolicy()

    /// 完全不重试。
    public static let none = RetryPolicy(maximumRetries: 0)

    /// 该错误是否值得自动重试。
    public func allowsRetry(_ error: GitHubError, request: HTTPRequest) -> Bool {
        guard request.method.isSafelyRetryable else { return false }

        switch error {
        case let .serverError(status):
            // ⚠️ `serverError` 是**兜底** case —— 400 / 415 / 451 之类也会落进来。
            //    必须再看 status：把"请求本身就错"的 400 重试两遍毫无意义。
            return (500...599).contains(status)

        case let .transport(urlError):
            return urlError.isTransient

        default:
            return false
        }
    }

    /// 第 `attempt` 次重试前该等多久（`attempt` 从 1 开始）。
    public func backoff(beforeAttempt attempt: Int) -> TimeInterval {
        guard attempt > 1 else { return initialBackoff }
        return initialBackoff * pow(multiplier, Double(attempt - 1))
    }
}

extension URLError {

    /// 是否属于"这次没成、下次可能成"的**瞬时**故障。
    ///
    /// ⚠️ 刻意**不含** `.notConnectedToInternet`：那不是瞬时抖动，而是明确的"没网"。
    /// 对它重试只会把 2 秒的失败拖成 6 秒，用户看到的还是转圈 ——
    /// 应该尽早失败，让 UI 立刻给出"检查网络"的提示。
    var isTransient: Bool {
        switch code {
        case .timedOut,
             .networkConnectionLost,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .resourceUnavailable,
             .badServerResponse:
            return true
        default:
            return false
        }
    }
}
