import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 四个分段的文案、数据源与过滤规则（PRD §4.3 / TECH_SPEC §9.3）。
///
/// 文案是**契约** —— 逐字对齐原型 `scripts/05-repo.js` 的 `['全部','公开','私有','Starred']`，
/// 以及 2026-10-06 拍板的逐段空态。改动这两处等于改需求，必须同步 PRD §4.3。
@Suite("RepoListSegment · 文案 / 数据源 / 过滤")
struct RepoListSegmentTests {

    private let writable = Repository(
        owner: "my-git", name: "gitduo", isPrivate: false,
        starCount: 128, forkCount: 12, permissions: Permissions(push: true)
    )
    private let privateOnly = Repository(
        owner: "my-git", name: "notes", isPrivate: true,
        starCount: 3, forkCount: 0, permissions: Permissions(push: true)
    )

    // MARK: - 文案

    @Test("四个分段的文案与顺序**逐字对齐原型**")
    func titlesMatchPrototype() {
        #expect(
            RepoListSegment.allCases.map(\.title) == ["全部", "公开", "私有", "Starred"]
        )
    }

    @Test("每个分段都有独立的空态文案 —— 不允许重复（说错话的空态比没有空态更糟）")
    func emptyCopyIsPerSegmentAndDistinct() {
        let copies = RepoListSegment.allCases.map(\.emptyTitle)

        #expect(copies == ["还没有仓库", "还没有公开仓库", "还没有私有仓库", "还没有 Star 过的仓库"])
        #expect(Set(copies).count == copies.count, "空态文案重复意味着某个段在说别人的话")
        #expect(copies.allSatisfy { !$0.isEmpty })
        // Starred 段尤其不能共用「还没有仓库」：那会让人以为**自己的仓库没了**。
        #expect(!RepoListSegment.starred.emptyTitle.contains("自己的"))
    }

    @Test("`id` 唯一 —— 它进 `ForEach`，重复会让分段控件渲染错乱")
    func idsAreUnique() {
        let ids = RepoListSegment.allCases.map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    // MARK: - 数据源

    @Test("前三段共用 `user/repos`，Starred 段独占 `user/starred`（§9.3）")
    func sourcesAreSplit() {
        #expect(RepoListSegment.all.source == .repos)
        #expect(RepoListSegment.publicOnly.source == .repos)
        #expect(RepoListSegment.privateOnly.source == .repos)
        #expect(RepoListSegment.starred.source == .starred)
    }

    // MARK: - 过滤

    @Test("全部段：不做过滤，私有与公开都留")
    func allKeepsEverything() {
        #expect(RepoListSegment.all.matches(writable))
        #expect(RepoListSegment.all.matches(privateOnly))
    }

    @Test("公开段留非私有、私有段留私有 —— 两者互斥且合起来等于全部")
    func publicAndPrivatePartition() {
        #expect(RepoListSegment.publicOnly.matches(writable))
        #expect(!RepoListSegment.publicOnly.matches(privateOnly))
        #expect(!RepoListSegment.privateOnly.matches(writable))
        #expect(RepoListSegment.privateOnly.matches(privateOnly))
    }

    @Test("Starred 段不做本地过滤 —— 它的数据源本身就是「我 Star 过的」")
    func starredDoesNotFilterLocally() {
        #expect(RepoListSegment.starred.matches(writable))
        #expect(RepoListSegment.starred.matches(privateOnly))
    }

    @Test("可写性**不参与**分段过滤：只读的公开仓库在「公开」段里照样出现")
    func filterIgnoresWritability() {
        let readOnlyPublic = Repository(
            owner: "rust-lang", name: "rust", isPrivate: false,
            starCount: 98_000, forkCount: 12_600, permissions: .none
        )

        #expect(RepoListSegment.publicOnly.matches(readOnlyPublic))
        #expect(RepoListSegment.all.matches(readOnlyPublic))
    }
}
