import Foundation

/// 清空 HTTP 缓存的能力 —— 登出时必须做的一件事。
///
/// 依据：TECH_SPEC §3.3（凭据绝不写入任何磁盘缓存目录）、§3.6 第 ③ 步
/// （清空"与该账号绑定的本地数据"，其中明列"接口与图片缓存"）。
///
/// ⚠️ 为什么这不是"顺手的可选优化"（真机实测，2026-10-06）：
///    `GitHubOAuthClient` 早期用 `URLSession.shared`，换令牌的响应
///    （含 `access_token` / `refresh_token`）被系统写进了
///    `Library/Caches/<bundle-id>/Cache.db`。那份副本不受 Keychain 的
///    `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 保护，
///    而**修好写入路径并不会清除已经写下的副本** —— 只有显式清理才会让它消失。
///    这正是本类型存在的唯一理由。
///
/// 定义为协议而不是直接调用 `URLCache.shared`：单例没法断言"登出时真的清了"，
/// 而这条行为必须能被测试守住 —— 否则它会在某次重构里静默消失，
/// 且**没有任何测试会变红**（这类缺口最贵）。
public protocol HTTPCachePurging: Sendable {
    /// 清空缓存。
    ///
    /// 实现必须**连同磁盘部分一起清** —— 要清掉的那个副本正躺在磁盘上。
    func purge()
}

/// 生产实现：清空 `URLCache.shared`（含其磁盘存储）。
public struct SystemHTTPCachePurger: HTTPCachePurging {

    private let cache: URLCache

    /// - Parameter cache: 默认 `URLCache.shared`（生产用）。
    ///   **测试会注入一个隔离实例** —— `URLCache.shared` 在测试进程里默认容量为 0，
    ///   `storeCachedResponse` 会静默丢弃，导致断言无一例外地空过。
    public init(cache: URLCache = .shared) {
        self.cache = cache
    }

    public func purge() {
        // ⚠️ 用 `removeAllCachedResponses()` 而不是只清内存：
        //    它是唯一能同时清掉磁盘条目的公开手段（`Cache.db` 就在磁盘上）。
        cache.removeAllCachedResponses()
    }
}
