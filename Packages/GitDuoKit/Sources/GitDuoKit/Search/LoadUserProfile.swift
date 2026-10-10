import Foundation
import GitHubAPI

/// 点搜索用户结果行时补全资料（C 方案）。
///
/// 列表行只显示 `/search/users` 的精简数据；用户点开弹层时，本用例再走一次
/// `GET /users/{login}`，拿到完整资料映射成 `UserHit` 后渲染。
///
/// 映射复用 `SearchRowMapper.user` —— 搜索行与弹层用的是同一个"用户资料"形状，
/// 不在此重抄一遍。
public struct LoadUserProfile: Sendable {

    private let source: any UserProfileDataSource

    public init(source: any UserProfileDataSource) {
        self.source = source
    }

    /// 取完整公开资料并映射成 `UserHit`。
    ///
    /// - Throws: 取数失败（如 `404` 用户不存在）。调用方据此降级成精简数据或提示。
    public func load(login: String) async throws -> UserHit {
        let dto = try await source.loadUser(login: login)
        return SearchRowMapper.user(dto)
    }
}
