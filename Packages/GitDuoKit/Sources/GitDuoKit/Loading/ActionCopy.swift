import Foundation

/// **「操作失败 · 请重试」** —— 写操作（Star / 删除分支 / 合并 / 新建标签 / 提交 Issue …）
/// 失败后的那一句通用提示。
///
/// ## 它的出处：§8.5 的「操作类」那一行
///
/// TECH_SPEC §8.5 的三档统一表里，「操作类」那一行逐字写着：
///
/// > **操作类**（提交、合并、关闭 Issue、Star）| 按钮内联 loading + **禁用**，防重复提交；
/// > 失败恢复可点并给 Toast
///
/// 也就是说这一句**不是 PRD §7 给的**（那一节给的是各操作各自成功时的提示），
/// 而是 §8.5 要求"失败必须给一个 Toast"之后推出来的那句通用话。
/// 同 `RefreshCopy.failed` 的来历（§8.5 的「分页 / 下拉刷新」那一行）。
///
/// ## ⚠️ 为什么它必须是一个正本（切片 7.4 收口）
///
/// 收口前这一句在仓里有**三份**同值副本，三个名字：
///
/// | 落点 | 名字 | 用在哪 |
/// |---|---|---|
/// | `BranchesViewModel.actionFailedToast` | 分支页 | 删除 / 合并 / 新建失败（toast **与**弹层内联提示两处） |
/// | `RepoDetailViewModel.actionFailedToast` | 仓库详情 | Star 失败 |
/// | `ExploreRepoViewModel.starFailedToast` | 探索仓库详情 | Star 失败 |
///
/// 而第四、第五个调用方已经在路上了：§4.10 新建 Issue 的「提交」失败、
/// §5.2 标签弹层的新建失败（那一处当时**借**了 `RepoDetailViewModel.actionFailedToast`，
/// 一个 ViewModel 去引另一个 ViewModel 的文案常量）。
///
/// ⚠️ 三份副本的**名字已经不一致**（`actionFailedToast` / `starFailedToast`），
/// 而其中 `BranchesViewModel` 那一份有一半的用途是**弹层内联提示**、不是 toast
/// —— 名字里的 `Toast` 早就名不副实。这一处一并改掉（`ActionCopy.failed` 不带呈现方式）。
///
/// ## ⚠️ 它为什么不写成一个带参数的函数
///
/// 因为**具体的失败成因各操作自己说得更准**，而那几句都已经在各自的 `…Copy` 里：
/// 合并冲突是 `BranchCopy.mergeConflictHint`、PR 不可合并是 `PullCopy.mergeNotMergeableToast`、
/// 分支名不合法是 `BranchCreationError.message`。
/// 本类型只在"没有更准的话可说"时兜底 —— 所以它是**一个常量**，
/// 不接收"操作名"之类的参数（那会诱使某一处拿它去拼一句本可以更具体的话）。
///
/// ⚠️ 同 `RefreshCopy`：`nil` / 空白不在这里判（判据在各自的用例里），本类型只管措辞。
public enum ActionCopy {

    /// 写操作失败的兜底提示。
    ///
    /// 后半句 `请重试` 是操作引导：§8.5 要求失败后"按钮恢复可点"，
    /// 而这句话告诉用户那件事 —— 少了它，一个转回原样的按钮看起来像"点了没反应"。
    public static let failed = "操作失败 · 请重试"
}
