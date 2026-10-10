import Foundation
import GitHubAPI

/// 用户公开资料的取数接缝 —— 搜索弹层补全用（PRD §5.10）。
///
/// 与 `SearchEndpoints.searchUsers` 的区别：那个走 `/search/users`（精简对象、搜索桶），
/// 这个走 `/users/{login}`（完整公开资料、主桶）。点用户行时才补一次。
public protocol UserProfileDataSource: Sendable {

    /// `GET /users/{login}` —— 补回搜索结果缺的昵称 / 简介 / 公开仓库数 / 关注者数。
    func loadUser(login: String) async throws -> SearchUserDTO
}

/// 让真实端点满足上面的接缝（协议由本包声明，非追溯适配）。
extension GitHubPublicUserEndpoint: UserProfileDataSource {}
