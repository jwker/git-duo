import Foundation

/// 仓库详情的四个分区（PRD §4.4 第 2 条、原型 `SCR.repoDetail` 的 `.prtabs`）。
///
/// ## 顺序就是声明顺序
///
/// `CaseIterable` 的顺序 = 分段条上从左到右的顺序（代码 / Issues / Pull Requests /
/// Commits），与原型 `[['code','代码'],['issues','Issues'],['prs','Pull Requests'],['commits','Commits']]`
/// **逐位一致**。视图直接遍历 `allCases` 渲染，不要自己写一个数组 ——
/// 那样两处顺序会在某次调整里分叉，而"分段条顺序变了"没有人会当成 bug 报上来。
///
/// ## ⚠️ 「本片交付了哪几段」**不在这里**
///
/// 决策 #50 曾定下切片 6 只交「代码」与「Commits」，Issues / Pull Requests 归切片 7，
/// 落地方式是"分段条照画满四项、未交付的两段用占位块显式标注"。
/// 那条信息属于**施工进度**，不属于产品语义 —— 把它做成 `RepoSection.isDelivered`
/// 会让这个枚举在切片 7 之后还需要再改一次（去掉那个属性），
/// 而"哪几段还没做"的判断本来就该在路由/视图那一层（那里才看得见当前进度）。
/// **四段现已全部交付**（7.4 换真件），那个占位块类型也随切片 9 一起删掉了。
public enum RepoSection: String, CaseIterable, Sendable {

    case code
    case issues
    case pullRequests
    case commits

    /// 分段条上的可见文字（原型逐字，含英文大小写）。
    public var title: String {
        switch self {
        case .code: "代码"
        case .issues: "Issues"
        case .pullRequests: "Pull Requests"
        case .commits: "Commits"
        }
    }

    /// 默认落在哪一段 —— 进仓库先看到代码（PRD §4.4「分区一：代码（默认）」）。
    public static let initial: RepoSection = .code
}
