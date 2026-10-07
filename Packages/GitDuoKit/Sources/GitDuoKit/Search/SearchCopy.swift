import Foundation
import GitDuoCore

/// 搜索页的全部可见文案（PRD §4.2 / §5.10 / §7、TECH_SPEC §9.2）。
///
/// ## 为什么放在领域层
///
/// 与 `ExploreBoardNotice` / `OpenIssueIndicator` 同源的理由：这是**可见契约**，
/// 而"什么时候该说哪一句"是一条业务规则（不是排版选择）。放进 `GitDuoKit`
/// 才能被单测钉住 —— App target 没有测试 target。
///
/// ## ⚠️ 原型每页末尾那段 `本页功能点 · 搜索` **不照抄**
///
/// 它是原型给评审看的**标注面板**（`fnote('搜索', ...)`，由 `fnToggle` 开关，
/// 十个页面各有一份），不是产品界面；交付物里没有它。
/// 同理，`ExploreBoardNotice` 当时也没照抄原型那句后缀的 `· 只读演示数据`。
public enum SearchCopy {

    /// 输入框占位符（原型 `SCR.search.render` 逐字）。
    public static let fieldPlaceholder = "搜索仓库、用户、代码、Issue…"

    /// 空闲态两个小节的标题（原型 `searchIdleHTML` 逐字）。
    public static let recentSectionTitle = "最近搜索"
    public static let hotSectionTitle = "热门关键词"

    /// 「最近搜索」右侧的按钮（原型 `clearSearchHistory` 的按钮文字）。
    public static let clearHistoryAction = "清除"

    /// 没有历史时的空态（原型 `searchIdleHTML` 逐字）。
    public static let emptyHistory = "还没有搜索记录"

    /// 清空历史后的提示（原型 `clearSearchHistory` 的 toast 逐字）。
    public static let historyClearedToast = "已清除搜索记录"

    /// 回车时的提示：`搜索「swiftui」`（原型 `commitSearch` 逐字）。
    public static func submittedToast(keyword: String) -> String { "搜索「\(keyword)」" }

    /// 输入不够格时的提示（原型 `commitSearch` 逐字）。
    ///
    /// ## ⚠️ 它现在兼两个用途（2026-10-07 用户拍板）
    ///
    /// 1. 回车时关键词为空 ⇒ **toast**（原型用法）；
    /// 2. **代码范围只填了限定符**（如 `language:go`）⇒ 结果区的**说明行**。
    ///
    /// 第 2 条是原型没有的：原型是本地过滤、从不发请求，所以它不会遇到
    /// "这个查询服务端不收"的情形。真实 API 会回 422，且**照样扣配额**
    /// （代码那一档只有 10 次/分钟）⇒ 必须在本地拦下并说一句。
    /// 用户选定**复用这一句**而不是新拟一条，语义也对得上：只有限定符等于没有关键词。
    public static let needsKeyword = "先输入关键词"

    /// 结果标题：`{范围名} · {N} 个结果`（原型 `searchBody` 的 `.section-label`）。
    ///
    /// ⚠️ **N 是服务端匹配总数**（`total_count`，与 GitHub 网页端一致），
    /// 不是屏幕上已加载的条数 —— 理由见 `LoadSearch.Result.totalCount`。
    /// 千分位用 `GroupedNumber`：原型那处是 `rows.length`（演示数据不足十位，
    /// 看不出差别），而真实结果动辄上千。
    public static func resultsTitle(scope: SearchScope, totalCount: Int) -> String {
        "\(scope.title) · \(GroupedNumber.string(from: totalCount)) 个结果"
    }

    /// 无结果时的第一行：`没有匹配「swiftui」的仓库`（原型 `searchBody` 逐字）。
    public static func noResultsTitle(scope: SearchScope, keyword: String) -> String {
        "没有匹配「\(keyword)」的\(scope.title)"
    }

    /// 无结果时的第二行（原型 `searchBody` 逐字）。
    public static let noResultsHint = "换个关键词，或切换上方范围试试"

    /// 结果不完整时的说明行。
    ///
    /// 与 `ExploreBoardNotice.incompleteResults` **刻意不同的一句**：
    /// 那边给出口是"下拉刷新重试"（探索页有下拉刷新），搜索页没有下拉刷新，
    /// 出口是重新输入或切范围 ⇒ 这里只写"请重试"。
    /// 两处共用同一句会让搜索页指向一个它没有的手势。
    public static let incompleteResults = "结果可能不完整（GitHub 计算超时）· 请重试"
}

/// 空闲态的「热门关键词」词表（决策 #45、PRD §4.2）。
///
/// ## 为什么是**内置静态**的
///
/// GitHub **没有任何**接口能给出"热门搜索词"（§16 已核实项）。
/// 而 PRD §4.2 要求空闲态展示这一块 ⇒ 只能内置一份，等将来有真数据源再替换
/// （决策 #45，2026-10-07 用户拍板）。
///
/// ## ⚠️ 这 5 个词**逐字取自原型的演示数据**
///
/// ```js
/// const SEARCH_HOT = ['swiftui','markdown','设计令牌','oauth','折叠屏'];
/// ```
/// 按事实优先级（原型 > TECH_SPEC > PRD）照抄，**不自行替换**。
///
/// 但有两个词值得注意，已报给用户待其决定是否替换（**只在这里出现一次，改就改这一处**）：
/// `设计令牌` 与 `折叠屏` 是**本项目的内部概念**，不是 GitHub 上的通用热词；
/// 其中「折叠屏」还与 PRD §1「纯 iPhone，本期不做折叠屏 / iPad」的定位相冲。
public enum SearchHotKeywords {

    /// 空闲态展示的标签，**顺序即展示顺序**（原型按数组顺序渲染）。
    public static let all = ["swiftui", "markdown", "设计令牌", "oauth", "折叠屏"]
}
