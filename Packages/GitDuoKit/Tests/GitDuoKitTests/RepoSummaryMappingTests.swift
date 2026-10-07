import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// `RepoSummary` 与它的两个映射入口（**决策 #43**，含 2026-10-06 的补充条）。
///
/// 这组断言守的是两个**很容易被"顺手重构"掉的性质**：
///
/// 1. 摘要里**凡数据源给不出的字段都是 `nil`**（不是 0 / false / 空串）——
///    搜索（REST）给不出 `forkCount` / `isPrivate` / `canWrite`，而置顶（GraphQL）都给得出。
///    编一个假值的后果是"看起来完全正常"的错值：`Fork · 0` 与"这个接口不告诉我们"
///    在界面上长得一样，含义却完全相反。
/// 2. **可写性的映射只有一处**（`RepoSummaryMapper`），且认不出的取值给 `nil`
///    而不是 `false` —— 枚举多出一档时我们"不知道"，而"不知道"与"不可写"的后果不同。
@Suite("RepoSummary · 摘要映射与字段集")
struct RepoSummaryMappingTests {

    private let mapper = RepoSummaryMapper()

    // MARK: - 置顶（GraphQL）

    @Test("置顶 → 摘要：七个字段全有，语言取自 `primaryLanguage.name`")
    func pinnedMapsEveryField() throws {
        let summary = try mapper.map(PinnedRepositoryDTO(
            nameWithOwner: "my-git/gitduo",
            description: "GitHub 客户端 · SwiftUI",
            isPrivate: true,
            starCount: 128,
            forkCount: 12,
            viewerPermission: "ADMIN",
            primaryLanguage: .init(name: "Swift")
        ))

        #expect(summary.fullName == "my-git/gitduo")
        #expect(summary.owner == "my-git")
        #expect(summary.name == "gitduo")
        #expect(summary.description == "GitHub 客户端 · SwiftUI")
        #expect(summary.language == "Swift")
        #expect(summary.starCount == 128)
        #expect(summary.forkCount == 12)
        #expect(summary.isPrivate == true)
        #expect(summary.canWrite == true)
    }

    @Test("置顶：`primaryLanguage` 为 null ⇒ 语言为 nil（空仓库不该伪造一个语言）")
    func pinnedWithoutLanguage() throws {
        let summary = try mapper.map(PinnedRepositoryDTO(
            nameWithOwner: "my-git/notes",
            isPrivate: false,
            starCount: 3,
            forkCount: 0,
            viewerPermission: "READ",
            primaryLanguage: nil
        ))

        #expect(summary.language == nil)
        // 有一个语言为 nil，不代表别的字段也要是 nil —— `forkCount == 0` 是**真值 0**，
        // 与"搜索接口给不出"必须分得开（这正是本文件上半段在守的性质）。
        #expect(summary.forkCount == 0)
        #expect(summary.canWrite == false)
    }

    // MARK: - 可写性映射（全项目仅此一处）

    @Test(
        "`viewerPermission` → 可写性：ADMIN / MAINTAIN / WRITE 为真，其余为假",
        arguments: [
            ("ADMIN", true), ("MAINTAIN", true), ("WRITE", true),
            ("TRIAGE", false), ("READ", false), ("NONE", false),
        ]
    )
    func viewerPermissionMapping(_ permission: String, _ expected: Bool) {
        #expect(RepoSummaryMapper.canWrite(fromViewerPermission: permission) == expected)
    }

    @Test(
        "⚠️ 认不出的取值 / 字段缺失 ⇒ **nil**（不知道），不是 false（不可写）",
        arguments: ["REPO_WRITE", "write_limited", "", " ", "PUSH"]
    )
    func unknownPermissionIsNilNotFalse(_ permission: String) {
        #expect(
            RepoSummaryMapper.canWrite(fromViewerPermission: permission) == nil,
            "`\(permission)` 不是已知档位，只能给 nil —— 给 false 会让用户自己的仓库长出只读页脚"
        )
        #expect(RepoSummaryMapper.canWrite(fromViewerPermission: nil) == nil)
    }

    @Test(
        "⚠️ 大小写不敏感：GitHub 发的是大写枚举，但小写也该认（否则用户自己的仓库会被判成只读）",
        arguments: [("admin", true), ("write", true), ("read", false), ("none", false)]
    )
    func permissionMatchingIsCaseInsensitive(_ permission: String, _ expected: Bool) {
        #expect(RepoSummaryMapper.canWrite(fromViewerPermission: permission) == expected)
    }

    @Test("⚠️ 路由判定的保守默认：`nil`（不知道）按**不可写**处理")
    func unknownWritabilityRoutesToReadOnly() {
        // 判错的代价在这一侧是保守的：自己的仓库看到只读页；
        // 反过来会给他人的仓库长出编辑入口，用户改完文件才吃 403。
        #expect(RepoSummary(fullName: "a/b", starCount: 0).canOpenWritableDetail == false)
        #expect(RepoSummary(fullName: "a/b", starCount: 0, canWrite: nil).canOpenWritableDetail == false)
        #expect(RepoSummary(fullName: "a/b", starCount: 0, canWrite: false).canOpenWritableDetail == false)
        #expect(RepoSummary(fullName: "a/b", starCount: 0, canWrite: true).canOpenWritableDetail == true)
    }

    // MARK: - 搜索（REST）

    @Test("⚠️ 搜索 → 摘要：`forkCount` / `isPrivate` / `canWrite` **恒为 nil**，绝不是 0 / false")
    func searchNeverFabricatesForkCountOrPrivacy() throws {
        let summary = try mapper.map(SearchRepositoryDTO(
            fullName: "my-git/gitduo",          // ← 哪怕是用户**自己的**仓库
            description: "GitHub 客户端",
            language: "Swift",
            starCount: 128,
            createdAt: Date(timeIntervalSince1970: 1_785_920_400),
            pushedAt: nil
        ))

        #expect(summary.fullName == "my-git/gitduo")
        #expect(summary.language == "Swift")
        #expect(summary.starCount == 128)
        // 这三条是重点：搜索响应里根本没有这些字段。
        // 填 0 / false 会显示成 `Fork · 0`、"公开仓库"，以及**把趋势卡也拖进"自己的仓库"**
        // （`canWrite == false` 是一个可读的值，路由会照它分流）。
        #expect(summary.forkCount == nil)
        #expect(summary.isPrivate == nil)
        #expect(summary.canWrite == nil)
    }

    @Test("搜索：`pushedAt` 为 null 不影响摘要（推送时间是榜单指标的原料，不进摘要）")
    func searchIgnoresTimestamps() throws {
        let summary = try mapper.map(SearchRepositoryDTO(
            fullName: "misoge/paneltkit",
            description: nil,
            language: nil,
            starCount: 2_341,
            createdAt: Date(timeIntervalSince1970: 1_785_920_400)
        ))

        #expect(summary.description == nil)
        #expect(summary.language == nil)
        #expect(summary.forkCount == nil)
        #expect(summary.isPrivate == nil)
        #expect(summary.canWrite == nil)
    }

    @Test("一整页搜索结果 → 摘要数组，**保留分页与不完整标记**")
    func searchPageKeepsPagingSignals() throws {
        let cursor = URL(string: "https://api.github.com/search/repositories?page=2")!
        let result = SearchRepositoriesResult(
            items: [
                SearchRepositoryDTO(fullName: "a/one", starCount: 10,
                                    createdAt: Date(timeIntervalSince1970: 0)),
                SearchRepositoryDTO(fullName: "b/two", starCount: 20,
                                    createdAt: Date(timeIntervalSince1970: 0)),
            ],
            nextCursor: cursor,
            incompleteResults: true
        )

        let mapped = try mapper.map(result)

        #expect(mapped.items.map(\.fullName) == ["a/one", "b/two"])
        #expect(mapped.nextCursor == cursor)          // 丢掉它 ⇒ 永远加载不到第二页
        #expect(mapped.incompleteResults)             // 丢掉它 ⇒ "这一页少了些条目"无从提示
    }

    // MARK: - 契约校验

    @Test(
        "`fullName` 不是 `owner/name` 形状 ⇒ 抛错（与仓库列表用同一条契约）",
        arguments: ["noSlash", "a/b/c", "/name", "owner/", ""]
    )
    func malformedFullNameThrows(_ fullName: String) throws {
        var threw = false
        do {
            _ = try mapper.map(PinnedRepositoryDTO(
                nameWithOwner: fullName, isPrivate: false, starCount: 0, forkCount: 0
            ))
        } catch let error as RepositoryMappingError {
            #expect(error == .malformedFullName(fullName))
            threw = true
        }
        #expect(threw, "`\(fullName)` 应当被拒绝")

        // 搜索路径走的是同一个拆分，必须同样拒绝。
        threw = false
        do {
            _ = try mapper.map(SearchRepositoryDTO(
                fullName: fullName, starCount: 0, createdAt: Date(timeIntervalSince1970: 0)
            ))
        } catch let error as RepositoryMappingError {
            #expect(error == .malformedFullName(fullName))
            threw = true
        }
        #expect(threw, "`\(fullName)` 在搜索路径上也应当被拒绝")
    }

    // MARK: - 结构性护栏

    @Test("⚠️ `RepoSummary` 的可写性**必须保持可空** —— 可空是「数据源给不给」，非空就成了断言")
    func summaryWritabilityMustStayOptional() {
        // 2026-10-06 修订：这条护栏原先断言"摘要里**没有任何**可写性字段"。
        // 决策 #43 的补充条允许了一个**可空**的 `canWrite` —— 因为首页置顶卡必须在点开之前
        // 就知道该进哪个详情页（铁律 #7）。护栏随之改口径：**可空可以，非空不行**。
        //
        // 非空值的危害是它长得像断言：`canWrite == false` 会被路由当成"这个仓库不可写"用，
        // 而搜索路径上我们**根本没问过**。
        let summary = RepoSummary(fullName: "a/b", starCount: 0)
        #expect(summary.canWrite == nil, "默认必须是 nil —— 编不出结论的地方就给 nil")

        // 结构性护栏：字段清单是**白名单**，任何新增字段都要来这里过一遍
        // （忘记登记的表现是"某个源给不出的字段被填了假值，而测试全绿"）。
        let fieldNames = Mirror(reflecting: summary).children.compactMap(\.label)
        #expect(fieldNames == [
            "fullName", "description", "language", "starCount",
            "forkCount", "isPrivate", "canWrite",
        ])
    }

    @Test("`owner` / `name` 的兜底：形状不符时不猜，整串当 name、owner 为空")
    func ownerAndNameAreNotGuessedWhenMalformed() {
        // Mapper 会在入口拦掉这种输入；这里守的是"有人绕过 Mapper 直接构造"时的行为 ——
        // "没有 owner 的仓库名"肉眼可辨，而猜一个 owner 会让路由指向不存在的仓库。
        let summary = RepoSummary(fullName: "noSlash", starCount: 0)

        #expect(summary.owner.isEmpty)
        #expect(summary.name == "noSlash")
        #expect(summary.id == "noSlash")
    }
}
