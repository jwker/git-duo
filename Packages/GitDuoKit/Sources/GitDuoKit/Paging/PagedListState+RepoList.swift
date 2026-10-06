import Foundation

/// 仓库列表的展示层派生 —— §9.3「分段切换不重新请求」的落点。
///
/// ## 为什么这三段过滤必须在**展示时**做
///
/// 因为用户会来回切段。若在取数时过滤，切到「私有」再加载的那一页会把其中的公开仓库丢掉，
/// 切回「全部」时它们就凭空消失了。所以累计的是**未过滤**的原始条目，
/// 每次渲染再按当前段现算 —— 切换段只是换一个过滤条件，不重新请求，也不丢数据。
extension PagedListState where Item == Repository {

    /// 当前段可见的条目。
    public func visibleItems(segment: RepoListSegment) -> [Repository] {
        items.filter(segment.matches)
    }

    /// 当前段的渲染形态（把分段过滤喂给通用状态机）。
    public func content(segment: RepoListSegment) -> PagedListContent {
        content(matching: segment.matches)
    }
}
