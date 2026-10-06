import CryptoKit
import Foundation

/// SHA256 → 小写十六进制。
///
/// 只用于给缓存条目取文件名（见 `CacheKey.fileName`）。CryptoKit 是**系统框架**，
/// 不是第三方依赖（决策 #12 不受影响）。
enum SHA256Digest {

    static func hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
