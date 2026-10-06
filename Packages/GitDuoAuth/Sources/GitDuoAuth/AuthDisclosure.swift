import Foundation

/// 登录页必须向用户讲清的三件事 —— **单一数据源**。
///
/// 依据：PRD §4.0.1（登录页安全说明）、TECH_SPEC §3.3 / §3.5.4 / §3.6。
///
/// 为什么这三句值得单独立一个类型：它们是**产品对用户的承诺**，
/// 一旦实现变了（比如将来 secret 不再内嵌、或登出不再撤销），文案不改就是**说谎**。
/// 放在这里，改实现时至少有一个能被测试点到的位置；
/// 散在 SwiftUI 的 `Text("…")` 里，就只能等用户发现。
///
/// ⚠️ 刻意**不**在这里提 `client_secret`：
///    - 对用户而言它不可操作（既不能关也不能改），讲出来只会制造困惑；
///    - 它的性质（"软机密"、不是防线）属于**文档与代码注释**的事实（TECH_SPEC §3.1 / §3.9），
///      不是登录页的营销文案。
///    原型早期的 fnote 里有一句"客户端不持有 client secret"，D4 决策后该表述**已被推翻**
///    （我们确实持有）——这里既不复述旧话，也不把新话塞给用户。
public enum AuthDisclosure: String, CaseIterable, Sendable {

    /// 密码始终留在系统浏览器里，App 看不到
    case passwordNeverSeen

    /// 令牌存在哪、退出登录时会发生什么
    case tokenStorageAndRevocation

    /// 安装范围决定了令牌能看见多少仓库（GitHub App 独有约束，§3.5.4）
    case installScope

    public var text: String {
        switch self {
        case .passwordNeverSeen:
            "授权在系统浏览器中完成 · 密码不经过 GitDuo"
        case .tokenStorageAndRevocation:
            "令牌存于本机 Keychain，退出登录即同时撤销 GitHub 侧授权"
        case .installScope:
            "安装页请选「All repositories（全部仓库）」，否则 GitDuo 只能看到被勾选的那部分仓库"
        }
    }
}
