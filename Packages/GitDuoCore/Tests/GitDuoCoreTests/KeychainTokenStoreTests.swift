import Foundation
import Testing

@testable import GitDuoCore

/// `KeychainTokenStore` 的**真实** Keychain 往返测试（不是 mock）。
///
/// 三个环境约定：
/// - 每个测试用**独立的随机 Service**，既不污染真实凭据，也避免测试之间互扰；
/// - `.serialized` —— Keychain 是进程外共享资源，并行会撞出难以复现的竞争；
/// - 必须**非沙箱**运行（`make test` 已如此约定），沙箱下 `SecItemAdd` 会被拒。
///
/// ⚠️ 写法约定：断言里**不要**写 `#expect(try store.load() == …)` ——
///    `#expect` 宏展开后 `try` 会落在非 throwing 上下文里（闭包内尤其如此）。
///    先 `let x = try store.load()` 再 `#expect(x == …)`。
@Suite("KeychainTokenStore · 真实钥匙串往返", .serialized)
struct KeychainTokenStoreTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeToken(login: String = "jiangjiang") -> StoredToken {
        StoredToken(
            accessToken: "ghu_0123456789abcdef",
            refreshToken: "ghr_0123456789abcdef",
            accessTokenExpiry: now.addingTimeInterval(8 * 3600),
            refreshTokenExpiry: now.addingTimeInterval(180 * 24 * 3600),
            login: login
        )
    }

    /// 建一个用完即清的独立 store，并把 Service 一并交给用例（供直接查询 Keychain 用）。
    private func withStore(_ body: (KeychainTokenStore, String) throws -> Void) throws {
        let service = "com.gitduo.tests.\(UUID().uuidString)"
        let store = KeychainTokenStore(service: service)
        defer { try? store.clear() }
        try body(store, service)
    }

    /// 绕过 store 直接问 Keychain 要条目属性 —— 用于验证"确实只写了一份、且属性正确"。
    private func keychainAttributes(service: String) -> [String: Any]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: KeychainTokenStore.defaultAccount,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? [String: Any]
    }

    // MARK: - 基本往返

    @Test("无凭据时 load 返回 nil —— 「没有凭据」是正常状态，不是错误")
    func emptyLoadReturnsNil() throws {
        try withStore { store, _ in
            let loaded = try store.load()
            #expect(loaded == nil)
        }
    }

    @Test("save 后可原样读回（字段逐一相等）")
    func roundTrip() throws {
        try withStore { store, _ in
            let token = makeToken()
            try store.save(token)
            let loaded = try store.load()
            #expect(loaded == token)
        }
    }

    @Test("重复 save 是**覆盖**，不会留下第二份条目")
    func saveOverwritesInsteadOfDuplicating() throws {
        try withStore { store, _ in
            try store.save(makeToken(login: "first"))
            try store.save(makeToken(login: "second"))

            let loaded = try store.load()
            #expect(loaded?.login == "second")

            // 若实现是 add 出两份，clear 只删得掉一份、load 仍读得到旧的 → 守住该回归
            try store.clear()
            let afterClear = try store.load()
            #expect(afterClear == nil)
        }
    }

    @Test("clear 幂等：从未存过也能安全调用；清除后读到 nil")
    func clearIsIdempotent() throws {
        try withStore { store, _ in
            try store.clear()                       // 空态清除不应抛错
            let a = try store.load()
            #expect(a == nil)

            try store.save(makeToken())
            try store.clear()
            let b = try store.load()
            #expect(b == nil)

            try store.clear()                       // 重复清除仍不应抛错
            let c = try store.load()
            #expect(c == nil)
        }
    }

    // MARK: - 内容边界

    @Test("含中文与 emoji 的登录名往返不乱码（JSON 编码，非字符串拼接）")
    func handlesNonASCIILogin() throws {
        try withStore { store, _ in
            let token = makeToken(login: "江东父老🚀")
            try store.save(token)
            let loaded = try store.load()
            #expect(loaded == token)
        }
    }

    @Test("长令牌（4096 字符）不被截断")
    func handlesLongTokens() throws {
        try withStore { store, _ in
            let long = String(repeating: "ghu_", count: 1024)
            let token = StoredToken(
                accessToken: long,
                refreshToken: long,
                accessTokenExpiry: now,
                refreshTokenExpiry: now,
                login: "jiangjiang"
            )
            try store.save(token)
            let loaded = try store.load()
            #expect(loaded?.accessToken.count == long.count)
        }
    }

    @Test("过期时刻保留亚秒精度")
    func preservesDatePrecision() throws {
        try withStore { store, _ in
            let expiry = Date(timeIntervalSince1970: 1_800_000_000.123_456)
            let token = StoredToken(
                accessToken: "a",
                refreshToken: "r",
                accessTokenExpiry: expiry,
                refreshTokenExpiry: expiry,
                login: "jiangjiang"
            )
            try store.save(token)
            let loaded = try store.load()
            #expect(loaded?.accessTokenExpiry == expiry)
        }
    }

    // MARK: - 存储属性

    @Test("条目可被 (service, account) 精确命中，且只存在一份")
    func entryIsAddressableAndUnique() throws {
        try withStore { store, service in
            #expect(keychainAttributes(service: service) == nil)   // 存之前查不到

            try store.save(makeToken())

            let attributes = keychainAttributes(service: service)
            #expect(attributes != nil)
            #expect(attributes?[kSecAttrAccount as String] as? String == KeychainTokenStore.defaultAccount)

            // 只写了一份：按 class 枚举该 service 下的全部条目应为 1
            let countQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnAttributes as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll
            ]
            var items: CFTypeRef?
            let status = SecItemCopyMatching(countQuery as CFDictionary, &items)
            #expect(status == errSecSuccess)
            #expect((items as? [[String: Any]])?.count == 1)
        }
    }

    @Test("不同 Service 之间互不可见（凭据不串味）")
    func servicesAreIsolated() throws {
        try withStore { storeA, _ in
            try withStore { storeB, _ in
                try storeA.save(makeToken(login: "a"))
                let bEmpty = try storeB.load()
                #expect(bEmpty == nil)

                try storeB.save(makeToken(login: "b"))
                let aLoaded = try storeA.load()
                let bLoaded = try storeB.load()
                #expect(aLoaded?.login == "a")
                #expect(bLoaded?.login == "b")
            }
        }
    }

    // ⚠️ 以下断言只在 iOS 生效（生产平台）。macOS 宿主机上 `save` 不设置 accessibility 属性，
    //    故该分支不参与编译；它由切片 1.8 的真机手测兜底。
    //    （上面的查询逻辑两端都会编译并执行，不存在"从未编译过的代码"。）
    #if os(iOS)
    @Test("iOS：条目为 AfterFirstUnlockThisDeviceOnly —— 不进 iCloud、不跨设备迁移（§3.3）")
    func accessibilityIsThisDeviceOnly() throws {
        try withStore { store, service in
            try store.save(makeToken())
            let attributes = keychainAttributes(service: service)
            #expect(attributes?[kSecAttrAccessible as String] as? String
                    == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
        }
    }
    #endif
}
