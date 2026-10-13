import Foundation
import GitDuoCore

/// 贡献热力图的一格**深浅档**（TECH_SPEC §9.14、决策 #74②）。
///
/// ## ⚠️ 它照抄服务端给的档位，**不自己按次数划**
///
/// 官方 schema 对 `ContributionCalendarDay.contributionLevel` 的注释是
/// *"Indication of contributions, **relative to other days**. Can be used to indicate
/// which color to represent this day on a calendar."* —— 它是**相对这位用户自己这一年
/// 的分布**算出来的四分位。同一个 `contributionCount` 在两个人身上可以是不同档
/// （一天 5 次贡献，在一年只有 20 次的人那里是最高档，在天天 50 次的人那里是零档）。
/// 我们复现不出这个分布，**自己划档只能得到一张形状不对的图**。
///
/// ## 正好 5 档
///
/// `NONE` + 四个四分位 = 5 个取值。`scale` 把它们映成 `0...4` 的整数给设计层用
/// —— 设计层（`GitDuoDesign`）不认识本类型（它不依赖领域包），
/// 所以"第几档"必须以一个**基础类型**的形式交出去。
public enum ContributionLevel: String, Sendable, Hashable, CaseIterable {

    case none = "NONE"
    case firstQuartile = "FIRST_QUARTILE"
    case secondQuartile = "SECOND_QUARTILE"
    case thirdQuartile = "THIRD_QUARTILE"
    case fourthQuartile = "FOURTH_QUARTILE"

    /// 给设计层用的整数档位（`0` = 无贡献，`4` = 最高）。
    ///
    /// ⚠️ 顺序就是**从浅到深**，设计层的色板按同一个顺序取色 —— 两处各写一套
    /// "哪个 case 对应第几档"必然有一天分叉（表现为"最深的那档画成了浅色"）。
    public var scale: Int {
        switch self {
        case .none: 0
        case .firstQuartile: 1
        case .secondQuartile: 2
        case .thirdQuartile: 3
        case .fourthQuartile: 4
        }
    }

    /// 档位的数量 —— 设计层要按它准备色板，写死 `5` 会让"哪天多一档"变成一张越界的图。
    public static let scaleCount = 5

    /// 把服务端给的字符串翻译成档位。
    ///
    /// ## ⚠️ 认不出的取值按"**有没有贡献**"兜底，而不是一律当成无贡献
    ///
    /// `contributionLevel` 声明成 `String` 而不是枚举（见 `ContributionCalendarDayDTO`），
    /// 所以"认不出"是一个真实存在的分支（GitHub 哪天多一档）。
    /// 两种兜底的方向不对称：
    /// - 一律当 `.none` ⇒ 图上那些天变成空白 —— 而它们**确实有贡献**，
    ///   于是"这张图少了东西"这件事**看不出是数据问题还是本来就这样**；
    /// - 按有无贡献二选一 ⇒ 那些天画成**最浅的有色档**（`.firstQuartile`），
    ///   图的形状基本对，代价只是深浅不准。
    ///
    /// 后者把"档位不准"和"数据缺了"分开，前者把它们混成一件事。选后者。
    public static func translate(rawValue raw: String, contributionCount: Int) -> ContributionLevel {
        if let level = ContributionLevel(rawValue: raw) { return level }
        return contributionCount > 0 ? .firstQuartile : .none
    }
}

/// 热力图上的一天（TECH_SPEC §9.14）。
public struct ContributionDay: Sendable, Hashable, Identifiable {
    /// 那一天，**原样保留服务端给的 `yyyy-MM-dd` 字符串**。
    ///
    /// ⚠️ 不转 `Date`：这个值不带时区，而转成 `Date` 就必须**替服务端选一个时区**
    /// —— 选错的表现是某些时区下整体偏移一天，而图上看起来完全正常。
    /// 界面上当前没有"某一天是哪天"的用法（连 tooltip 都没有），所以没必要承担它。
    public let date: String

    /// 这一天有多少次贡献。
    ///
    /// ⚠️ 它**不决定深浅**（深浅看 `level`），只用于读屏与排查。
    public let count: Int

    public let level: ContributionLevel

    public var id: String { date }

    public init(date: String, count: Int, level: ContributionLevel) {
        self.date = date
        self.count = count
        self.level = level
    }
}

/// x 轴上一个月份标签**该挂在哪一列**（2026-10-09 加）。
///
/// ⚠️ 它只有**事实**（第几列、几月），没有一个字的文案 —— "挂上去写什么"
/// 由 `ProfileCopy.monthLabel(_:)` 决定（文案是契约，见 `ContributionGrid.monthLabels`）。
public struct MonthLabel: Sendable, Hashable, Identifiable {

    /// 列下标（0 = 最左那一周）。
    public let column: Int

    /// 月份（`1...12`）。
    public let month: Int

    public var id: Int { column }

    public init(column: Int, month: Int) {
        self.column = column
        self.month = month
    }
}

/// 一整年的热力图网格（TECH_SPEC §9.14、决策 #74）。
///
/// ## 形状：**列 = 周，行 = 一周里的第几天**
///
/// `columns[c][r]` 是第 `c` 列第 `r` 行的那一格；`nil` = **补位**（那格里没有日子，
/// 出现在头尾那两周 —— 见下）。
///
/// ## ⚠️ 头尾两周可能不足 7 天，所以"补位"是必须的
///
/// 日历的周是**周日对齐**的，而窗口（自然年，见 `ContributionYear`）不会正好从周日开始、
/// 到周六结束 ⇒ 第一列前面、最后一列后面会空出几格。**不能按"每周固定 7 格"去铺**，
/// 那会让整张图**整体错位**（而错位的热力图看起来一样正常，只是每一天都不在它该在的位置）。
///
/// ## ⚠️ 列数是**接口给多少画多少**（决策 #74③）
///
/// 原型画死 **40 列**（`12-me.js` 的 `for(let w=0;w<40;w++)`，硬编码演示值）；
/// 而我们给的窗口（自然年）是**整整一年（≈53 周）**。这里按接口给的画满 ——
/// 已登记为**有意偏差第 38 条**（`REVIEW-CHECKLIST §6`）。
///
/// ## 零贡献是**正常值**，不是空态
///
/// 新账号 / 一年没动过：`totalContributions == 0`，而网格照常有 53 列、全是最浅档。
/// PRD §4.17 明写「一年零贡献时**也照常画一张全空的图** + `0 次贡献`，不给空态」
/// —— "零贡献"是一个有意义的事实，与"没取到"（那一整个分区降级）不是一回事。
public struct ContributionGrid: Sendable, Hashable {

    /// 一行有几天 —— 周日到周六。
    public static let rowCount = 7

    /// 列（周）→ 7 个格子（`nil` = 补位）。
    public let columns: [[ContributionDay?]]

    /// 这一年贡献总数（**服务端给的那个数**，不是把格子加起来的）。
    ///
    /// ⚠️ 别用格子求和去"验算"它：那样得到的数会随"这次取回了多少格"而变，
    /// 而这两者本该是同一件事 —— 服务端已经算好了，用它。
    public let totalContributions: Int

    /// 全部日子，**服务端给的顺序**（未补位、未分组）。
    public let days: [ContributionDay]

    public var columnCount: Int { columns.count }

    /// 实际有日子的格子数（不含补位）。
    public var dayCount: Int { days.count }

    /// 网格是不是空的 —— 即**一格日子都没有**。
    ///
    /// ⚠️ 注意它**不是**"零贡献"：零贡献的一年有 365 个格子，只是都最浅。
    public var isEmpty: Bool { days.isEmpty }

    /// 交给设计层的**纯整数矩阵**：`nil` = 补位，`0...4` = 档位。
    ///
    /// 设计包不认识 `ContributionDay` / `ContributionLevel`（它不依赖领域包），
    /// 所以跨包只传这个。
    public var levelMatrix: [[Int?]] {
        columns.map { column in column.map { $0?.level.scale } }
    }

    /// x 轴月份表头该挂在哪几列上（2026-10-09 加，用户走查第 2 条）。
    ///
    /// ## 规则：**每个月第一次出现的那一列**
    ///
    /// 逐列取"这一列第一个有日子的格"，月份与前一列不同 ⇒ 这一列挂标签。
    /// 于是 1 月只会在第 0 列（窗口从 1/1 开始），此后每个月各挂一次 —— 恰好 12 个。
    ///
    /// ## ⚠️ 这里为什么只给"第几列 + 几月"，不给字符串
    ///
    /// 因为"哪一列该挂"是**事实**（只依赖数据结构），而"挂上去写什么"是**文案**
    /// （`1月` 还是 `Jan`、要不要空格）—— 文案按铁律归 `ProfileCopy`。
    /// 领域层只要把两件事分开，App 层一行 `map` 就把它们合起来。
    ///
    /// ⚠️ **不处理"标签会重叠"**：本机一格 11pt、一个月最少 4 列（≈50pt），
    /// 而 `{n}月` 在 caption 下约 22pt ⇒ 真实数据下撞不上。若哪天格子里程变了、
    /// 或者有人把窗口改成非自然年，这里要补一条"离得太近就跳过"的规则。
    ///
    /// ⚠️ **2026-10-12 补记（用户走查第 60 条）**：上面那条"撞不上"的前提**被现实打过一次脸** ——
    /// 打破它的不是"格子里程变了"，而是**首列混进了一个上一年的 12 月日子**
    /// （服务端按周返回，而窗口起点按 GMT 序列化后落到了 12/31）⇒ 「12月」与「1月」
    /// 只差一列、直接叠上，用户就是这么报回来的。
    /// **修法不是在这里加"离得太近就跳过"**（那会把「12月」整个吞掉，而它本来就
    /// 不该出现在这一年的图上）—— 而是在**上游把那一天裁掉**（`ProfileMapper.grid(_:year:)`）：
    /// 少一天 ⇒ 本规则自然算出「1月」在第 0 列。**本方法一个字没改。**
    public var monthLabels: [MonthLabel] {
        var labels: [MonthLabel] = []
        var previous: Int?

        for (index, column) in columns.enumerated() {
            // 该列第一个有日子的格 —— 头尾两周可能是全补位（`nil`），跳过它们。
            guard let date = column.compactMap({ $0?.date }).first,
                  let month = Self.month(inISODate: date)
            else { continue }

            if month != previous {
                labels.append(MonthLabel(column: index, month: month))
            }
            previous = month
        }
        return labels
    }

    /// 从服务端给的 `yyyy-MM-dd` 里取月份。取不出来 ⇒ `nil`（那一列不挂标签）。
    ///
    /// ⚠️ **不建 `DateFormatter`**：这个字符串不带时区，而"把它变成 `Date` 再取月"
    /// 会引入一次时区解释（`ContributionDay.date` 的抬头讲了为什么本类型一路不碰 `Date`）。
    /// 按 `-` 切开取第二段既没有时区，也不会因为设备日历设置而变。
    static func month(inISODate date: String) -> Int? {
        let parts = date.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let month = Int(parts[1]), (1...12).contains(month) else {
            return nil
        }
        return month
    }

    public init(columns: [[ContributionDay?]], totalContributions: Int, days: [ContributionDay]) {
        self.columns = columns
        self.totalContributions = totalContributions
        self.days = days
    }

    /// 把一串连续的日子铺进 7 行的网格。
    ///
    /// - Parameters:
    ///   - days: 连续的日子，**顺序即时间顺序**。
    ///   - firstRow: 第一天落在第几行（`0` = 周日）。
    ///     由调用方从"服务端给的 `weekday` 相对某个满 7 天的周"算出来（见 `ProfileMapper`）
    ///     —— 本方法**不猜**这个值，因为猜错的表现是整张图上下错位。
    ///
    /// 铺法：从 `firstRow` 起逐格往下走，走到底就换下一列。**只按顺序铺，不按周分组**
    /// —— 那正是"头尾两周不足 7 天"时仍然正确的唯一办法（分组铺会在第一列就错位）。
    public static func layout(days: [ContributionDay], firstRow: Int) -> [[ContributionDay?]] {
        guard !days.isEmpty else { return [] }

        let start = min(max(firstRow, 0), rowCount - 1)
        var columns: [[ContributionDay?]] = [
            Array(repeating: nil, count: rowCount)
        ]
        var row = start

        for day in days {
            columns[columns.count - 1][row] = day
            row += 1
            if row == rowCount {
                row = 0
                columns.append(Array(repeating: nil, count: rowCount))
            }
        }

        // 恰好铺满整列时会多出一个全空的尾列 —— 去掉它。
        // 漏掉这一步的表现是图右边缘多出一条空白列（看着像"下周还没开始"）。
        if let last = columns.last, last.allSatisfy({ $0 == nil }) {
            columns.removeLast()
        }
        return columns
    }
}
