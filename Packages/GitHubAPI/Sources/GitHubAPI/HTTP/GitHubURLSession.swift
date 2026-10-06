import Foundation

/// 本包所有出网请求的会话工厂 —— **一条铁律：不落盘**。
///
/// 依据：TECH_SPEC §3.3「凭据**绝不写入**日志、崩溃上报、剪贴板、UserDefaults 明文、
/// **任何磁盘缓存目录**」。
///
/// ⚠️ **为什么这件事必须自己管（真机实测，2026-10-06）**：
/// `URLCache` 落盘的**不只是响应体，还有序列化后的请求对象**。
/// 设备上 `Library/Caches/com.gitduo.app/Cache.db` 的 `cfurl_cache_blob_data.proto_props` 里
/// 明文躺着 `Authorization` + `Bearer` + `ghu_…`（访问令牌），以及 GitHub 的 `_octo` Cookie。
/// —— 响应体本身是干净的（`/user` 只返回公开资料），**泄露源是请求头**。
///
/// ⚠️ **只设 `URLRequest.cachePolicy` 挡不住**：那个字段的意思是"取用时是否走缓存"，
/// 不是"存不存"。要"不存"，只能把 `urlCache` 从**会话**上摘掉。
///
/// ⚠️ 切片 2 做 ETag 三层缓存时**不要回头启用系统 `URLCache`** —— 那会把请求头又写回磁盘。
/// 正确做法是在本会话之上自建一层，只存 `URL / ETag / 响应体 / 过期时间`。
public enum GitHubURLSession {

    /// 进程内共用一个实例 —— `URLSession` 本就不该逐请求新建（连接池与配置都靠它复用）。
    public static let shared: URLSession = noCache()

    /// 无缓存会话：令牌响应、以及每个带 `Authorization` 的请求对象，都无处落盘。
    ///
    /// 同时**不要 Cookie 罐**：GitHub App 用令牌走 `Authorization` 头，客户端不需要 Cookie；
    /// 留着它只会让 GitHub 把 `_octo` 之类写进磁盘（实测见过）。
    public static func noCache() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        // 结构性杜绝：会话上没有 URLCache ⇒ 请求对象与响应体都无处落盘
        configuration.urlCache = nil
        // 第二道（取用侧），同时让"本会话不缓存"在配置里显式可读
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }
}
