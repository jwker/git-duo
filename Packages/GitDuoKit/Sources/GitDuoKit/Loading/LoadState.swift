import GitHubAPI

/// 一次性取数的加载态 —— 首页置顶（§9.1）与探索仓库详情（§9.11）共用。
///
/// ## 为什么不复用 `PagedListState`
///
/// 那两个页面**没有分页**：置顶是"一次 GraphQL 查询取回全部"（§9.1 的性能一行），
/// 详情四路各自只回一个响应。套用 `PagedListState` 就必须伪造一个
/// `Page(items: …, nextCursor: nil)`，于是 `canLoadMore` 恒假、
/// `received(_:)` 里的去重与追加逻辑**永远走不到** —— 一个有一半分支是死代码的状态机，
/// 比一个窄一点的类型更难读，也更难在下一次改动时判断"这段还有没有用"。
///
/// ## 为什么它在领域层，而不是写在 ViewModel 里
///
/// 与 `PagedListState` 同源的理由：**App target 没有测试 target**。
/// 而"哪一刻该显示骨架屏、哪一刻才算失败、失败之后还能不能再试"恰恰是最容易写错、
/// 又最难靠点击发现的地方（表现是闪一下空白、或失败后永远转圈）。
/// 放进本包，它就落在 `LoadStateTests` 里。
public enum LoadState<Value: Sendable>: Sendable {

    /// 还没开始（首帧）。它与 `loading` 在界面上**同一种样子**，见 `presentation`。
    case idle

    /// 请求在途。
    case loading

    case loaded(Value)

    case failed(GitHubError)

    // MARK: - 读取

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// 只有成功才有值 —— 界面不得从失败态里"抠"出一份旧值继续用。
    public var value: Value? {
        if case let .loaded(value) = self { return value }
        return nil
    }

    public var error: GitHubError? {
        if case let .failed(error) = self { return error }
        return nil
    }

    /// 是否已经完成过至少一次取数（**成功或失败都算**）。
    ///
    /// 它把"还没开始"与"确实取完了"分开 —— 这也是 `presentation` 里
    /// `idle` 与 `loading` 要合并的原因：对用户来说这两者都是"东西还没来"。
    public var hasFinished: Bool {
        switch self {
        case .idle, .loading: false
        case .loaded, .failed: true
        }
    }

    // MARK: - 迁移

    public mutating func begin() {
        self = .loading
    }

    public mutating func succeed(_ value: Value) {
        self = .loaded(value)
    }

    public mutating func fail(_ error: GitHubError) {
        self = .failed(error)
    }

    /// 回到初始状态（切换账号 / 登出）。
    public mutating func reset() {
        self = .idle
    }
}

/// 首屏该画哪一种（§8.5 的三档：骨架 / 内容 / 失败）。
///
/// 与 `PagedListContent` 并列而不是合并：后者还要区分
/// `.needsMore`（空但还有下一页）与 `.empty`，而一次性取数没有这两个概念。
public enum LoadPresentation: Equatable, Sendable {

    /// 首屏骨架屏。
    case skeleton

    /// 有内容。**"内容为空"是调用方的事** —— 只有它知道该说
    /// 「GitHub 个人主页还没有置顶仓库」还是「这个仓库还没有贡献者」。
    case content

    /// 首屏失败 —— 必须给一个重试出口（PRD §1 设计原则 4）。
    case failure(GitHubError)
}

extension LoadState {

    /// 首屏渲染形态。
    ///
    /// ⚠️ `idle` 与 `loading` **都**映射到骨架屏 —— §8.5 明写「加载中 ≠ 无数据，
    /// 不得用空态文案代替加载态」。两者的区别只在"是否已经发过请求"，那是内务；
    /// 若把 `idle` 映射成空态，首帧会先闪一下「还没有置顶仓库」再变成骨架屏，
    /// 用户看到的是"明明有置顶却说没有"。
    public var presentation: LoadPresentation {
        switch self {
        case .idle, .loading: .skeleton
        case .loaded: .content
        case let .failed(error): .failure(error)
        }
    }
}
