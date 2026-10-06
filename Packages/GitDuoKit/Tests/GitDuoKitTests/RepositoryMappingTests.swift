import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 映射与可写性判定 —— 本切片最要紧的一组断言（PRD §3.1 / TECH_SPEC §6.2、§8.1）。
@Suite("Repository · 映射与可写性判定")
struct RepositoryMappingTests {

    private let mapper = RepositoryMapper()

    // MARK: - 可写性判定

    @Test("`permissions.push == true` ⇒ 可写（且进入可写工作台）")
    func pushMeansWritable() throws {
        let repo = try mapper.map(Fixtures.dto("my-git/gitduo", push: true))

        #expect(repo.canWrite)
        #expect(repo.entry == .writable)
    }

    @Test("`permissions.push == false` ⇒ 只读（进入只读阅览室）")
    func noPushMeansReadOnly() throws {
        let repo = try mapper.map(Fixtures.dto("vercel/next.js", push: false))

        #expect(!repo.canWrite)
        #expect(repo.entry == .readOnly)
    }

    @Test("⚠️ `permissions` **整个缺失** ⇒ 只读 —— 绝不能默认成可写")
    func missingPermissionsIsReadOnly() throws {
        let repo = try mapper.map(Fixtures.dto("someone/repo"))

        #expect(repo.permissions == .none)
        #expect(!repo.canWrite)
        #expect(repo.entry == .readOnly)
        // 为什么这条最要紧：`permissions` 只在已认证请求里返回。
        // 把它的缺席读成"没说不行就是行"，用户会在只读仓库上看到一个编辑入口，
        // 改完文件、提交时才吃 403 —— 而那时他已经把改动写完了。
    }

    @Test("`admin == true` 但缺 `push` ⇒ **仍然只读**（规格以 push 为唯一判据，不由 admin 推断）")
    func adminWithoutPushStaysReadOnly() throws {
        let dto = RepositoryDTO(
            fullName: "org/repo",
            isPrivate: false,
            starCount: 1,
            forkCount: 0,
            permissions: RepositoryPermissionsDTO(admin: true, maintain: true)
        )

        let repo = try mapper.map(dto)

        #expect(!repo.canWrite)
        // 两条规则（push 判、admin 推断）迟早会分歧；判错的这一侧是**保守**的：
        // 少显示一个可写入口，用户看到的仍是只读页，不会撞上 403。
    }

    @Test("私有与可写是两个独立维度：私有只读 / 公开可写都能出现")
    func privacyAndWritabilityAreIndependent() throws {
        let privateReadOnly = try mapper.map(Fixtures.dto("me/secret", isPrivate: true, push: false))
        let publicWritable = try mapper.map(Fixtures.dto("org/shared", isPrivate: false, push: true))

        #expect(privateReadOnly.isPrivate && !privateReadOnly.canWrite)
        #expect(!publicWritable.isPrivate && publicWritable.canWrite)
    }

    // MARK: - fullName 拆分

    @Test("`full_name` 拆成 owner / name，并能还原成全名")
    func splitsFullName() throws {
        let repo = try mapper.map(Fixtures.dto("rust-lang/rust"))

        #expect(repo.owner == "rust-lang")
        #expect(repo.name == "rust")
        #expect(repo.fullName == "rust-lang/rust")
        #expect(repo.id == "rust-lang/rust", "id 用全名，分页追加时不会变 —— 自增序号会让列表整片重绘")
    }

    @Test(
        "畸形 `full_name` ⇒ 响亮失败，不猜一个 owner 出来",
        arguments: ["no-slash", "/leading", "trailing/", "a/b/c", ""]
    )
    func rejectsMalformedFullName(_ malformed: String) {
        #expect(throws: RepositoryMappingError.malformedFullName(malformed)) {
            try mapper.map(Fixtures.dto(malformed))
        }
    }

    // MARK: - 其余字段

    @Test("可空字段（description / language）原样搬过来，不补默认值")
    func keepsNullables() throws {
        let repo = try mapper.map(
            Fixtures.dto("me/empty", description: nil, language: nil, stars: 0, forks: 0)
        )

        #expect(repo.description == nil)
        #expect(repo.language == nil)
        #expect(repo.starCount == 0)
        #expect(repo.forkCount == 0)
    }

    @Test("整页映射：条目顺序与 nextCursor 都不丢")
    func mapsWholePage() throws {
        let page = Fixtures.page(
            [Fixtures.dto("a/one"), Fixtures.dto("b/two")],
            next: "https://api.github.com/user/repos?page=2"
        )

        let mapped = try mapper.map(page)

        #expect(mapped.items.map(\.fullName) == ["a/one", "b/two"])
        #expect(mapped.nextCursor?.absoluteString == "https://api.github.com/user/repos?page=2")
    }
}
