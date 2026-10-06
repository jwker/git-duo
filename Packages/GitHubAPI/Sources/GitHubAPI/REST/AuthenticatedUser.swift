import Foundation

/// 已认证用户的**最小**信息。
///
/// 依据：TECH_SPEC §3.1 步骤 8（换到令牌后立即用 `GET /user` 校验有效性）。
///
/// ⚠️ 这是刻意收窄的子集，**不是**完整的用户模型：切片 1 只需要 `login`
///    （它是本地数据的命名空间键，§7.2，为将来多账号预留）。
///    完整的个人页模型（头像、简介、统计、贡献热力图）由切片 4 扩展——
///    届时是扩展本类型还是另立 DTO，以那时的事实为准；**不要**现在就把字段猜全。
public struct AuthenticatedUser: Sendable, Equatable, Decodable {

    public let login: String

    public init(login: String) {
        self.login = login
    }
}
