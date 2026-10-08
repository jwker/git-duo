import Foundation

/// PR 详情的三个分区（PRD §4.11 第 2 条、原型 `08-pr.js:15` 的 `.prtabs`）。
///
/// ## 顺序就是声明顺序
///
/// `CaseIterable` 的顺序 = 分段条上从左到右的顺序（对话 / Commits / 文件），
/// 与原型 `[['conv','对话'],['commits','Commits'],['files',`文件 ${curPr.ds}`]]`
/// **逐位一致**。视图直接遍历 `allCases` 渲染，不要自己写一个数组 ——
/// 那样两处顺序会在某次调整里分叉（同 `RepoSection` 的口径）。
///
/// ## ⚠️ 它与 `RepoSection` 不能合并成"一个通用的分区分段条"
///
/// 两者的**领域完全不同**（仓库四分区 vs PR 三分区），而合并的代价不是多写一个枚举，
/// 是"哪一个页面上该出现哪几格"变成运行时的数组内容 —— 漏一格不会报错，
/// 只会让那一档点不着（`RepoSectionSegment` 的说明里已经记过这条）。
///
/// ## ⚠️ 第三个分区的标题**带数据**（与另外两格不一样）
///
/// 原型是 `文件 ${curPr.ds}` —— 那个 `+842 −156` 来自 `PullDetailDTO`，
/// **只有详情端点给**（决策 #58）。所以 `title(stats:)` 必须吃一个参数，
/// 而不像 `RepoSection.title` 是一个无参属性。
///
/// 这一点决定了 PR 详情页的骨架期**整页都是骨架**（含分段条）：
/// 详情还没到手时第三格的文案拼不出来，先画一条"文件"、等数据到了再补上 `+842 −156`
/// 会让那三个字在眼前跳一下。仓库详情那边分段条能先画，是因为它的四格标题
/// 不依赖任何数据。
public enum PullSection: String, CaseIterable, Sendable, Hashable {

    /// 分区一：对话（评论 + 评审合成的时间线）。
    case conversation

    /// 分区二：Commits（进分区才取）。
    case commits

    /// 分区三：文件 + diff 卡片（进分区才取）。
    case files

    /// 分段条上的可见文字。
    ///
    /// - Parameter stats: `PullDetail.statsLabel`（`+842 −156`）。
    ///   ⚠️ **必传**，不给默认值 —— 给它一个空串默认值，会让某一处忘传时
    ///   静默渲染出 `文件 `（尾巴上一个孤零零的空格），而那看起来像排版瑕疵、
    ///   不像一个 bug。
    public func title(stats: String) -> String {
        switch self {
        case .conversation: PullCopy.conversationSegment
        case .commits: PullCopy.commitsSegment
        case .files: PullCopy.filesSegment(stats: stats)
        }
    }

    /// 默认落在哪一段 —— 进 PR 先看到对话（原型 `08-pr.js:6` 的 `p.seg||'conv'`）。
    ///
    /// ⚠️ 写成 `.allCases.first` 而不是 `.conversation`：让"默认"与"顺序"
    /// 是同一件事（同 `PullCopy.defaultMergeMethod` 的理由）——
    /// 哪天有人把 `files` 挪到第一位，默认仍然是"第一条"。
    public static var initial: PullSection {
        allCases.first ?? .conversation
    }
}
