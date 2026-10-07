import Foundation
import GitHubAPI

/// 仓库详情页（**自己的仓库**，PRD §4.4）进页那一次取数。
///
/// ## 两个请求的失败后果**不同**，这是本类型的全部要点
///
/// | 请求 | 失败 |
/// |---|---|
/// | `GET /repos/{o}/{r}`（头部） | **整页失败** + 一个重试出口（§8.5 三档统一） |
/// | `GET /user/starred/{o}/{r}`（Star 基准） | **降级**：按钮按未 Star 显示，页面照常打开 |
///
/// 把这两件事写在同一个方法里、且返回值把它们分开，是为了让"Star 基准失败不该
/// 拖垮整页"这条口径只有一个落点 —— 否则它会在视图里散成一句
/// `try? await …`（看着无害，但那正是"失败被静默吞掉"）。
///
/// 基准查询失败的**兜底**在 `ToggleStar.initialState` 里（它把失败折叠成
/// `baselineConfirmed == false`），本类型只是**不把它并进头部的错误**。
public struct LoadRepoDetail: Sendable {

    private let detail: any RepoDetailDataSource
    private let star: ToggleStar

    public init(detail: any RepoDetailDataSource, star: ToggleStar) {
        self.detail = detail
        self.star = star
    }

    /// 进页取数。
    ///
    /// - Throws: `RepositoryMappingError.malformedFullName`（`fullName` 不是 `owner/name`）
    ///   与头部请求的任何错误。⚠️ **Star 基准的失败不会走到这里**。
    public func load(fullName: String) async throws -> RepoDetailSnapshot {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let dto = try await detail.repository(owner: owner, repo: repo)
        let model = RepositoryDetailMapper.detail(from: dto)

        // 基准查询在头部**之后**：`±1` 要有一个起点，而起点就是头部里那个计数
        // （决策 #41）。两次请求是串行的，但它们都很快、且第二次失败无害。
        let starState = await star.initialState(fullName: fullName, starCount: model.starCount)

        return RepoDetailSnapshot(detail: model, star: starState)
    }

    /// 只取头部，**不查 Star 基准**。
    ///
    /// 用在那些**不显示 Star**的页面：分支管理页（§4.8）只要一个 `defaultBranch`，
    /// 文件页只要知道自己在哪条分支上。那两处查一次基准是白花一个请求 ——
    /// 而它的结果没有任何一处会用到（不是"暂时没用"，是这个页面上根本没有那个按钮）。
    ///
    /// ⚠️ 走的是同一条路由 ⇒ 缓存键相同 ⇒ 从详情页点过来的那一次通常命中 304，不计配额。
    public func repository(fullName: String) async throws -> RepositoryDetail {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        return RepositoryDetailMapper.detail(
            from: try await detail.repository(owner: owner, repo: repo)
        )
    }
}

/// 仓库详情页首屏需要的那两样。
///
/// ⚠️ 它**不叫 `RepoInsights`**：那个是探索页的四路并发（含语言 / Release / 贡献者），
/// 而本页只要头部与 Star。两者的字段集互有出入，合并不成立
/// （同 `Repository` / `RepositoryDetail` 不合并的取舍）。
public struct RepoDetailSnapshot: Sendable {

    public let detail: RepositoryDetail

    /// Star 状态。基准未确认时它是 `baselineConfirmed == false` 的那一档，
    /// **不是** `nil` —— 界面读到的永远是"一个状态"，不必再判空。
    public let star: StarState

    public init(detail: RepositoryDetail, star: StarState) {
        self.detail = detail
        self.star = star
    }
}
