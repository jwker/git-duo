import Foundation
import GitHubAPI

/// 列表加载状态机 —— `{ items, isLoading, canLoadMore, error }`（TECH_SPEC §4.4）。
///
/// ## 为什么它是个**纯值类型**，而不是 ViewModel 里的几个 `@Published`
///
/// 因为 §4.4 让每个列表都暴露这四个量，而"什么时候算加载完""失败之后还能不能再加载"
/// 这类判断恰恰是最容易写错、又最难靠点击发现的地方（表现是重复行、永远转圈、
/// 或"加载更多"点了没反应）。App target 没有测试 target，所以这套状态机放在领域层，
/// 由 ViewModel 持有并转发 —— 于是它可以被单测覆盖。
///
/// 它**只做状态**，不发请求：请求由 `LoadRepositoriesPage` 发，结果喂给 `received(_:)`。
public struct PagedListState<Item: Identifiable & Sendable>: Sendable {

    /// 已加载的条目（顺序即渲染顺序）。
    public private(set) var items: [Item] = []

    /// 是否有请求在途。
    public private(set) var isLoading = false

    /// 下一页的游标（服务端 `Link: rel=next` 给的完整 URL）；`nil` = 已到底。
    ///
    /// 它是**唯一的真相**，`canLoadMore` 由它派生 —— 两份状态必然会不同步。
    public private(set) var nextCursor: URL?

    /// 最近一次失败。**与 `items` 并存**：分页失败时已加载的内容必须留在屏幕上（§8.5）。
    public private(set) var error: GitHubError?

    /// 是否已经完成过至少一次加载（成功或失败都算）。
    ///
    /// 它的唯一用途是**把"还没开始"与"确实没有"分开**：没有它，首帧会先渲染一次
    /// `items` 为空、`isLoading` 为假的状态，于是屏幕上闪过一瞬「还没有仓库」，
    /// 再变成骨架屏 —— 用户看到的是"明明有仓库却说没有"。
    public private(set) var hasLoaded = false

    /// 下一次 `received` 是**替换**还是**追加**（下拉刷新 = 替换）。
    ///
    /// ⚠️ 替换**不在 `beginLoad` 时就清空 `items`**：§8.5 要求下拉刷新"不遮挡已有内容"。
    ///    先清空会让整屏瞬间塌成骨架，刷新失败时用户还会发现内容全没了。
    private var isResetting = false

    public var canLoadMore: Bool { nextCursor != nil }

    public init() {}

    // MARK: - 迁移

    /// 开始一次加载。`reset = true` 表示下拉刷新（拿到结果后整体替换）。
    ///
    /// ⚠️ 它**不动 `nextCursor`**：刷新失败时那个游标还有效（指向旧数据的下一页），
    ///    清掉它等于一次刷新失败就让用户彻底失去"加载更多"的入口；
    ///    而刷新成功时 `received` 会把它覆盖掉。
    public mutating func beginLoad(reset: Bool) {
        isLoading = true
        error = nil
        isResetting = reset
    }

    /// 收到一页结果（已映射；过滤在展示层做）。
    public mutating func received(_ page: Page<Item>) {
        let incoming = isResetting ? page.items : merged(items, page.items)
        items = incoming
        nextCursor = page.nextCursor
        isLoading = false
        error = nil
        isResetting = false
        hasLoaded = true
    }

    /// 一次加载失败。
    public mutating func failed(_ error: GitHubError) {
        self.error = error
        isLoading = false
        isResetting = false
        hasLoaded = true
        // `nextCursor` **保持不变**：失败的是这一次尝试，不是"后面没有了"。
        // 清掉它会让用户永远失去重试入口。
    }

    /// 回到初始状态（切换账号 / 登出时用）。
    public mutating func reset() {
        self = PagedListState()
    }

    // MARK: - 派生

    /// 主区域的渲染形态（§8.5：骨架 / 内容 / 空态 / 失败，四者可辨）。
    ///
    /// - Parameter isIncluded: 展示层的过滤条件。默认全收 ——
    ///   仓库列表会传当前分段（§9.3 的"本地过滤"），见 `content(segment:)`。
    ///
    /// ⚠️ **判断"有没有内容"必须基于过滤后的结果**，而不是 `items` 是否为空：
    ///    「全部」段拉到 30 条公开仓库时切到「私有」段，`items` 非空但一条都不该显示。
    public func content(matching isIncluded: (Item) -> Bool = { _ in true }) -> PagedListContent {
        if items.contains(where: isIncluded) { return .items }
        // ⚠️ 顺序：`hasLoaded` 与 `isLoading` 必须排在 `error` / `empty` 之前。
        //    否则首帧（还没请求）会渲染成「还没有仓库」。
        if !hasLoaded || isLoading { return .skeleton }
        if let error { return .failure(error) }
        // ⚠️ 空、但服务端还有下一页 —— 此时**不能说"还没有"**：
        //    本地过滤的三段（全部/公开/私有）共用同一份分页数据，
        //    这一页恰好没有该段的条目，不代表后面没有。
        if canLoadMore { return .needsMore }
        return .empty
    }

    // MARK: - 内部

    /// 追加并按 `id` 去重。
    ///
    /// 去重不是洁癖：列表按 `sort=updated` 排序，**翻页期间有人推了一次提交**
    /// 就会让某一条从第 2 页挪到第 1 页，于是它在两页里各出现一次。
    /// 不去重的话 `ForEach` 会拿到两个相同的 id（渲染告警 + 视觉上是重复行）。
    ///
    /// 保留**已在列表里的那份**（`existing` 优先），避免已经渲染的行被替换掉。
    private func merged(_ existing: [Item], _ incoming: [Item]) -> [Item] {
        var seen = Set(existing.map(\.id))
        var result = existing
        for item in incoming where seen.insert(item.id).inserted {
            result.append(item)
        }
        return result
    }
}

/// 列表主区域的渲染形态。
///
/// 有意**定义在泛型之外**：它不依赖条目类型，放在 `PagedListState<T>` 里面
/// 会让每个引用点都要写 `PagedListState<Repository>.Content` 这种话。
public enum PagedListContent: Equatable, Sendable {
    /// 首屏骨架屏（尚未拿到任何内容）。
    case skeleton
    /// 有内容。
    case items
    /// 空、但还有下一页 ⇒ 给「继续加载」，不得断言"还没有"。
    case needsMore
    /// 空、且已到底 ⇒ 逐段空态文案。
    case empty
    /// 首屏失败（已有内容时的分页失败走底部重试行，不影响这里）。
    case failure(GitHubError)
}
