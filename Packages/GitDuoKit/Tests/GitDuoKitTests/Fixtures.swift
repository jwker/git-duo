import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 造 DTO / 页 的小工具 —— 本包多个套件共用。
enum Fixtures {

    static func dto(
        _ fullName: String,
        isPrivate: Bool = false,
        description: String? = nil,
        language: String? = "Swift",
        stars: Int = 0,
        forks: Int = 0,
        push: Bool? = nil
    ) -> RepositoryDTO {
        RepositoryDTO(
            fullName: fullName,
            isPrivate: isPrivate,
            description: description,
            language: language,
            starCount: stars,
            forkCount: forks,
            permissions: push.map { RepositoryPermissionsDTO(push: $0, pull: true) }
        )
    }

    static func page(
        _ dtos: [RepositoryDTO],
        next: String? = nil
    ) -> Page<RepositoryDTO> {
        Page(
            items: dtos,
            nextCursor: next.flatMap(URL.init(string:)),
            headers: HTTPHeaders([:])
        )
    }
}

/// 一页仓库的脚本化替身 —— 领域层测试用它，**不碰 HTTP**。
///
/// 理由见 `RepositoryDataSource` 的文档：领域层要断言的是业务规则，
/// 而不是"请求头带没带版本号"（那已由 `GitHubAPITests` 用真实桩件覆盖）。
actor ScriptedRepositorySource: RepositoryDataSource {

    /// 依次返回的 `user/repos` 页；用完后重复最后一页。
    private var reposPages: [Page<RepositoryDTO>]
    private var starredPages: [Page<RepositoryDTO>]

    /// 记录每次请求用到的游标 —— 用来断言"续页真的把上一页的 nextCursor 传下去了"。
    private(set) var reposCursors: [URL?] = []
    private(set) var starredCursors: [URL?] = []

    /// 让 `listRepos` 抛出的错误（测失败路径）。
    private var failure: GitHubError?

    init(repos: [Page<RepositoryDTO>] = [], starred: [Page<RepositoryDTO>] = []) {
        self.reposPages = repos
        self.starredPages = starred
    }

    func failWith(_ error: GitHubError) {
        self.failure = error
    }

    func listRepos(cursor: URL?) async throws -> Page<RepositoryDTO> {
        reposCursors.append(cursor)
        if let failure { throw failure }
        return reposPages.count > 1 ? reposPages.removeFirst() : (reposPages.first ?? Fixtures.page([]))
    }

    func listStarred(cursor: URL?) async throws -> Page<RepositoryDTO> {
        starredCursors.append(cursor)
        if let failure { throw failure }
        return starredPages.count > 1 ? starredPages.removeFirst() : (starredPages.first ?? Fixtures.page([]))
    }
}
