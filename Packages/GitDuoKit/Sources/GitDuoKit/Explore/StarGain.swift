import Foundation

/// 新星榜的「新增 Star」计算与排序（TECH_SPEC §9.10.2 / 决策 #36）。
///
/// 这张表把三件事钉在一处，因为它们必须**同时**成立才不会出现"数字好看但含义是假的"：
///
/// | 情形 | 展示 | 排序 |
/// |---|---|---|
/// | 有基线 | `+812 本周`（周增量 × 窗口系数） | 按窗口增量降序 |
/// | 无基线 | **不显示增幅角标**（只留 `🆕 08-05 创建`） | 保持服务端顺序（总 Star 降序） |
///
/// ## 为什么无基线时"不显示"而不是"显示总 Star"
///
/// 决策 #36 的初稿写的是"回退显示总 Star"，**实现时改掉了**：
/// `PRD §4.12` 把趋势卡片内容定义为「主语言 + **Star 总数** + 榜单指标」三项并列，
/// 原型里也确实并排着两个角标。若指标位再回退显示总 Star，
/// 同一张卡上会出现**两个一模一样的数字**。总 Star 交给**既有的 Star 角标**承担即可，
/// 需求（不造数、首屏不留破折号）同样满足。
///
/// ## 为什么排序不能用一个键
///
/// 增量（每周 +812）与总量（2,341 星）**单位不同**，混进一个排序键会得出
/// 「每周 +5 的 3 星仓库压过 20 万星的成熟仓库」这种明显错误的顺序。
/// 故分两组：**有基线的一组按增量降序排在前，无基线的一组保持服务端原序接在后**。
/// 首次运行（全部无基线）⇒ 全序 = 服务端总 Star 序，正是决策 #36 的"回退按总 Star"。
public enum StarGain {

    /// 没有日期范围时的窗口词（原型 `RANGE_LABEL[range] || '近期'`）。`+812 近期`。
    public static let unspecifiedWindowLabel = "近期"

    // MARK: - 数值

    /// 窗口内增量 = 周增量 × 系数，**至少 1**。
    ///
    /// 为什么下限是 1：`今天` 的系数是 `1/7`，一个小仓库的周增量 3 会算成 0，
    /// 角标就成了 `+0 今日` —— 一个正在涨的仓库显示"+0"比不显示更让人困惑。
    /// 原型同样有这层 `Math.max(1, …)`。
    public static func windowDelta(weeklyDelta: Int, range: ExploreDateRange?) -> Int {
        let scale = range?.scaleFactor ?? 1
        return max(1, Int((Double(weeklyDelta) * scale).rounded()))
    }

    // MARK: - 文案

    /// 角标文案；**`weeklyDelta` 为 `nil` 时返回 `nil`** —— 调用方据此**不渲染该角标**。
    public static func badge(weeklyDelta: Int?, range: ExploreDateRange?) -> String? {
        guard let weeklyDelta else { return nil }
        let window = range?.badgeLabel ?? unspecifiedWindowLabel
        return "+\(windowDelta(weeklyDelta: weeklyDelta, range: range)) \(window)"
    }

    // MARK: - 排序

    /// 按「有基线优先、组内各自降序」重排（决策 #36）。
    ///
    /// - Parameters:
    ///   - delta: 该行的**周增量**；`nil` = 还没有基线。
    ///   - totalStars: 该行的总 Star（只在**回退**时用，即不参与本函数排序，仅作语义说明）。
    /// - Returns: 重排后的数组。
    ///
    /// ⚠️ `totalStars` **不参与排序键** —— 无基线行保持传入顺序（服务端 `sort=stars` 已经
    /// 是总 Star 降序）。把它并进排序键就会重新引入"混单位"的问题，见类型注释。
    public static func rank<T>(
        _ rows: [T],
        delta: (T) -> Int?,
        range: ExploreDateRange?
    ) -> [T] {
        // 带上原始下标：Swift 的 `sorted(by:)` **不保证稳定**，靠下标做平手裁决
        // 才能保证同一份输入永远得到同一份输出（否则列表会在两次刷新之间无理由地抖动）。
        let indexed = Array(rows.enumerated())

        let scored = indexed
            .compactMap { offset, row -> (offset: Int, row: T, key: Int)? in
                guard let weekly = delta(row) else { return nil }
                return (offset, row, windowDelta(weeklyDelta: weekly, range: range))
            }
            .sorted { lhs, rhs in
                lhs.key == rhs.key ? lhs.offset < rhs.offset : lhs.key > rhs.key
            }
            .map(\.row)

        // `filter` 保序 ⇒ 无基线的一组原样保持服务端顺序。
        let unscored = indexed.filter { delta($0.element) == nil }.map(\.element)

        return scored + unscored
    }
}
