import Foundation

/// 分支管理页（§4.8）与切换分支弹层（§5.7）的全部可见文案。
///
/// 与 `SearchCopy` 同源的理由：这是**可见契约**，而"什么时候该说哪一句"是业务规则。
/// 放进 `GitDuoKit` 才能被单测钉住（App target 没有测试 target）。
///
/// ## 逐字来源
///
/// - 分区标题、按钮、说明句、删除确认弹层 → 原型 `scripts/06-files.js` 的 `SCR.branches`
///   与 `deleteBranchAsk`；
/// - 切换弹层三句 → 原型 `scripts/15-sheets.js` 的 `openBranchSheet`。
///
/// ⚠️ 标了「**规格未给**」的几条是本片新增的（原型里那些状态根本不存在，
/// 因为它没有服务端、也没有 `protected`）。它们按原型同类句子的句式拟，
/// 并在 `REVIEW-CHECKLIST` 登记，等评审时逐句确认。
public enum BranchCopy {

    // MARK: - 分区标题与列表

    /// 分区标题：`{仓库全名} · 全部分支（{N}）`（原型逐字）。
    ///
    /// ⚠️ N 是**本页已加载的分支数**。`branches` 端点用 `per_page=100` 一页取回
    /// （§9.7.1），没有下一页 ⇒ 正常情况下它就是精确总数；
    /// 极端仓库（>100 条分支）下它会是**下界** —— 那时 `hasMore` 为真，
    /// 本函数**不**加 `+`（与 `OpenIssueIndicator.countLabel` 有意不同）：
    /// 那边列表在用户眼前逐条加载、"30+" 说的是"还没看完"；
    /// 这里的列表是一次全量取回后渲染的，加 `+` 会指向一个本页不存在的续页动作。
    public static func sectionTitle(fullName: String, count: Int) -> String {
        "\(fullName) · 全部分支（\(max(0, count))）"
    }

    /// 当前分支上的胶囊（原型逐字）。
    public static let currentPill = "当前"

    /// 删除按钮（原型逐字）。
    public static let deleteAction = "删除"

    /// 新建分支按钮（原型逐字，含全角 `＋`）。
    public static let createAction = "＋ 新建分支"

    /// 合并按钮：`合并分支到 {当前分支}…`（原型逐字，含省略号）。
    public static func mergeAction(current: String) -> String {
        "合并分支到 \(current)…"
    }

    /// 页脚说明（原型逐字）。
    public static let footer = "Merge 走 API · 冲突时引导到网页端处理"

    // MARK: - 删除确认弹层

    /// 弹层标题：`删除分支「{分支}」？`（原型 `deleteBranchAsk` 逐字）。
    public static func deleteSheetTitle(branch: String) -> String {
        "删除分支「\(branch)」？"
    }

    /// 弹层说明（原型逐字）。
    ///
    /// ⚠️ 它承诺的是"**删除前会校验**是否有未合并提交，有则阻止"——
    /// 那句承诺必须真的成立（决策 #53 落的正是这条），否则就是文案承诺了实现做不到的事。
    public static let deleteSheetHint = "删除前会校验该分支是否有未合并提交，有则阻止。删除后不可恢复。"

    /// 弹层里的确认按钮（原型逐字；红色底用的是 `--closed-p` 的色，见设计包）。
    public static let deleteConfirmAction = "删除分支"

    /// 通用取消（原型逐字）。
    public static let cancelAction = "取消"

    // MARK: - 删除的三种结局

    /// 删除成功（删除的不是当前分支）——原型 `deleteBranch` 逐字。
    public static func deletedToast(branch: String) -> String {
        "已删除分支 \(branch)"
    }

    /// 删除成功且删的**正是当前分支** —— 原型逐字（`· 已回到 {回落值}`）。
    ///
    /// 回落值由调用方按 `BranchResolver` 算好传进来，**不在这里重算**：
    /// 这里再算一次就是第二套解析规则（那份规则要读分支列表与记忆，本函数拿不到）。
    public static func deletedCurrentToast(branch: String, fallback: String) -> String {
        "已删除分支 \(branch) · 已回到 \(fallback)"
    }

    /// 未合并提交阻止删除（**规格未给**，PRD §4.8 只写"阻止并提示"）。
    ///
    /// 带上具体提交数：用户需要知道"挡我的是什么量级" ——
    /// 1 个提交可能只是忘了推，40 个则说明这是条有内容的分支。
    public static func unmergedBlockedToast(branch: String, aheadBy: Int) -> String {
        "\(branch) 有 \(max(0, aheadBy)) 个未合并的提交，无法删除"
    }

    /// 默认分支不可删（原型 `deleteBranchAsk` 逐字）。
    ///
    /// ⚠️ 正常情况下用户点不到它（`BranchSummary.canDelete` 为假时**不画**删除按钮），
    /// 这句是**逻辑层拦截**那一路的输出 —— 「不给入口」与「逻辑层拦截」两条路都要在。
    public static func defaultBranchBlockedToast(branch: String) -> String {
        "\(branch) 是默认分支，不可删除"
    }

    /// 受保护分支不可删（**规格未给**，决策 #53 新增）。
    ///
    /// 与上一条刻意分开成两句：它们对用户的**含义不同** ——
    /// 默认分支是"这条不能动，是仓库的门面"；受保护是"**规则**不允许，
    /// 而规则是仓库管理员设的"。合成一句会让后者看起来像前者的特例。
    public static func protectedBranchBlockedToast(branch: String) -> String {
        "\(branch) 是受保护分支，不可删除"
    }

    // MARK: - §5.7 切换分支弹层

    /// 弹层标题 —— 自己的仓库（原型逐字）。
    public static let switchSheetTitle = "切换分支 · 代码与 Commits 联动"

    /// 弹层标题 —— 他人仓库（原型逐字）。
    public static let switchSheetTitleReadOnly = "切换分支 · 浏览他人仓库"

    /// 「管理分支…」入口（原型逐字，含省略号与括号）。
    public static let manageBranchesRow = "管理分支…（创建 / 删除 / 合并）"

    /// 他人仓库的说明行（原型逐字）——本弹层**不给**管理入口的替代说明。
    public static let readOnlySheetHint = "他人仓库：可切换分支浏览，创建 / 删除 / 合并需先 Fork"

    /// 切换成功的提示：`已切换到 {分支}`（原型 `switchBranch` 逐字）。
    ///
    /// ⚠️ 用函数而不是"前缀常量 + 调用方拼"：后者会让那句文案的**形状**
    /// 散到调用点上去（`"已切换到 " + b` 与 `"已切换到\(b)"` 会并存）。
    public static func switchedToast(branch: String) -> String {
        "已切换到 \(branch)"
    }

    /// 切到一条**不属于当前仓库**的分支时的提示（原型 `switchBranch` 逐字）。
    ///
    /// 正常路径下点不到：弹层里列的就是当前仓库的分支。
    /// 留着它是因为 `switchBranch` 的两处防范原型都有，而"逻辑层也拦一次"
    /// 是本项目对会写盘的操作的固定做法。
    public static let foreignBranchToast = "该分支不属于当前仓库"

    // MARK: - 新建分支弹层（**规格未给**：PRD §4.8 只写"输入名称 → 从当前分支创建并切换"）

    public static let createSheetTitle = "新建分支"

    /// 输入框占位：`分支名（从 {当前分支} 创建）`。
    public static func createFieldPlaceholder(current: String) -> String {
        "分支名（从 \(current) 创建）"
    }

    /// 确认按钮。
    public static let createConfirmAction = "创建并切换"

    /// 创建成功的提示（句式对齐 `switchedToast`）。
    public static func createdToast(branch: String, from: String) -> String {
        "已从 \(from) 创建并切换到 \(branch)"
    }

    // MARK: - 合并弹层（决策 #52：**自己的弹层**，不复用「提交更改」）

    /// 弹层标题：`合并分支到 {目标分支}`。
    public static func mergeSheetTitle(target: String) -> String {
        "合并分支到 \(target)"
    }

    /// 源分支小节的标题。
    public static let mergeSourceLabel = "源分支"

    /// 目标分支小节的标题。
    public static let mergeTargetLabel = "目标分支"

    /// 目标分支只读说明 —— 目标恒为**当前分支**（`POST /merges` 的 `base`）。
    public static let mergeTargetHint = "当前分支，合并后提交到这里"

    /// 一个可以合并进来的源分支都没有。
    ///
    /// ⚠️ **规格未给，待评审**（自拟）。它不是理论上不会发生：只有一条 `main`
    /// 的仓库、或分支列表还没加载出来时，`mergeCandidates` 就是空的。
    /// PRD §4.8 把「合并分支…」列为**固定结构项**（第 4 条）⇒ 按钮不隐藏，
    /// 于是这条弹层必须能表达"没有东西可合"。
    /// ⚠️ 它**不是** 204 那一句（`nothingToMergeToast`）：那一句说的是
    /// "你选的那条已经合过了"，而这一句说的是"你没得选"。
    public static let mergeNoSourceHint = "没有其他分支可以合并进来"

    /// 提交信息输入框的占位（可选项）。
    public static let mergeMessagePlaceholder = "合并提交信息（可选）"

    /// 确认按钮。
    public static let mergeConfirmAction = "合并"

    /// 冲突引导（PRD §4.8 第 5 条的说明句 + 冲突出口）。
    public static let mergeConflictHint = "冲突时 GitHub 会拒绝合并，请到网页端处理"

    /// 合并成功的提示。
    public static func mergedToast(source: String, target: String) -> String {
        "已把 \(source) 合并到 \(target)"
    }

    /// **204：没有东西可合**（`head` 已经合进 `base`）—— 决策 #52 的三种结局之一。
    ///
    /// ⚠️ **规格未给，待评审**（自拟）。它与 `mergedToast` **必须分开**：
    /// 说"已把 X 合并到 Y"会让用户以为刚刚产生了一个合并提交，
    /// 而 204 的含义恰恰是**服务端什么都没做**（那正是 `.nothingToMerge` 想表达的）。
    public static func nothingToMergeToast(source: String) -> String {
        "\(source) 已经合并过，没有新的改动"
    }
}
