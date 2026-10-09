import SwiftUI

/// 贡献热力图 —— 「我的」页那张 `1,024 次贡献 / 2026 年` + 年份切换器 + 一整年的方格图
/// （PRD §4.17 第 3 条、TECH_SPEC §9.14、决策 #74）。
///
/// ```css
/// .heatmap{background:var(--card);border:1px solid var(--border-soft);
///          border-radius:14px;padding:14px;margin:12px 0}
/// .hm-grid{display:grid;grid-auto-flow:column;grid-template-rows:repeat(7,11px);
///          gap:2.5px;overflow-x:auto}
/// .hm-cell{width:11px;height:11px;border-radius:2.5px;background:#ebedf0}
/// ```
///
/// ## 它只收一个整数矩阵（判据 #43）
///
/// `levels[c][r]` 是第 `c` 列第 `r` 行那一格的档位：`nil` = **补位**（那格里没有日子），
/// `0...4` = 档位。这个形状是领域包 `ContributionGrid.levelMatrix` 的**逐字复制** ——
/// **不是**新约定，是同一个约定在两边的名字。
///
/// ⚠️ 本包**不认识** `ContributionGrid` / `ContributionDay` / `ContributionLevel`
/// （依赖铁律：设计包不依赖领域包），所以跨包只走基础类型：矩阵是 `[[Int?]]`、
/// 月份表头是 `[MonthMark]`（列号 + 文案，文案由调用方从 `ProfileCopy` 取）、
/// 年份是 `HeatmapYear`（数字 + 文案）。
/// 「第几档」与「画哪个颜色」的对应关系见 `Theme.Palette.heatmapLevels` 的抬头。
///
/// ## ⚠️⚠️ 格子**固定 11pt**，放不下就横向滑动（2026-10-09 改，用户走查第 2 条）
///
/// 原型那条 CSS 就是这两件事：`.hm-cell{width:11px;height:11px;gap:2.5px}` +
/// `.hm-grid{overflow-x:auto}`。**两处都是回归原型**。
///
/// 本组件此前写的是相反的口径（"格子边长由可用宽度反算、刻意不做横向滚动"，
/// 见 `TECH_SPEC §9.14` 改前的末段），那是决策 #74 落地时自己换的，理由是
/// "53 列滚动起来只能看见半年，会让「过去一年」那句变成假话"。**那句话现在没有了**
/// （卡片右上改成年份切换器，写的是 `{年份} 年`）⇒ 那个理由随之消失，而用户的观感
/// （格子太小、要能滑）成了唯一还站着的意见。
///
/// ⚠️ **"不许写死像素"那条铁律仍然成立**，只是对象换了：它的原意是"不许假定
/// iPhone 只有一种宽度"（不许用 `UIScreen.main`）。这里没有任何一处读屏幕尺寸 ——
/// 放不下由滚动接管，11pt 是**原型的视觉值**。整张图的内容宽 =
/// `53 × 11 + 52 × 2.5 ≈ 713pt`（iPhone 17 Pro 上卡片可用宽约 342pt ⇒ 约 2.1 屏）。
///
/// ## ⚠️ 默认停在**最右端**
///
/// PRD §4.17 的"默认停在当前月份附近"。窗口的结尾要么是"今天"（当前年），要么是
/// 该年 12/31 ⇒ **最右永远是最新那一段**，所以 `.defaultScrollAnchor(.trailing)`
/// 就是那句话的实现，不需要按月份算偏移量。
///
/// ## 零贡献照常画（`levels` 非空、全是最浅档）
///
/// PRD §4.17 明写「一年零贡献时**也照常画一张全空的图** + `0 次贡献`，不给空态」。
/// 那种情形 `levels` 有 53 列、每一格都是 `0` ⇒ 画出来是一张**全最浅色的图**，
/// 与"没取到"（整个卡片换成一行失败提示）在画面上完全不同。
///
/// `levels` 真的**是空数组**时（`weeks: []` 这种畸形响应）只画头部那行字、
/// 跳过表头与网格 —— 而不是画一个零宽或零高的东西（那会得到一条细线，看着像渲染坏了）。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct ContributionHeatmap: View {

    /// 一列有几格 —— 与 `ContributionGrid.rowCount` 同一个数（7，周日到周六）。
    ///
    /// ⚠️ 这里**必须**是 7：`grid-template-rows:repeat(7,…)` 就是原型的那条规则。
    /// 跨包的两处声明同样连不起来（见 `heatmapLevels` 抬头那条说明）。
    ///
    /// ⚠️ **`nonisolated` 不是装饰**：本类型是 `View` ⇒ 隐式 `@MainActor`，
    /// 而下面那几个"算坐标"的纯函数是 `nonisolated` 的（要在单测里直接调）。
    /// 漏了这个关键字不会编译不过，只会得到一串
    /// `main actor-isolated static property 'rowCount' can not be referenced from a nonisolated context`
    /// 的**警告** —— 而增量构建会把它吞掉，只有强制全量重编才看得见。
    public nonisolated static let rowCount = 7

    /// 一格边长（pt）—— 原型 `.hm-cell{width:11px;height:11px}` 的**原值**。
    ///
    /// ⚠️ 这个数字**直接决定要不要横向滚动**：`53 × 11 + 52 × 2.5 ≈ 713pt` 在任何
    /// iPhone 上都放不下 ⇒ 一定滚得动。改到 6 以下就会变成"能放下但看不清"，
    /// 而那时滚动条空着、用户也说不清哪里不对。
    public nonisolated static let cellSize: CGFloat = 11

    /// 间距与圆角**相对格子边长**的比例 —— 原型 `2.5px / 11px`。
    ///
    /// 原型把间距和圆角都写成 `2.5px`（`gap:2.5px` 与 `border-radius:2.5px`），
    /// 而格子是 `11px` ⇒ 一个比例同时管这两件事。
    ///
    /// ⚠️ `nonisolated` 的理由同 `rowCount`（上面那条）。
    nonisolated static let unitRatio: CGFloat = 2.5 / 11

    /// 月份表头那一行的高度（pt）。
    ///
    /// `Theme.Font.caption`（11pt）的行高约 13pt ⇒ 14 给一点余量。
    /// ⚠️ 它**不参与** `unitRatio`：那是格子内部的几何，这是两个区块之间的间距。
    public nonisolated static let monthRowHeight: CGFloat = 14

    /// 间距（pt）= 原型 `2.5px`。
    public nonisolated static var gap: CGFloat { cellSize * unitRatio }

    /// 一格的**步进**（边长 + 间距）—— 列坐标与月份标签共用它，见 `xOffset(column:)`。
    public nonisolated static var step: CGFloat { cellSize + gap }

    /// 整张网格的高度（pt）：7 格 + 6 个间距 = 92。
    public nonisolated static var gridHeight: CGFloat {
        CGFloat(rowCount) * cellSize + CGFloat(rowCount - 1) * gap
    }

    /// x 轴一个月份标签（列号 + 文案）。
    ///
    /// ⚠️ 文案是**调用方给的**：本包不写 `1月` 这样的字 —— 那句话是文案，归领域层
    /// 管（`ProfileCopy.monthLabel(_:)`）。设计包里写死一句等于把文案漏出铁律
    /// （同下面那条"不给它编一句『贡献热力图』"）。
    public struct MonthMark: Identifiable, Hashable, Sendable {

        /// 列下标（0 = 最左那一周）。
        public let column: Int

        /// 挂在那一列上的字（`1月`）。
        public let title: String

        public var id: Int { column }

        public init(column: Int, title: String) {
            self.column = column
            self.title = title
        }
    }

    /// 列 → 格子档位（`nil` = 补位，`0...4` = 档位）。形状同 `ContributionGrid.levelMatrix`。
    public let levels: [[Int?]]

    /// 左上角那个数（`1,024 次贡献`）。**由调用方算好** —— 千分位与 `次贡献` 那两个字
    /// 都是领域层 `ProfileCopy.contributionCount(_:)` 的事（文案是契约）。
    public let totalText: String

    /// 网格上方那一排月份标签（领域层 `ContributionGrid.monthLabels` 给列号，
    /// `ProfileCopy.monthLabel(_:)` 给字）。
    public let monthMarks: [MonthMark]

    /// 年份切换器上显示的字（`2026 年`）。
    public let yearTitle: String

    /// 年份切换器里的选项（顺序 = 菜单顺序）。
    public let yearOptions: [HeatmapYear]

    /// 当前选中的年份（`HeatmapYear.year`）。
    ///
    /// ⚠️ 它**必须与 `totalText` 来自同一份数据**：切换年份时总数与年份一起换，
    /// 否则会出现"写着 2025、画的是 2026"（`ProfileOverview.year` 的说明）。
    public let selectedYear: Int

    /// 切换器的读屏标签（`ProfileCopy.heatmapYearAccessibilityLabel(year:)`）。
    public let yearAccessibilityLabel: String

    /// 选了某一年（传回 `HeatmapYear.year`）。
    public let onSelectYear: (Int) -> Void

    public init(
        levels: [[Int?]],
        totalText: String,
        monthMarks: [MonthMark],
        yearTitle: String,
        yearOptions: [HeatmapYear],
        selectedYear: Int,
        yearAccessibilityLabel: String,
        onSelectYear: @escaping (Int) -> Void
    ) {
        self.levels = levels
        self.totalText = totalText
        self.monthMarks = monthMarks
        self.yearTitle = yearTitle
        self.yearOptions = yearOptions
        self.selectedYear = selectedYear
        self.yearAccessibilityLabel = yearAccessibilityLabel
        self.onSelectYear = onSelectYear
    }

    public var body: some View {
        CardBox(vertical: 14) {
            VStack(alignment: .leading, spacing: 0) {
                HeatmapHeader(
                    totalText: totalText,
                    yearTitle: yearTitle,
                    yearOptions: yearOptions,
                    selectedYear: selectedYear,
                    yearAccessibilityLabel: yearAccessibilityLabel,
                    onSelectYear: onSelectYear
                )

                // 网格真的是空的（畸形响应）⇒ 只留头部那行字。
                if !levels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            monthRow
                            grid
                        }
                        .frame(width: contentWidth, alignment: .leading)
                    }
                    // PRD §4.17：「默认停在当前月份附近」。窗口结尾是"今天"或该年 12/31
                    // ⇒ 最右端就是最新那一段，见类型说明。
                    .defaultScrollAnchor(.trailing)
                    // 371 个格子逐个念给读屏听没有意义（也没有逐格提示语可给），
                    // 而"多少次贡献 + 哪一年"那行本来就是可读文本（还在切换器上）
                    // ⇒ 整块图（含月份表头）对读屏隐藏。
                    // ⚠️ **不给它编一句 `贡献热力图` 这样的话**：那句话是文案，
                    // 归领域层管（`ProfileCopy`），设计包里写死一句等于把文案漏出铁律。
                    // ⚠️ `.accessibilityHidden` 只挂在这个 `ScrollView` 上，
                    // **不能挂到 `CardBox` 上** —— 那样会把年份切换器一起藏掉。
                    .accessibilityHidden(true)
                }
            }
        }
    }

    /// 月份表头：每个标签按它那一列的 x 坐标摆。
    ///
    /// ⚠️ 用 `ZStack` + `offset` 而不是 `HStack` + 占位：月份之间的列数不等（4–5 列），
    /// 用 `HStack` 就得给每一列配一个宽度可变的占位视图，而那是 53 个多余视图。
    /// `offset` 不影响布局，而这里的布局是固定尺寸（表头宽度 = 网格宽度），
    /// 所以"不影响布局"恰好是我们要的。
    private var monthRow: some View {
        ZStack(alignment: .topLeading) {
            ForEach(monthMarks) { mark in
                Text(mark.title)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    // 表头行高度固定、文字不许被压成两行。
                    .fixedSize()
                    .offset(x: Self.xOffset(column: mark.column))
            }
        }
        .frame(width: contentWidth, height: Self.monthRowHeight, alignment: .topLeading)
    }

    private var grid: some View {
        Canvas { context, _ in
            Self.draw(levels: levels, in: &context)
        }
        .frame(width: contentWidth, height: Self.gridHeight)
    }

    /// 整张图的宽度 = `n` 格 + `n−1` 个间距。
    private var contentWidth: CGFloat { Self.contentWidth(columnCount: levels.count) }

    // MARK: - 纯函数（可单测）

    /// `count` 列时整个网格的宽度（pt）。
    ///
    /// ⚠️ 写成 `count * step` 会多算一个间距（最后一列右边不该有间距）——
    /// 53 列上那是 2.5pt 的差，看不出来，但它会让"内容宽"与"最后一格的右边缘"
    /// 悄悄不一致，而横向滚动的末端位置正是按内容宽算的。
    public nonisolated static func contentWidth(columnCount: Int) -> CGFloat {
        guard columnCount > 0 else { return 0 }
        return CGFloat(columnCount) * cellSize + CGFloat(columnCount - 1) * gap
    }

    /// 第 `column` 列的 x 坐标（pt）—— 网格与月份表头**共用这一个**。
    ///
    /// ⚠️ 两处各算一遍是"标签逐列漂移"的唯一成因（漂一点点，几十列之后偏一格）。
    public nonisolated static func xOffset(column: Int) -> CGFloat {
        guard column > 0 else { return 0 }
        return CGFloat(column) * step
    }

    /// 某一档取哪个颜色。
    ///
    /// ⚠️ **越界夹取**而不是回落到"无贡献"：服务端哪天多一档（`5`），
    /// 夹到最深那一档至少还看得出"这天有贡献"；回落到 0 会让那些天变成空白
    /// ——正是 `ContributionLevel.translate` 抬头里说的那个"看不出是数据问题还是本来就这样"。
    internal nonisolated static func color(for level: Int) -> Color {
        let palette = Theme.Palette.heatmapLevels
        guard !palette.isEmpty else { return .clear }
        let index = min(max(level, 0), palette.count - 1)
        return palette[index]
    }

    /// 真正画格子 —— 一个 `Canvas` 画 371 个圆角方块。
    ///
    /// 列数多的时候，`VStack` + 371 个 `Rectangle` 也能画出来，但那意味着
    /// 一次布局要过 371 个视图；而且每一格都要自己算一遍坐标（算错一处就是
    /// 一整列斜着）。画在一个 `Canvas` 里，坐标只有下面这一行乘法。
    ///
    /// ⚠️ 尺寸**不再来自 `size`**（那是"按可用宽度反算"时代的参数）：格子固定 11pt，
    /// 所以 `Canvas` 的 frame 与画出来的内容必然一致 —— 反过来，如果哪天有人
    /// 把 `.frame` 去掉、让它按可用宽度铺，格子会被拉伸而**代码里看不出任何异常**。
    private nonisolated static func draw(levels: [[Int?]], in context: inout GraphicsContext) {
        let radius = cellSize * unitRatio

        for (column, cells) in levels.enumerated() {
            // 列长理论上恒为 `rowCount`（领域包 `ContributionGrid.layout` 保证），
            // 但本包看不到那个保证 ⇒ 超出的部分不画（画出去会是一条越界的色带）。
            for (row, level) in cells.enumerated() where row < rowCount {
                // `nil` = 补位：**不画**。头尾两周不足 7 天时空出来的那几格
                // 就该露出卡片白底 —— 画成最浅色会让整张图看起来从周一就开始了。
                guard let level else { continue }
                let rect = CGRect(
                    x: xOffset(column: column),
                    y: CGFloat(row) * step,
                    width: cellSize,
                    height: cellSize
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: radius),
                    with: .color(color(for: level))
                )
            }
        }
    }
}

#Preview {
    // 造一张 53 列 × 7 行、像真的一样的图：中间偏浅、有几段深色。
    let levels: [[Int?]] = (0..<53).map { column in
        (0..<ContributionHeatmap.rowCount).map { row -> Int? in
            // 第一列前面空两格，模拟"窗口不从周日开始"。
            if column == 0 && row < 2 { return nil }
            let seed = (column &* 7 &+ row) % 11
            return seed < 5 ? 0 : (seed < 8 ? 1 : (seed < 10 ? 2 : 4))
        }
    }

    // 月份表头：约每 4–5 列一个月（真数据由 `ContributionGrid.monthLabels` 算）。
    let marks = (0..<12).map {
        ContributionHeatmap.MonthMark(column: $0 * 4 + 1, title: "\($0 + 1)月")
    }
    let years = [
        HeatmapYear(year: 2026, title: "2026 年"),
        HeatmapYear(year: 2025, title: "2025 年"),
        HeatmapYear(year: 2024, title: "2024 年"),
    ]

    return VStack(spacing: Theme.Spacing.m) {
        ContributionHeatmap(
            levels: levels,
            totalText: "1,024 次贡献",
            monthMarks: marks,
            yearTitle: "2026 年",
            yearOptions: years,
            selectedYear: 2026,
            yearAccessibilityLabel: "切换年份，当前 2026 年",
            onSelectYear: { _ in }
        )

        // 零贡献：53 列全是最浅档 —— 照常画一张图，不给空态。
        ContributionHeatmap(
            levels: Array(repeating: Array(repeating: 0, count: 7), count: 53),
            totalText: "0 次贡献",
            monthMarks: marks,
            yearTitle: "2026 年",
            yearOptions: years,
            selectedYear: 2026,
            yearAccessibilityLabel: "切换年份，当前 2026 年",
            onSelectYear: { _ in }
        )

        // 畸形响应：一列都没有 ⇒ 只剩头部那行字（切换器仍在）。
        ContributionHeatmap(
            levels: [],
            totalText: "0 次贡献",
            monthMarks: [],
            yearTitle: "2026 年",
            yearOptions: years,
            selectedYear: 2026,
            yearAccessibilityLabel: "切换年份，当前 2026 年",
            onSelectYear: { _ in }
        )
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
