import Foundation
import GitHubAPI

/// 取一页仓库 —— 「按数据源取数 → 映射」这一个业务动作（TECH_SPEC §9.3）。
///
/// 命名按 §2.1 的 UseCase 惯例（"业务动作"），而不是叫 `XxxRepository` ——
/// 本项目里 `Repository` 一词既指"仓库"这个领域模型（§6.2），也指"仓储"这个模式（§2.1），
/// 把它拼进类型名会得到一个读不出意思的名字。
///
/// ## ⚠️ 它**只取数、不过滤** —— 这是 §9.3 逼出来的
///
/// §9.3【已定】：**分段切换不重新请求**（全部 / 公开 / 私有三段共用同一份已拉取的数据，
/// 各自本地过滤），"加载更多"时按当前段决定后续请求。
///
/// 如果在这一层就按段过滤掉，会出现一个很难发现的数据缺失：
/// 用户切到「私有」再加载下一页 ⇒ 这一页里的公开仓库被**丢弃**，
/// 于是切回「全部」时它们就永远不存在了 —— 而界面上没有任何迹象说明少了什么。
///
/// 所以职责这样切：
/// - **本类型**：按数据源取一页、映射成领域模型（数据源由 `RepoListSource` 决定）；
/// - **累计与过滤**：由 `PagedListState` 持有原始条目，展示时用
///   `visibleItems(segment:)` / `content(segment:)` 现算（§9.3 的"本地过滤"）。
public struct LoadRepositoriesPage: Sendable {

    private let source: any RepositoryDataSource
    private let mapper: RepositoryMapper

    /// - Parameter source: 生产里传 `GitHubRepositoryEndpoint`；测试里传一页脚本化的替身。
    public init(source: any RepositoryDataSource, mapper: RepositoryMapper = RepositoryMapper()) {
        self.source = source
        self.mapper = mapper
    }

    /// - Parameters:
    ///   - source: 取哪一份数据（§9.3：前三段共用 `.repos`，Starred 段用 `.starred`）。
    ///   - cursor: 上一页的 `nextCursor`；`nil` 表示第一页。
    public func load(source which: RepoListSource, cursor: URL? = nil) async throws -> Page<Repository> {
        let raw: Page<RepositoryDTO>
        switch which {
        case .repos:
            raw = try await source.listRepos(cursor: cursor)
        case .starred:
            raw = try await source.listStarred(cursor: cursor)
        }

        // ⚠️ 游标原样带走：`nextCursor` 是服务端给的续页地址，
        //    映射不该顺手把它吃掉（否则"加载更多"永远拿不到下一页）。
        return try mapper.map(raw)
    }
}
