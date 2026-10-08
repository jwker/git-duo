import GitDuoDesign
import GitDuoKit

/// 「领域层的状态」→「设计包的胶囊色调」的**唯一转换处**（§4.9 / §4.11）。
///
/// ## 为什么要有这一件
///
/// `ConversationHeader` 收一个 `StatusPill.Tone`（设计包的类型），而两个详情页手上
/// 拿的是**领域层**的状态。这个翻译必须只写一份：
///
/// - 两个页面各写一个 `switch` 的话，漏掉 `.closed` 那一档的下场是那个分支
///   落到别处 —— 而"已关闭的 PR 显示成紫色（已合并）"在屏幕上看起来很正常
///   （两种状态本来就都是"结束了"）。
/// - 更要紧的是，**已关闭的 Issue 与已合并的 PR 用的是同一个紫族**
///   （原型 `.pill.closed-i` / `.pill.merged` 配色逐字相同，见 `StatusPill.Tone`），
///   所以 Issue 侧那两档**不是** `.open` / `.closed`，而是 `.open` / `.merged`。
///   这条反直觉的映射正是最容易在第二处写错的东西。
///
/// ## ⚠️ 与 `PullCard.tint(for:)` 不是重复
///
/// 那一族是**状态图标**的颜色（`stateOpenIcon` / `stateCompletedIcon`，比胶囊色亮一档），
/// 这一族是**胶囊**的（`stateOpen` / `stateMerged` / `stateClosed`）。
/// 混用的症状是图标与它旁边的文字串味（`Theme.Palette.stateOpenIcon` 的说明写了这条）。
///
/// ## ⚠️ 搜索页那一份没有合并进来
///
/// `SearchResultRows` 里另有一处同形状的翻译，但它的输入是
/// `ConversationStatusTone`（搜索领域的族，与 `PullRequestState` 不是同一个枚举）。
/// 硬揉成一个函数就得先统一那两个领域类型 —— 那是搜索侧的事，
/// 不该在切片 7 里顺手做掉。两者的映射规则**逐条相同**（`open→.open`、
/// `completed/merged→.merged`、`closed→.closed`），若哪天两个枚举合一，落点是这里。
enum StateTone {

    /// Issue 的两档：开放 = 绿族，已关闭 = **紫族**（原型 `.pill.closed-i`）。
    ///
    /// ⚠️ 参数是 `isOpen` 而不是 `IssueDetail`：本件不认识领域模型
    /// （判据 #43 的反向运用 —— 能收基础类型就收基础类型，这里两边都只是"一个布尔"）。
    static func tone(isOpen: Bool) -> StatusPill.Tone {
        isOpen ? .open : .merged
    }

    /// PR 的三档：开放 = 绿族，已合并 = 紫族，已关闭（未合并）= **红族**。
    ///
    /// ⚠️ 三分支的顺序与 `PullRequestState` 的声明顺序一致，但判据不依赖它。
    static func tone(for state: PullRequestState) -> StatusPill.Tone {
        switch state {
        case .open: .open
        case .merged: .merged
        case .closed: .closed
        }
    }
}
