import SwiftUI

/// 贡献热力图 —— 「我的」页那张 `1,024 次贡献 / 过去一年` + 一整年的方格图
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
/// （依赖铁律：设计包不依赖领域包），所以跨包只走这个基础类型。
/// 「第几档」与「画哪个颜色」的对应关系见 `Theme.Palette.heatmapLevels` 的抬头。
///
/// ## ⚠️⚠️ 格子尺寸**由可用宽度算出来**，不许写死
///
/// `TECH_SPEC §9.14` 末段：「53 周 × 7 天 = 371 格，格子边长与间距**必须由可用宽度
/// 算出来**（容器尺寸 / size class），**不许写死像素**」。原型那两处 `11px` / `2.5px`
/// 是**硬编码的演示值**，照抄就等于把"iPhone 只有一种宽度"写进代码。
///
/// 做法：网格只声明**比例**（`aspectRatio(columnCount:)` —— 用一个格子边长为单位
/// 表示整张图该有多宽多高），交给 SwiftUI 按可用宽度铺满；`Canvas` 拿到的
/// `size.width` 就是**真实的可用宽度**，再反算一格多大（`cellSize(forWidth:columnCount:)`）。
///
/// **落地时量过一次（2026-10-09）**：iPhone 17 Pro（402pt 宽）上，
/// 页面左右各 16pt、卡片左右各 14pt ⇒ 可用 **342pt** ⇒ 一格 **5.28pt**、
/// 间距与圆角各 **1.20pt**、整图高 **44.1pt**。
/// 格子很小，但热力图看的是**形状**不是单格数值，而 53 列铺满一屏正好是"一整年"的形状。
///
/// ⚠️ **刻意不做横向滚动**：原型 `.hm-grid{overflow-x:auto}` 在 40 列时就已经溢出
/// （实测 313pt 的可视宽、538pt 的内容宽 ⇒ 一屏只能看见 23 周）。
/// 我们画的是 53 列，若照原型滚动就会**只看见半年** —— 而卡片右边写着「过去一年」，
/// 那句话会变成假话。真要"更大的格子 + 横向滚动"，改一处即可：
/// 把 `cellSize` 的结果夹到下限，并给 `Canvas` 外面套一个 `ScrollView(.horizontal)`。
///
/// ## 零贡献照常画（`levels` 非空、全是最浅档）
///
/// PRD §4.17 明写「一年零贡献时**也照常画一张全空的图** + `0 次贡献`，不给空态」。
/// 那种情形 `levels` 有 53 列、每一格都是 `0` ⇒ 画出来是一张**全最浅色的图**，
/// 与"没取到"（整个卡片换成一行失败提示）在画面上完全不同。
///
/// `levels` 真的**是空数组**时（`weeks: []` 这种畸形响应）只画头部那行字、
/// 跳过网格 —— 而不是画一个零宽或零高的东西（那会得到一条细线，看着像渲染坏了）。
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
    /// 而下面那几个"算尺寸"的纯函数是 `nonisolated` 的（要在单测里直接调）。
    /// 漏了这个关键字不会编译不过，只会得到一串
    /// `main actor-isolated static property 'rowCount' can not be referenced from a nonisolated context`
    /// 的**警告** —— 而增量构建会把它吞掉，只有强制全量重编才看得见。
    public nonisolated static let rowCount = 7

    /// 间距与圆角**相对格子边长**的比例 —— 原型 `2.5px / 11px`。
    ///
    /// 原型把间距和圆角都写成 `2.5px`（`gap:2.5px` 与 `border-radius:2.5px`），
    /// 而格子是 `11px` ⇒ 一个比例同时管这两件事。
    ///
    /// ⚠️ 别把它换算成一个固定的 pt 值：格子在 iPhone 上只有 5.28pt，
    /// 而原型那个 `2.5px` 是在 11px 的格子上量的 —— 写死会让小格子看起来像"糊在一起"。
    ///
    /// ⚠️ `nonisolated` 的理由同 `rowCount`（上面那条）。
    nonisolated static let unitRatio: CGFloat = 2.5 / 11

    /// 列 → 格子档位（`nil` = 补位，`0...4` = 档位）。形状同 `ContributionGrid.levelMatrix`。
    public let levels: [[Int?]]

    /// 左上角那个数（`1,024 次贡献`）。**由调用方算好** —— 千分位与 `次贡献` 那两个字
    /// 都是领域层 `ProfileCopy.contributionCount(_:)` 的事（文案是契约）。
    public let totalText: String

    /// 右上角那几个字（`过去一年`）。
    public let rangeText: String

    public init(levels: [[Int?]], totalText: String, rangeText: String) {
        self.levels = levels
        self.totalText = totalText
        self.rangeText = rangeText
    }

    public var body: some View {
        CardBox(vertical: 14) {
            VStack(alignment: .leading, spacing: 0) {
                header

                // 网格真的是空的（畸形响应）⇒ 只留头部那行字。
                if !levels.isEmpty {
                    Canvas { context, size in
                        Self.draw(levels: levels, in: &context, size: size)
                    }
                    // 只声明比例，宽度交给 SwiftUI 铺满 —— 见类型说明的"格子尺寸由可用宽度算出来"。
                    .aspectRatio(Self.aspectRatio(columnCount: levels.count), contentMode: .fit)
                    // 371 个格子逐个念给读屏听没有意义（也没有逐格提示语可给），
                    // 而"多少次贡献"那行本来就是可读文本 ⇒ 整块图对读屏隐藏。
                    // ⚠️ **不给它编一句 `贡献热力图` 这样的话**：那句话是文案，
                    // 归领域层管（`ProfileCopy`），设计包里写死一句等于把文案漏出铁律。
                    .accessibilityHidden(true)
                }
            }
        }
    }

    /// 头部那行：左边总数、右边时间范围（原型 `.row{margin-bottom:10px}`）。
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            // 原型 `.t1`（15px/650）被内联改成 `font-size:14px` ⇒
            // 最近的一档是 `rowTitle`（`.subheadline` 15），权重取 `.semibold`（600 ≈ 650）。
            Text(totalText)
                .font(Theme.Font.rowTitle.weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)

            Spacer(minLength: 0)

            // 原型 `.t3`（11.5px / `--text3`）。
            Text(rangeText)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        // 原型 `style="margin-bottom:10px"`（10 不在 4pt 阶里 ⇒ 写原值）。
        .padding(.bottom, 10)
    }

    // MARK: - 纯函数（可单测）

    /// 以一格边长（= 1）为单位，整张图的宽高比。
    ///
    /// 宽 = `n` 格 + `n−1` 个间距；高 = 7 格 + 6 个间距。
    /// `n == 0` 时回落成 `1×1`：调用点已经用 `!levels.isEmpty` 挡在前面，
    /// 这里只是不让"传了一个空矩阵"变成一次除零。
    public nonisolated static func aspectRatio(columnCount: Int) -> CGSize {
        guard columnCount > 0 else { return CGSize(width: 1, height: 1) }
        return CGSize(width: unitLength(count: columnCount), height: unitLength(count: rowCount))
    }

    /// 一格多大（pt）—— **由可用宽度反算**，这是本组件唯一一处尺寸来源。
    ///
    /// 原型那两处 `11px` 之所以不能照抄，见类型说明。
    public nonisolated static func cellSize(forWidth width: CGFloat, columnCount: Int) -> CGFloat {
        guard columnCount > 0 else { return 0 }
        return max(0, width) / unitLength(count: columnCount)
    }

    /// `count` 个格子 + `count−1` 个间距，以一格为单位表示的总长度。
    private nonisolated static func unitLength(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) + CGFloat(count - 1) * unitRatio
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
    private nonisolated static func draw(
        levels: [[Int?]],
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let cell = cellSize(forWidth: size.width, columnCount: levels.count)
        guard cell > 0 else { return }
        let gap = cell * unitRatio
        let step = cell + gap
        let radius = cell * unitRatio

        for (column, cells) in levels.enumerated() {
            // 列长理论上恒为 `rowCount`（领域包 `ContributionGrid.layout` 保证），
            // 但本包看不到那个保证 ⇒ 超出的部分不画（画出去会是一条越界的色带）。
            for (row, level) in cells.enumerated() where row < rowCount {
                // `nil` = 补位：**不画**。头尾两周不足 7 天时空出来的那几格
                // 就该露出卡片白底 —— 画成最浅色会让整张图看起来从周一就开始了。
                guard let level else { continue }
                let rect = CGRect(
                    x: CGFloat(column) * step,
                    y: CGFloat(row) * step,
                    width: cell,
                    height: cell
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

    return VStack(spacing: Theme.Spacing.m) {
        ContributionHeatmap(levels: levels, totalText: "1,024 次贡献", rangeText: "过去一年")

        // 零贡献：53 列全是最浅档 —— 照常画一张图，不给空态。
        ContributionHeatmap(
            levels: Array(repeating: Array(repeating: 0, count: 7), count: 53),
            totalText: "0 次贡献",
            rangeText: "过去一年"
        )

        // 畸形响应：一列都没有 ⇒ 只剩头部那行字。
        ContributionHeatmap(levels: [], totalText: "0 次贡献", rangeText: "过去一年")
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
