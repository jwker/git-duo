import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 点搜索用户行补全资料（C 方案，PRD §5.10）。
///
/// 守的是：弹层打开时走 `GET /users/{login}` 补回精简搜索行缺的字段，
/// 并映射成 `UserHit`；取数失败时错误抛给调用方（调用方降级成精简数据）。
@Suite("LoadUserProfile · 点开补全")
struct LoadUserProfileTests {

    @Test("点开时按 login 取完整资料，补回昵称 / 简介 / 人数")
    func loadsCompleteProfile() async throws {
        let dto = SearchUserDTO(
            login: "torvalds",
            name: "Linus Torvalds",
            bio: "creator of Linux",
            publicRepos: 12,
            followers: 327008
        )
        let source = ScriptedUserProfileSource(dto: dto)
        let loader = LoadUserProfile(source: source)

        let hit = try await loader.load(login: "torvalds")

        #expect(hit.login == "torvalds")
        #expect(hit.name == "Linus Torvalds")
        #expect(hit.bio == "creator of Linux")
        #expect(hit.publicRepoCount == 12)
        #expect(hit.followerCount == 327008)
        #expect(await source.requestedLogin == "torvalds")
    }

    @Test("精简对象（只有 login）也能映射：缺失字段保持 nil，不填 0")
    func mapsSparseDTO() async throws {
        let dto = SearchUserDTO(login: "someone")
        let loader = LoadUserProfile(source: ScriptedUserProfileSource(dto: dto))

        let hit = try await loader.load(login: "someone")

        #expect(hit.login == "someone")
        #expect(hit.name == nil)
        #expect(hit.bio == nil)
        #expect(hit.publicRepoCount == nil)
        #expect(hit.followerCount == nil)
    }

    @Test("取数失败 ⇒ 错误上抛，交给调用方降级（弹层保持精简数据）")
    func failurePropagates() async throws {
        let source = ScriptedUserProfileSource(error: .notFound)
        let loader = LoadUserProfile(source: source)

        await #expect(throws: GitHubError.self) {
            _ = try await loader.load(login: "ghost")
        }
    }
}

/// `UserProfileDataSource` 的脚本化替身，不碰 HTTP。
private actor ScriptedUserProfileSource: UserProfileDataSource {

    private let dto: SearchUserDTO?
    private let error: GitHubError?

    private(set) var requestedLogin: String?

    init(dto: SearchUserDTO? = nil, error: GitHubError? = nil) {
        self.dto = dto
        self.error = error
    }

    func loadUser(login: String) async throws -> SearchUserDTO {
        requestedLogin = login
        if let error { throw error }
        return dto ?? SearchUserDTO(login: login)
    }
}
