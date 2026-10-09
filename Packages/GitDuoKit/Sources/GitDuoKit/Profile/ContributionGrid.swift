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

/// 一整年的热力图网格（TECH_SPEC §9.14、决策 #74）。
///
/// ## 形状：**列 = 周，行 = 一周里的第几天**
///
/// `columns[c][r]` 是第 `c` 列第 `r` 行的那一格；`nil` = **补位**（那格里没有日子，
/// 出现在头尾那两周 —— 见下）。
///
/// ## ⚠️ 头尾两周可能不足 7 天，所以"补位"是必须的
///
/// 日历的周是**周日对齐**的，而"过去一年"这个窗口不会正好从周日开始、到周六结束
/// ⇒ 第一列前面、最后一列后面会空出几格。**不能按"每周固定 7 格"去铺**，
/// 那会让整张图**整体错位**（而错位的热力图看起来一样正常，只是每一天都不在它该在的位置）。
///
/// ## ⚠️ 列数是**接口给多少画多少**（决策 #74③）
///
/// 原型画死 **40 列**（`12-me.js` 的 `for(let w=0;w<40;w++)`，硬编码演示值）；
/// 接口默认给的是**整整一年（≈53 周）**。这里按接口给的画满 ——
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
