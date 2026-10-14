import Foundation

/// 仓库的**列表分区**（PRD §4.4 第 2 条、原型 `SCR.repoSection` 一个路由三档）。
///
/// ## ⚠️ 2026-10-14：「代码」**不再是**一个分区（走查第 63 条）
///
/// 用户要求把仓库页改成「首页 + 四个入口」：进仓库先看到头部大卡与四行入口，
/// **代码浏览整块搬进一个独立页面**（它自己承载目录层级），Issues / Pull Requests /
/// Commits 也各自成一页。于是：
///
/// - 本枚举**收成三档** —— 它就是那三个列表页的身份；
/// - 「代码」那一行不是这里的一员，它在 `RepoCopy.codeEntryTitle`
///   （它是**一个入口**，不是"某一档分区"，混进这个枚举会让"分区页拿到 `.code`"
///   成为一个类型上合法、运行时无意义的值）；
/// - `initial`（原「进仓库默认落代码」）**删掉了**：首页不再"默认选中某一段"。
///
/// ## 顺序就是声明顺序
///
/// `CaseIterable` 的顺序 = 首页那四行入口里**后三行**从左到右的顺序
/// （代码 / Issues / Pull Requests / Commits 去掉首行之后）。
/// 视图直接遍历 `allCases` 渲染这几行，不要自己写一个数组 ——
/// 那样两处顺序会在某次调整里分叉，而"入口顺序变了"没有人会当成 bug 报上来。
public enum RepoSection: String, CaseIterable, Sendable {

    case issues
    case pullRequests
    case commits

    /// 页面上可见的文字（原型逐字，含英文大小写）。
    ///
    /// ⚠️ `pullRequests` 的「Pull Requests」（全大写 P、R）是**原型的写法**，
    /// 与 `RepoCopy.codeEntryTitle` 那一行并列时两种大小写会同时出现 ——
    /// 那是原样保留的既有文案，不在这里统一。
    public var title: String {
        switch self {
        case .issues: "Issues"
        case .pullRequests: "Pull Requests"
        case .commits: "Commits"
        }
    }
}
