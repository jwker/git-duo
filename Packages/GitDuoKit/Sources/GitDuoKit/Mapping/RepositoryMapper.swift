import Foundation
import GitHubAPI

/// `RepositoryDTO` → `Repository` 的映射。
///
/// 依据：TECH_SPEC §6.1（三层模型：DTO → 领域模型 → 视图状态）。
///
/// 为什么要有这一层：DTO 是**服务端的形状**，领域模型是**产品的语义**。
/// 直接让界面吃 DTO，等于把"GitHub 的 JSON 长什么样"变成全 App 的隐式契约 ——
/// 那样一次 API 改字段，改动会散落到每一个用到它的页面。
/// 映射集中在这里，改字段时只需要改一处，且**这一处有测试**。
public struct RepositoryMapper: Sendable {

    public init() {}

    /// - Throws: `RepositoryMappingError.malformedFullName` —— `full_name` 里没有 `/`。
    public func map(_ dto: RepositoryDTO) throws -> Repository {
        let (owner, name) = try Self.splitFullName(dto.fullName)

        return Repository(
            owner: owner,
            name: name,
            description: dto.description,
            isPrivate: dto.isPrivate,
            language: dto.language,
            starCount: dto.starCount,
            forkCount: dto.forkCount,
            permissions: Permissions(dto.permissions)
        )
    }

    /// 映射一整页，保留 `nextCursor`（续页信息不能在这一层丢掉）。
    public func map(_ page: Page<RepositoryDTO>) throws -> Page<Repository> {
        try page.map { try map($0) }
    }

    // MARK: - 内部

    /// 拆 `owner/name`。
    ///
    /// GitHub 保证 `full_name` 恰好含一个 `/`（owner 登录名与仓库名都不允许含 `/`），
    /// 所以这里**不是**在做容错解析，而是在**校验一条契约**：
    /// 它不成立就说明响应的含义变了，此时必须响亮地失败 ——
    /// 猜一个 owner 出来（比如取第一段）会让路由指向一个不存在的仓库，
    /// 而用户看到的只是一个 404 页面。
    ///
    /// ⚠️ **不是 `private`**：`RepoSummaryMapper` 用的是**同一条契约**
    /// （置顶与搜索的 `nameWithOwner` / `full_name` 同样是 `owner/name`）。
    /// 两处各写一遍拆分，迟早有一处把 `count == 2` 写成 `count >= 2` 而放行 `a/b/c`。
    ///
    /// 2026-10-06 由 `internal` 提升为 `public`：表现层的卡片（`RecentRow`）也要拆
    /// `owner` / `name` 来弱化显示 owner，而它**不该**为此构造一个 `RepoSummary`
    /// （那个类型还带 star / fork / 可写性等用不到的字段 —— 为拿两个字符串去填一堆假值，
    /// 等于把"这一个实现"的约束换成"到处凑一个领域对象"）。
    /// 提升可见性而不是复制一份实现，正是为了让口径仍然只有一处。
    public static func splitFullName(_ fullName: String) throws -> (owner: String, name: String) {
        let parts = fullName.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw RepositoryMappingError.malformedFullName(fullName)
        }
        return (String(parts[0]), String(parts[1]))
    }
}

/// 领域层的映射错误。
public enum RepositoryMappingError: Error, Equatable, Sendable {
    /// `full_name` 不是 `owner/name` 的形状。
    case malformedFullName(String)
}

// MARK: - DTO → 领域：权限

extension Permissions {

    /// 把 REST 的 `permissions` 解释成领域权限。
    ///
    /// ⚠️ **`nil`（响应里没带该字段）映射成"什么权限都没有"**，而不是"全都可写"。
    ///    这是本文件里最要紧的一条：`permissions` 只在已认证请求里返回，
    ///    把它的缺席当成"没说不行就是行"，会让一个本该只读的仓库显示出编辑入口 ——
    ///    用户点进去、改完文件、提交时才吃 403，而那时他已经把改动写完了。
    ///
    /// ⚠️ 单个键缺席同样按 `false`：GitHub 会在某些情形下省略 `admin` / `maintain`，
    ///    而**省略 `push` 的仓库确实就是推不了的那个**。
    public init(_ dto: RepositoryPermissionsDTO?) {
        guard let dto else {
            self = .none
            return
        }
        self.init(
            admin: dto.admin ?? false,
            maintain: dto.maintain ?? false,
            push: dto.push ?? false,
            triage: dto.triage ?? false,
            pull: dto.pull ?? false
        )
    }
}
