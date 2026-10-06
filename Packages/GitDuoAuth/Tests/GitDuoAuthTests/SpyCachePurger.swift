import Foundation
import GitDuoCore

/// 记录 `purge()` 调用次数的替身。
///
/// 用 `final class` + 锁（而非 struct）：断言发生在 `await signOut()` **之后**，
/// 需要调用方与被测对象看到的是同一个可变量。
final class SpyCachePurger: HTTPCachePurging, @unchecked Sendable {

    private let lock = NSLock()
    private var count = 0

    /// 被调用过几次。**断言用它判断"登出是否真的清了缓存"**。
    var purgeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func purge() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}
