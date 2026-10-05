import Foundation

/// 本地保存的一整套凭据。
///
/// 依据：TECH_SPEC §3.2、§3.3。
/// ⚠️ 序列化 / 日志红线：`refreshToken` 与 `accessToken` **绝不写入**日志、崩溃上报、剪贴板、
/// UserDefaults 明文、任何磁盘缓存目录。生产实现只能落 Keychain。
public struct StoredToken: Equatable, Sendable, Codable {

    public var accessToken: String
    public var refreshToken: String
    /// `access_token`（`ghu_`）过期时刻 —— 固定 8 小时
    public var accessTokenExpiry: Date
    /// `refresh_token`（`ghr_`）过期时刻 —— 6 个月
    public var refreshTokenExpiry: Date
    /// 账号登录名。本地数据按 `login` 分命名空间（§7.2，为将来多账号预留）
    public var login: String

    public init(
        accessToken: String,
        refreshToken: String,
        accessTokenExpiry: Date,
        refreshTokenExpiry: Date,
        login: String
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiry = accessTokenExpiry
        self.refreshTokenExpiry = refreshTokenExpiry
        self.login = login
    }

    /// 是否应在**过期前 5 分钟**触发后台预刷新（§3.2 刷新策略第 1 条）。
    public func needsRefresh(at now: Date, lead: TimeInterval = 5 * 60) -> Bool {
        now.addingTimeInterval(lead) >= accessTokenExpiry
    }

    /// refresh_token 是否已失效（失效 ⇒ 必须清除凭据、回登录页，§3.2 第 3 条）。
    public func isRefreshTokenExpired(at now: Date) -> Bool {
        now >= refreshTokenExpiry
    }
}

/// 凭据存储抽象。生产实现走 Keychain（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，§3.3）。
public protocol TokenStore: Sendable {
    func save(_ token: StoredToken) throws
    func load() throws -> StoredToken?
    func clear() throws
}

public enum TokenStoreError: Error, Equatable {
    case encodingFailed
    case decodingFailed
    case unexpectedStatus(OSStatus)
}

/// 内存实现：单测 / SwiftUI 预览专用。
/// ⚠️ **不得用于生产**——无持久化、无加密。
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {

    private let lock = NSLock()
    private var stored: StoredToken?

    public init(seed: StoredToken? = nil) {
        self.stored = seed
    }

    public func save(_ token: StoredToken) throws {
        lock.lock()
        defer { lock.unlock() }
        stored = token
    }

    public func load() throws -> StoredToken? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        stored = nil
    }
}
