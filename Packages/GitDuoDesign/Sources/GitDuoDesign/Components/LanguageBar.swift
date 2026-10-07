import SwiftUI
import GitDuoCore

/// 语言构成占比条 + 图例（原型 `scripts/10-explore-repo.js` 的「语言构成」分区、
/// PRD §4.13 第 3 条、TECH_SPEC §9.11）。
///
/// 分段口径（**决策 #42**）由 `LanguageComposition` 决定 —— 本组件只负责画，
/// 不自己决定"切几段""百分比怎么取整"。这样"占比加起来是不是 100%"
/// 可以在没有 UI 的情况下被单测钉死。
///
/// ## 空输入不画任何东西
///
/// 语言数据为空（空仓库 / 只有配置文件）时它**不渲染**，由调用方换成空态文案。
/// 组件自己吐一根全灰的条会更糟 —— 那看起来像"这个仓库 100% 是某种语言"。
/// 这是"组件不猜业务语义"的一例。
///
/// ## 它是内容层
///
/// 占比条与图例都在卡片里（§10.2 点名"仓库卡片"），**实色，不加 Liquid Glass**。
public struct LanguageBar: View {

    public let shares: [LanguageShare]

    /// 色带高度。原型 `height:8px`；8pt 下用 `Capsule` 收口正好是原型那 4px 圆角。
    public let barHeight: CGFloat

    public init(shares: [LanguageShare], barHeight: CGFloat = 8) {
        self.shares = shares
        self.barHeight = barHeight
    }

    public var body: some View {
        if !shares.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                bar
                legend
            }
        }
    }

    // MARK: - 色带

    private var bar: some View {
        GeometryReader { proxy in
            let widths = Self.segmentWidths(
                percents: shares.map(\.percent),
                total: proxy.size.width
            )
            HStack(spacing: 0) {
                // 用 `indices` 而不是 `enumerated()`：段的身份就是它的位置
                // （两条数据源的排序稳定，位置不会漂），也免掉元组 keypath 那条灰色地带。
                ForEach(shares.indices, id: \.self) { index in
                    Rectangle()
                        .fill(color(for: shares[index]))
                        .frame(width: widths[index])
                }
            }
        }
        .frame(height: barHeight)
        .clipShape(Capsule())
        // 读屏：色带本身不承载文字信息，图例才是。
        .accessibilityHidden(true)
    }

    /// 把整数百分比换算成像素宽度，**最后一段吃掉舍入余数**。
    ///
    /// 为什么不让每段各算一次 `总宽 × 百分比`：那样各段之和会因浮点舍入
    /// 与总宽差上零点几个点，于是色带上出现**一条头发丝宽的背景色缝隙**
    /// —— 在深色段之间尤其明显，看起来像"语言之间还有别的语言"。
    ///
    /// `nonisolated` + 纯函数：这样"各段宽度之和恰等于总宽"可以被单测钉住，
    /// 而不必去截屏量像素。
    nonisolated static func segmentWidths(percents: [Int], total: CGFloat) -> [CGFloat] {
        guard !percents.isEmpty else { return [] }
        var widths = percents.dropLast().map { (total * CGFloat($0) / 100).rounded() }
        // 余数可能为负（前几段向上舍入过头）——夹到 0，宁可最后一段消失也不要负宽度。
        widths.append(max(0, total - widths.reduce(0, +)))
        return widths
    }

    private func color(for share: LanguageShare) -> Color {
        // 「其他」段没有语言名 ⇒ 走中性灰；有名字的走 linguist 词表。
        share.language.map { LanguageColor.color(for: $0) } ?? Theme.Palette.shareNeutral
    }

    // MARK: - 图例

    private var legend: some View {
        // 3 段封顶后，两个最长语言名（如 `TypeScript 61%` + `JavaScript 24%`）在窄屏上
        // 仍可能挤到一行放不下。`ViewThatFits` 让它在放不下时**自动换成竖排**，
        // 而不是把语言名截成 `TypeSc…`（截断后那行就没用了）。
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.m) { legendItems }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) { legendItems }
        }
    }

    private var legendItems: some View {
        ForEach(shares) { share in
            HStack(spacing: Theme.Spacing.xs) {
                Circle()
                    .fill(color(for: share))
                    .frame(width: 9, height: 9)
                Text("\(share.label) \(share.percentLabel)")
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
            .fixedSize()
            // 图例合成一条，读屏念「Swift 72%」而不是「圆形，Swift，72%」。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(share.label) \(share.percentLabel)")
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
        LanguageBar(shares: LanguageComposition.shares(from: [
            "Swift": 72_000, "Shell": 18_000, "Ruby": 6_000, "Makefile": 4_000,
        ]))
        LanguageBar(shares: LanguageComposition.shares(from: ["Rust": 5_000, "TOML": 200]))
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
