import Foundation
import Security

/// Keychain 凭据存储 —— `TokenStore` 的**生产实现**（替换骨架期的 `InMemoryTokenStore`）。
///
/// 依据：TECH_SPEC §3.3（凭据存储）、§7.1（存储选型）、§7.2（按 `login` 分命名空间）。
///
/// 三条不可退让的约束：
/// 1. `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` —— **不进 iCloud 钥匙串、不跨设备迁移**。
/// 2. 凭据**绝不**出现在日志 / 崩溃上报 / 剪贴板 / UserDefaults 明文 / 任何磁盘缓存目录（§3.3、铁律 8）。
/// 3. 序列化只走 `StoredToken` 的 `Codable` 实现，不另造一套字段映射（避免两份真相）。
public final class KeychainTokenStore: TokenStore, @unchecked Sendable {

    /// 默认 Service。⚠️ 改动等于**丢弃用户已有凭据**（旧条目不会再被读到），不要随意变更。
    public static let defaultService = "com.gitduo.app.auth"

    /// 默认 Account（同一 Service 下只存一套凭据；多账号时代再按 `login` 分条）
    public static let defaultAccount = "credentials"

    private let service: String
    private let account: String

    /// `SecItem*` 本身是线程安全的，但「先 update 再 add」这条复合路径不是 → 进程内串行化。
    private let lock = NSLock()

    /// - Parameters:
    ///   - service: Keychain Service（测试用独立值，避免污染真实凭据）
    ///   - account: Keychain Account
    public init(
        service: String = KeychainTokenStore.defaultService,
        account: String = KeychainTokenStore.defaultAccount
    ) {
        self.service = service
        self.account = account
    }

    // MARK: - TokenStore

    public func save(_ token: StoredToken) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(token)
        } catch {
            // 不把底层错误往外抛：它的 description 可能包含编码内容（凭据）
            throw TokenStoreError.encodingFailed
        }

        lock.lock()
        defer { lock.unlock() }

        // 先 update、失败再 add：避免 delete + add 之间出现「凭据不存在」的窗口期
        // （该窗口内若进程被杀，用户会凭空被登出）。
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var createQuery = baseQuery
            createQuery[kSecValueData as String] = data
            #if os(iOS)
            // §3.3：仅本机、重开机首次解锁后可用；不进 iCloud 备份、不跨设备迁移。
            // macOS 上该属性语义不同且部分取值会 errSecParam —— macOS 只是宿主机跑单测用，
            // 生产在 iOS，故仅在 iOS 设置。
            createQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            #endif
            let addStatus = SecItemAdd(createQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw TokenStoreError.unexpectedStatus(addStatus)
            }
        default:
            throw TokenStoreError.unexpectedStatus(updateStatus)
        }
    }

    public func load() throws -> StoredToken? {
        lock.lock()
        defer { lock.unlock() }

        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw TokenStoreError.decodingFailed }
            do {
                return try JSONDecoder().decode(StoredToken.self, from: data)
            } catch {
                throw TokenStoreError.decodingFailed
            }
        case errSecItemNotFound:
            // 「没有凭据」是正常状态（首启 / 已登出），**不是**错误。
            return nil
        default:
            throw TokenStoreError.unexpectedStatus(status)
        }
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }

        let status = SecItemDelete(baseQuery as CFDictionary)
        // 幂等：本就不存在也算成功（登出要能被重复调用而不报错）。
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.unexpectedStatus(status)
        }
    }

    // MARK: - Private

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
