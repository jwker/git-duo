import CryptoKit
import Foundation

/// RFC 7636（PKCE · S256）实现 —— 授权流程的第一步。
///
/// 依据：TECH_SPEC §3.1（步骤 1–5）、§3.2、§3.9。
///
/// ⚠️ 三条不可退让的约束：
/// 1. `code_verifier` **只存内存、绝不随回调传输、绝不落盘**——它是场景 A（scheme 被抢注、
///    授权码被第三方收到）唯一有效的防线（§3.9）。
/// 2. `state` **一次性**：每次授权重新生成，校验通过即作废，不一致必须中止并丢弃 `code`。
/// 3. **不启用 device flow**（官方明确反对，§3.1）。
public enum PKCE {

    /// 生成 `code_verifier`：43–128 个 unreserved 字符（RFC 7636 §4.1）。
    public static func makeCodeVerifier(length: Int = 64) -> String {
        precondition((43...128).contains(length), "code_verifier 长度必须落在 43...128（RFC 7636 §4.1）")
        return randomURLSafeString(length: length)
    }

    /// `code_challenge = BASE64URL-ENCODE(SHA256(ASCII(code_verifier)))`，即 `code_challenge_method=S256`。
    public static func codeChallenge(for verifier: String) -> String {
        base64URLEncoded(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// 生成一次性 `state`（防 CSRF）。
    public static func makeState() -> String {
        randomURLSafeString(length: 32)
    }

    /// 校验回调带回的 `state` 是否与本地暂存值完全一致。
    /// 返回 `false` ⇒ 必须中止流程并丢弃本次 `code`。
    public static func isValidCallbackState(_ received: String, expected: String?) -> Bool {
        guard let expected, !expected.isEmpty, !received.isEmpty else { return false }
        let a = Array(received.utf8)
        let b = Array(expected.utf8)
        guard a.count == b.count else { return false }
        // 逐字节异或累积，不提前返回：避免通过耗时差异推断匹配前缀
        var diff: UInt8 = 0
        for i in a.indices { diff |= a[i] ^ b[i] }
        return diff == 0
    }

    /// BASE64URL（RFC 4648 §5）：`+` → `-`、`/` → `_`、去掉 `=` 填充。
    public static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Private

    /// RFC 7636 §4.1 的 unreserved 字符集（66 个）
    private static let unreserved = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// 用系统 CSPRNG + 拒绝采样生成随机串（消除取模偏差）。
    private static func randomURLSafeString(length: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        let limit = UInt8(256 - (256 % unreserved.count))
        var out = ""
        out.reserveCapacity(length)
        while out.count < length {
            let byte = UInt8.random(in: .min ... .max, using: &generator)
            guard byte < limit else { continue }   // 拒绝采样
            out.append(unreserved[Int(byte) % unreserved.count])
        }
        return out
    }
}
