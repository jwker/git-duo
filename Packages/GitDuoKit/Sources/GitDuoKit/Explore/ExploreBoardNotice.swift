import Foundation

/// 探索榜列表上的**说明行文案**（PRD §7「列表说明行」、§4.12）。
///
/// ## 为什么放在领域层
///
/// 与 `ExploreFilterChange.toastText` 同源的理由：这是**可见契约**，
/// 而"什么时候该说这句话"是一条业务规则（不是排版选择）。放进 `GitDuoKit`
/// 才能被单测钉住 —— App target 没有测试 target。
///
/// ## ⚠️ 它不是错误态
///
/// `incomplete_results` 是 GitHub 在**计算超时**时的自述："这个回答不完整"。
/// 界面的正确反应是**照常渲染已拿到的条目 + 说明一句**，而不是把整屏变成错误页 ——
/// 内容是可用的，只是少了一些本该在里面的。
public enum ExploreBoardNotice {

    /// 结果不完整时列表标题下方的说明行（2026-10-06 用户拍板，PRD §4.12 / §7）。
    ///
    /// 句尾给出**下一步动作**（下拉刷新重试）而不是停在"可能不完整"：
    /// 只说问题不给出口，用户只能干瞪眼。
    public static let incompleteResults = "结果可能不完整（GitHub 计算超时）· 下拉刷新重试"

    /// 无结果时的空态文案（PRD §7「空态」原文，原型 `trendRows()` 逐字一致）。
    public static let noResults = "没有符合条件的仓库，试试放宽筛选"

    /// 空态该用哪一句。
    ///
    /// ⚠️ **这是本类型存在的主要理由**：当 `incomplete_results` 为真且列表为空时，
    /// 说「没有符合条件的仓库」是**编造结论** —— GitHub 刚说过"我的回答不完整"。
    /// 那一刻唯一诚实的说法是"结果可能不完整"。所以不是"两个文案各自独立地显示"，
    /// 而是**哪个优先**由这一条规则决定。
    ///
    /// ⚠️ 形参名**必须**与上面两个常量不同名（曾用 `incompleteResults:`，于是函数体里
    /// 那个名字指的是 `Bool` 形参、把常量遮住了，编译器报的是
    /// `cannot convert return expression of type 'Bool' to return type 'String'` ——
    /// 一句和"文案"毫不相干的错误）。
    public static func emptyStateText(isIncomplete: Bool) -> String {
        isIncomplete ? incompleteResults : noResults
    }
}
