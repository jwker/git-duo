import SwiftUI

/// 热力图卡片顶部那一行 —— 左边总数、右边**年份切换器**
/// （PRD §4.17 第 3 条、2026-10-09 加，用户走查第 2 条）。
///
/// ## 为什么把它从 `ContributionHeatmap` 里抽出来
///
/// 因为**失败态也要有它**：某一年的贡献取不到时，卡片里换成一行灰字 + 重试，
/// 而那时用户最需要的东西恰恰是**切回能看的那一年**（或切到别的年份再试）。
/// 把这一行留在 `ContributionHeatmap` 内部、失败态另画一套，会出现两个几乎一样
/// 但对不齐的头部（间距差 2pt、年份字号不一致这类），而且"失败态没有切换器"
/// 这种缺口**只在离线时才看得见**。
///
/// ## 年份切换器为什么是 `Menu` 而不是分段控件
///
/// 分段控件（三个格子）要塞进这一行就得自己占一行（约 +32pt），而这一行的左边
/// 只有一个数 —— 空着一大片。`Menu` 的标签就是"当前是哪一年"这句话本身，
/// 点开才是选项，于是**范围声明与控件是同一个东西**（`ProfileCopy.yearLabel`）。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。本件只画一行，背景由 `CardBox` 给。
public struct HeatmapHeader: View {

    /// 左边那个数（`1,024 次贡献`）。**`nil` = 这一年的数没拿到**（失败态）⇒ 那一侧不画。
    ///
    /// ⚠️ 不许填 `0 次贡献`：`0` 是"这一年确实没贡献"，`nil` 是"没拿到"
    /// （同 `ProfileStats` 那条"绝不把缺席填成 0"）。
    public let totalText: String?

    /// 切换器上显示的字（`2026 年`）。
    public let yearTitle: String

    /// 选项（顺序 = 菜单顺序）。
    public let yearOptions: [HeatmapYear]

    /// 当前选中的年份。
    public let selectedYear: Int

    /// 读屏标签（文案归领域层，见 `ProfileCopy.heatmapYearAccessibilityLabel(year:)`）。
    public let yearAccessibilityLabel: String

    /// 选了某一年。
    public let onSelectYear: (Int) -> Void

    public init(
        totalText: String?,
        yearTitle: String,
        yearOptions: [HeatmapYear],
        selectedYear: Int,
        yearAccessibilityLabel: String,
        onSelectYear: @escaping (Int) -> Void
    ) {
        self.totalText = totalText
        self.yearTitle = yearTitle
        self.yearOptions = yearOptions
        self.selectedYear = selectedYear
        self.yearAccessibilityLabel = yearAccessibilityLabel
        self.onSelectYear = onSelectYear
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            if let totalText {
                // 原型 `.t1`（15px/650）被内联改成 `font-size:14px` ⇒
                // 最近的一档是 `rowTitle`（`.subheadline` 15），权重取 `.semibold`（600 ≈ 650）。
                Text(totalText)
                    .font(Theme.Font.rowTitle.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }

            Spacer(minLength: 0)

            yearMenu
        }
        // 原型 `style="margin-bottom:10px"`（10 不在 4pt 阶里 ⇒ 写原值）。
        // ⚠️ 这一行**永远**在（失败态也在），所以这 10pt 不用按状态分支。
        .padding(.bottom, 10)
    }

    private var yearMenu: some View {
        Menu {
            // `Picker` 在菜单里的样子就是"带勾选的选项列表" —— 用的不是它挑值的本事，
            // 而是它自带的"当前是哪一项"这个视觉信号。
            Picker(
                selection: Binding(
                    get: { selectedYear },
                    set: { onSelectYear($0) }
                ),
                label: EmptyView()
            ) {
                ForEach(yearOptions) { option in
                    Text(option.title).tag(option.year)
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                // 原型 `.t3`（11.5px / `--text3`）那一档 —— 与卡片上那句范围声明同一档。
                Text(yearTitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)

                // ⚠️ 图标字号写死（与全项目 50 处 `.system(size:)` 同一处置，偏差第 41 条）：
                //    它是个图标、不随「更大字体」缩放，而 `chevron.down` 在 caption 那一档
                //    会显得比文字大一圈、把这一行顶高。
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            // 整块（含那枚小箭头）都可点 —— 只让文字可点会让这一行"看着能点、点不中"。
            .contentShape(Rectangle())
        }
        .accessibilityLabel(yearAccessibilityLabel)
    }
}

/// 年份切换器里的一个选项。
///
/// ⚠️ 它只有**数字 + 文案**：设计包不认识 `ContributionYear`（依赖铁律），
/// 而切换器需要的恰恰就是这两样（`id` 用来对勾选、`title` 用来写菜单项）。
public struct HeatmapYear: Identifiable, Hashable, Sendable {

    /// 年份（也是 `Picker` 的 `tag`）。
    public let year: Int

    /// 菜单里那一行字（`2026 年`）。
    public let title: String

    public var id: Int { year }

    public init(year: Int, title: String) {
        self.year = year
        self.title = title
    }
}

#Preview {
    let years = [
        HeatmapYear(year: 2026, title: "2026 年"),
        HeatmapYear(year: 2025, title: "2025 年"),
        HeatmapYear(year: 2024, title: "2024 年"),
    ]

    return VStack(spacing: Theme.Spacing.m) {
        CardBox(vertical: 14) {
            HeatmapHeader(
                totalText: "1,024 次贡献",
                yearTitle: "2026 年",
                yearOptions: years,
                selectedYear: 2026,
                yearAccessibilityLabel: "切换年份，当前 2026 年",
                onSelectYear: { _ in }
            )
        }

        // 失败态：左边那个数**不画**（不是 `0 次贡献`），而切换器照常在。
        CardBox(vertical: 14) {
            HeatmapHeader(
                totalText: nil,
                yearTitle: "2025 年",
                yearOptions: years,
                selectedYear: 2025,
                yearAccessibilityLabel: "切换年份，当前 2025 年",
                onSelectYear: { _ in }
            )
        }
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
