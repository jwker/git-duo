import Foundation
import GitHubAPI

/// `RepoSummary` 的映射 —— 两个"只读快照"数据源各一个入口（决策 #43）。
///
/// 两者的共同点：**都不返回 `permissions`**。这正是 `RepoSummary` 不含可写性字段的原因，
/// 也是这两个入口**不能**复用 `RepositoryMapper` 的原因（后者会填一个 `Permissions.none`，
/// 而那不是"没有权限"，是"没问过"）。
///
/// ⚠️ 复用 `RepositoryMapper.splitFullName` 而不是各写一遍：那条契约
/// （`owner/name` 恰好两段）在两个数据源上是同一个，写两遍就有一处会松掉。
public struct RepoSummaryMapper: Sendable {

    public init() {}

    /// 置顶仓库（GraphQL `viewer.pinnedItems`）→ 摘要。**七个字段全有**。
    public func map(_ dto: PinnedRepositoryDTO) throws -> RepoSummary {
        // 只为**校验**：`RepoSummary` 存的是整串 `fullName`，`owner` / `name` 由它自己派生
        // （那次派生也走同一个 `splitFullName`，所以这里不产生第二套拆分规则）。
        _ = try RepositoryMapper.splitFullName(dto.nameWithOwner)

        return RepoSummary(
            fullName: dto.nameWithOwner,
            description: dto.description,
            language: dto.primaryLanguage?.name,
            starCount: dto.starCount,
            forkCount: dto.forkCount,
            isPrivate: dto.isPrivate,
            canWrite: Self.canWrite(fromViewerPermission: dto.viewerPermission),
            ownerAvatarURL: dto.owner.avatarUrl
        )
    }

    /// 探索榜结果（REST `GET /search/repositories` 的 `items`）→ 摘要。
    ///
    /// ⚠️ **`forkCount` / `isPrivate` / `canWrite` 一律为 `nil`** —— 不是"忘了填"，
    /// 而是搜索响应里根本没有这三个字段（§9.10.1）。卡片据此不渲染 Fork 角标、
    /// 私有标记，也不做"自己的 / 他人的"分流。这三种"查不到"与"值就是 0 / false"
    /// 在界面上的表现**必须不同**。
    public func map(_ dto: SearchRepositoryDTO) throws -> RepoSummary {
        _ = try RepositoryMapper.splitFullName(dto.fullName)

        return RepoSummary(
            fullName: dto.fullName,
            description: dto.description,
            language: dto.language,
            starCount: dto.starCount,
            forkCount: nil,
            isPrivate: nil,
            canWrite: nil,
            ownerAvatarURL: dto.owner.avatarURL
        )
    }

    /// 一整页搜索结果 → 摘要数组。
    ///
    /// **保留 `nextCursor` / `incompleteResults`**：分页与"这一页少了些条目"的信号
    /// 不能在这一层丢掉（调用方要拿它们续页与提示）。
    public func map(_ result: SearchRepositoriesResult) throws -> (items: [RepoSummary], nextCursor: URL?, incompleteResults: Bool) {
        (
            items: try result.items.map { try map($0) },
            nextCursor: result.nextCursor,
            incompleteResults: result.incompleteResults
        )
    }

    // MARK: - 可写性（全项目仅此一处）

    /// GraphQL `viewerPermission` ⇒ 可写性。
    ///
    /// ## 为什么这里允许出现"第二种表达"
    ///
    /// TECH_SPEC §8.1 把 `Repository.permissions.push` 定为可写性的唯一来源。
    /// 但置顶走的是 GraphQL，响应里**没有** `permissions` 对象，只有等价的
    /// `viewerPermission` 枚举。要判定就得翻译 —— 而翻译的规则**只许写在这一个函数里**。
    /// 散到第二个地方就等于有了两条规则，而"某个入口能编辑、另一个入口不能"正是两条规则
    /// 分歧的样子。
    ///
    /// ## 三条映射纪律
    ///
    /// 1. `ADMIN` / `MAINTAIN` / `WRITE` ⇒ `true`；`TRIAGE` / `READ` / `NONE` ⇒ `false`。
    /// 2. **认不出的取值 ⇒ `nil`**，不是 `false`。枚举多出一档时我们**不知道**它意味着什么，
    ///    而"不知道"与"不可写"的后果完全不同（后者会让用户自己的仓库长出只读页脚）。
    /// 3. **字段缺失 ⇒ `nil`**，理由同上。
    ///
    /// - Note: `nil` 在路由上按"不可写"处理，但那是**另一件事**、写在另一个地方
    ///   （`RepoSummary.canOpenWritableDetail`）—— 把"不知道"与"保守默认"混成一个值，
    ///   将来想改默认值时就再也找不回来了。
    static func canWrite(fromViewerPermission permission: String?) -> Bool? {
        guard let permission else { return nil }

        switch permission.uppercased() {
        case "ADMIN", "MAINTAIN", "WRITE": return true
        case "TRIAGE", "READ", "NONE": return false
        default: return nil
        }
    }
}
