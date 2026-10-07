import Foundation
import GitHubAPI

/// 置顶仓库的数据来源 —— 领域层与网络层之间的**接缝**（同 `RepositoryDataSource`）。
///
/// 有了这层接缝，本包的测试可以直接喂一组 DTO 进去，不必复制一整套 HTTP 桩件；
/// 同时它把"领域层依赖的是哪几个动作"写明在类型上 —— 依赖的是**取数的能力**，
/// 不是某个具体的 GraphQL 客户端。
public protocol PinnedRepositoriesDataSource: Sendable {

    /// `viewer.pinnedItems(first: 6, types: [REPOSITORY])` —— **一次查询**取回全部置顶。
    ///
    /// ⚠️ 返回空数组是**正常结果**（还没置顶任何仓库），**不是**错误（§9.1）。
    func pinnedRepositories() async throws -> [PinnedRepositoryDTO]
}

/// 让真实端点满足上面的接缝。
///
/// 协议与本扩展都在 `GitDuoKit` 里，被扩展的类型在 `GitHubAPI` 里 —— 同
/// `RepositoryDataSource`，这**不是**追溯适配（协议是我们自己声明的）。
extension GitHubPinnedItemsEndpoint: PinnedRepositoriesDataSource {}

/// 取回首页的置顶仓库（PRD §4.1、TECH_SPEC §9.1、决策 #43）。
///
/// ## 它只做两件事
///
/// 1. 向接缝要一次 `viewer.pinnedItems`（**一次查询拿回全部**，见端点注释：不在 `nodes`
///    下再开连接，否则 1 点配额会涨到 100 点）；
/// 2. 把每个 DTO 映射成 `RepoSummary`（**不映射可写性** —— 置顶查询里根本没有
///    `permissions` 字段，见 `RepoSummary` 的类型说明）。
///
/// ## 它不认识"首页"
///
/// 本类型不知道调用方是首页还是别处，也不知道最近访问、清除按钮。那些是 Feature 的事。
public struct LoadPinnedRepositories: Sendable {

    private let source: any PinnedRepositoriesDataSource
    private let mapper: RepoSummaryMapper

    /// - Parameter source: 生产里传 `GitHubPinnedItemsEndpoint`；测试里传脚本化的替身。
    public init(
        source: any PinnedRepositoriesDataSource,
        mapper: RepoSummaryMapper = RepoSummaryMapper()
    ) {
        self.source = source
        self.mapper = mapper
    }

    /// 取回全部置顶仓库。
    ///
    /// - Returns: **顺序即 GitHub 上的排列顺序**（GraphQL 原样返回）——
    ///   不要在这里重排：置顶的顺序是用户自己在网页端拖出来的，重排等于改写他的意愿。
    /// - Throws: 除"没有置顶"外的一切错误。**空数组不是失败**，调用方据此渲染空态
    ///   `GitHub 个人主页还没有置顶仓库`（§9.1）。
    ///
    /// ⚠️ 一个失效的置顶（仓库被删 / 安装范围没勾到）会在接口层被 `compactMap` 掉，
    ///    只丢自己那一个 —— 所以这里的条目数**可能少于**用户实际置顶的数量。
    ///    这是有意的：让整块首页因为一个失效项而打不开，代价大得多（见端点注释）。
    public func load() async throws -> [RepoSummary] {
        try await source.pinnedRepositories().map { try mapper.map($0) }
    }
}
