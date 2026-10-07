import SwiftUI

/// 自动换行的横排布局 —— 放不下的元素折到下一行（原型 CSS 的 `flex-wrap:wrap`）。
///
/// ## 为什么需要它
///
/// 话题标签（`topics`）的**个数不定**（0–20 个），长度也不定（`ios` 三个字符、
/// `design-tokens` 十三个）。`HStack` 放不下会**压缩**（文字被截成 `desig…`），
/// 而原型是换行。SwiftUI 没有内建的流式布局，`ViewThatFits` 又只能给"整块的几个候选"，
/// 表达不了"第 3 个开始换行"。
///
/// ## 它是"与业务无关的视觉件"
///
/// 所以它在 `GitDuoDesign` 里（决策 #43）：认识领域模型的卡片才留在各 Feature。
/// 将来分支胶囊、标签列表、筛选结果都能用它。
///
/// ## 为什么不用 `LazyVGrid` 的 `.adaptive`
///
/// 那会**给每一列定一个统一的宽度**（最宽的那个元素说了算），于是短标签之间会隔着
/// 一大片空白。流式布局按每个元素自己的宽度排，正是原型的样子。
///
/// ⚠️ 它没有布局引擎之外的可测行为（`Layout` 的 `sizeThatFits` 需要真实的文本度量），
/// 所以这里**没有单测** —— 与"骨架屏尺寸必须匹配真实布局"同一类问题，
/// 只能靠模拟器上看一眼。
public struct FlowLayout: Layout {

    /// 同行元素之间的间距。
    public var spacing: CGFloat

    /// 行与行之间的间距。
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = Theme.Spacing.s, lineSpacing: CGFloat = Theme.Spacing.xs) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        // 宽度未知（`.unspecified`）时按"一行放得下"算 —— 返回 `infinity` 会让父容器崩溃或给出怪异布局。
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widestLine: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            // 已经排了东西、且再放一个就超宽 ⇒ 换行。
            if lineWidth > 0, lineWidth + spacing + size.width > maxWidth {
                widestLine = max(widestLine, lineWidth)
                totalHeight += lineHeight + lineSpacing
                lineWidth = 0
                lineHeight = 0
            }

            lineWidth += lineWidth > 0 ? spacing + size.width : size.width
            lineHeight = max(lineHeight, size.height)
        }

        widestLine = max(widestLine, lineWidth)
        totalHeight += lineHeight

        return CGSize(width: min(widestLine, maxWidth), height: totalHeight)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            // 同样的换行判定，必须与 `sizeThatFits` 逐字一致 ——
            // 两处若不一致，元素会落在"量出来有位置、实际画到界外"的地方。
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )

            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#Preview {
    FlowLayout {
        ForEach(["swiftui", "ios", "design-tokens", "accessibility", "components", "liquid-glass"], id: \.self) {
            Text($0)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.accent)
        }
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
