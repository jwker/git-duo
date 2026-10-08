import Foundation

/// §4.4 分区二 / 分区三分段条上的**两档**（PRD §4.4、决策 #61）。
///
/// ## 为什么不再用一个 `RepoListState`
///
/// `RepoListState` 有**三**档（`open` / `closed` / `all`）—— `all` 是搜索与探索页
/// 那种"不筛"的语义，而这两段的界面上**没有这一格**：用户要在「开放」与
/// 「已关闭 / 已合并」之间二选一，没有"两个都要"这个选项。
///
/// 直接复用三档枚举会逼出**两处运行时防御**：
/// ① 视图画分段条时要写 `[.open, .closed]` 这样一个**筛过的**数组
///    （而不是 `allCases`）—— 于是"顺序对不对""有没有漏一格"都变成口头约定，
///    而漏一格的后果是那一档点不着（不报错）；
/// ② "当前是哪个列表"那个计算属性必须处理 `.all`，而它落进哪一支都是**静默错**
///    （落 `open` 会让"全部"看起来像"开放"）。
///
/// 一个只有两档的枚举把这两件事都变成**编译期**的事。
///
/// ## 两段的档位是同一对，只有文案不同
///
/// Issues 段的第二格写 `已关闭`、PR 段写 `已合并`
/// （`RepoIssuesSectionCopy` / `RepoPullsSectionCopy` 各给各的）——
/// 但底下的 `state` 映射**完全一样**（`open` → `open`，`closed` → `closed`），
/// 所以档位本身只有一份：复制成两个枚举的话，哪天要加第三档（例如"按作者筛"）
/// 就会只加到其中一段。
public enum RepoSectionSegment: String, CaseIterable, Sendable, Hashable {

    /// 「开放」档。
    case open

    /// 第二档 —— Issues 段显示为「已关闭」、PR 段显示为「已合并」。
    ///
    /// ⚠️ 两段的服务端取值**都是 `closed`**：GitHub 没有"只看已合并"这一个筛选项
    /// （`state` 只有 `open` / `closed`），合并与"关闭但没合并"得靠 `merged_at`
    /// 本地分开（`PullRequestState` 的说明写了那条规则）。
    /// 所以 PR 段取回这一批之后还有**一道本地过滤** —— 那是 `LoadRepoPulls` 的活，
    /// 本枚举只负责"向服务端要哪一批"。
    case closed

    /// 传给 `LoadRepoIssues` / `LoadRepoPulls` 的取值。
    ///
    /// ⚠️ 写成 `switch` 而不是 `rawValue`：两者的字符串**恰好**相同
    /// （`"open"` / `"closed"`），直接 `rawValue` 也能跑 —— 但那样就把
    /// "这两个枚举的取值恰好重合"变成一条**没人守得住**的隐式契约，
    /// 而它一旦不成立（例如以后给 `.closed` 换个更准确的名字），
    /// 出错的是发出去的请求、表现是一个空列表。
    public var listState: RepoListState {
        switch self {
        case .open: .open
        case .closed: .closed
        }
    }
}
