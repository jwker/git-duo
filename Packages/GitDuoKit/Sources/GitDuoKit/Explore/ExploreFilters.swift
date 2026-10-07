import Foundation

/// 探索页的日期范围（PRD §3.12 / §4.12）。
///
/// 三个取值全部**逐字取自原型** `scripts/09-explore.js`：
/// `RANGE_OPTS = ['今天','本周','本月']`（弹层行）·
/// `RANGE_LABEL = {'今天':'今日','本周':'本周','本月':'本月'}`（角标窗口词）·
/// `{'今天':1440,'本周':10080,'本月':43200}`（时间窗，分钟）。
public enum ExploreDateRange: String, Sendable, Hashable, CaseIterable, Identifiable {

    case today
    case thisWeek
    case thisMonth

    public var id: String { rawValue }

    /// 筛选弹层里的行文案。
    public var title: String {
        switch self {
        case .today: "今天"
        case .thisWeek: "本周"
        case .thisMonth: "本月"
        }
    }

    /// 角标里的窗口词 —— ⚠️ 与 `title` **有意不同**：`今天` 在角标里写作 `今日`
    /// （`+812 今日` 比 `+812 今天` 更像"一个窗口的量"）。原型就是这么分的，别顺手合并。
    public var badgeLabel: String {
        switch self {
        case .today: "今日"
        case .thisWeek: "本周"
        case .thisMonth: "本月"
        }
    }

    /// 时间窗长度。活跃榜用它算出 `pushed:` 限定符的起点（§9.10.1）。
    public var window: TimeInterval {
        switch self {
        case .today: 86_400          // 1440 分钟
        case .thisWeek: 604_800      // 10080 分钟
        case .thisMonth: 2_592_000   // 43200 分钟
        }
    }

    /// 星增幅的换算系数（PRD §4.12：今天 ≈ 周值 × 1/7、本周 × 1、本月 × 4.3）。
    ///
    /// ⚠️ 它乘的是**窗口增量**，不是总 Star —— 见 `StarGain` 与决策 #36。
    public var scaleFactor: Double {
        switch self {
        case .today: 1.0 / 7.0
        case .thisWeek: 1
        case .thisMonth: 4.3
        }
    }
}

/// 两个筛选项的类别（原型 `FILTER_META`）。
public enum ExploreFilterKind: String, Sendable, Hashable, CaseIterable, Identifiable {

    case range
    case language

    public var id: String { rawValue }

    /// 弹层标题**也是 toast 前缀**（原型：`${meta.title}：${val}`）。
    public var title: String {
        switch self {
        case .range: "日期范围"
        case .language: "编程语言"
        }
    }

    /// 未选时 chip 上的占位文案（原型 `meta.blank`）。
    public var blankLabel: String {
        switch self {
        case .range: "日期"
        case .language: "语言"
        }
    }
}

/// 一次筛选操作的结果 —— 状态机决定，UI 只负责反映（TECH_SPEC §9.10.3）。
///
/// **为什么要把 toast 文案也放进领域层**：这两种提示是"再点当前项 = 取消"这条规则的
/// **唯一可见证据**，而 harness 正是靠它断言的（`harness.js:335` 断言出现 `已取消`）。
/// 文案散在 View 里就没人守得住。
public enum ExploreFilterChange: Equatable, Sendable {

    /// 选中了某项：`编程语言：Swift`
    case picked(ExploreFilterKind, String)
    /// 再点当前项 = 取消，回到「全部」：`编程语言：已取消，显示全部`
    case cancelled(ExploreFilterKind)

    public var toastText: String {
        switch self {
        case let .picked(kind, value): "\(kind.title)：\(value)"
        case let .cancelled(kind): "\(kind.title)：已取消，显示全部"
        }
    }
}

/// 探索页的筛选状态（PRD §3.12 / §4.12）。
///
/// 语义（§9.10.3）：**不选 = 全部**，**再点当前选中项 = 取消**。
/// 两个筛选**互相独立** —— 切榜单不影响已选筛选项（PRD §4.12）。
public struct ExploreFilters: Sendable, Hashable {

    /// 日期范围。`nil` = 全部。
    public var range: ExploreDateRange?

    /// 编程语言。`nil` = 全部。
    public var language: String?

    public init(range: ExploreDateRange?, language: String?) {
        self.range = range
        self.language = language
    }

    /// 初始状态：日期范围 **本周**、语言**不选**（PRD §3.12 明写；原型 `EXPLORE_FILTERS = { range:'本周', lang:'' }`）。
    public static let `default` = ExploreFilters(range: .thisWeek, language: nil)

    /// 语言选项 —— PRD §3.12 固定 5 项，**不是**从榜单结果里现算的。
    ///
    /// ⚠️ 弹层里**没有「全部」这一行**：取消靠"再点一次当前项"（`harness.js:329` 断言无此选项）。
    public static let languageOptions = ["Swift", "Rust", "TypeScript", "Python", "Go"]

    /// 日期 chip 文案（未选 = 占位 `日期`）。
    public var rangeChipLabel: String { range?.title ?? ExploreFilterKind.range.blankLabel }

    /// 语言 chip 文案（未选 = 占位 `语言`）。
    public var languageChipLabel: String { language ?? ExploreFilterKind.language.blankLabel }

    /// chip 是否高亮（原型 `class="fchip ${val?'on':''}"`）。
    public func isHighlighted(_ kind: ExploreFilterKind) -> Bool {
        switch kind {
        case .range: range != nil
        case .language: language != nil
        }
    }

    /// 该类别当前选中的值（用于弹层里的 ✓ 与文案）。
    public func selectedValue(_ kind: ExploreFilterKind) -> String? {
        switch kind {
        case .range: range?.title
        case .language: language
        }
    }

    /// 选中某个日期范围；**再点当前项即取消**。
    public mutating func select(range value: ExploreDateRange) -> ExploreFilterChange {
        guard range != value else {
            range = nil
            return .cancelled(.range)
        }
        range = value
        return .picked(.range, value.title)
    }

    /// 选中某种语言；**再点当前项即取消**。
    public mutating func select(language value: String) -> ExploreFilterChange {
        guard language != value else {
            language = nil
            return .cancelled(.language)
        }
        language = value
        return .picked(.language, value)
    }
}

/// 榜单结果的缓存键 ——（榜单 · 日期范围 · 编程语言）。
///
/// 依据：PRD §4.12「榜单与筛选按『榜单 · 日期范围 · 编程语言』组合复用缓存，来回切换直接命中」
/// 与决策 #37 / TECH_SPEC §9.10.5。**三个维度缺一不可**：少一个都会让"切回来却看到上一组筛选的
/// 结果"这种事发生 —— 那比不缓存更糟。
public struct ExploreCacheKey: Sendable, Hashable {

    public let board: TrendingBoard
    public let range: ExploreDateRange?
    public let language: String?

    public init(board: TrendingBoard, filters: ExploreFilters) {
        self.board = board
        self.range = filters.range
        self.language = filters.language
    }
}
