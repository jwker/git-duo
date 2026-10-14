import SwiftUI

/// 把若干格**横着排、一行放不下就换到下一行**的布局（2026-10-14 新增，走查第 **65** 条）。
///
/// ## 它解决什么
///
/// README 开头那排"许可证 / 构建状态"徽章在 GitHub 上是**一行横排**的小胶囊，
/// 而我们此前是每格**自成一行**（`VStack`）⇒ 四张 20pt 高的徽章吃掉 216pt，
/// 把正文挤得很长（用户 2026-10-14 报回的就是这个）。
///
/// ⚠️ **SwiftUI 没有内置的 flow 布局**：`HStack` 不换行、`LazyVGrid` 要求等宽列、
/// `ViewThatFits` 只按整体尺寸挑一个版本 —— 都做不到"宽度不同、放不下才换行"。
/// 所以这里自己写一个（`Layout` 协议，iOS 16+）。
///
/// ## 怎么量的
///
/// 每一格都按 **"整行宽度"** 去问它的尺寸（`ProposedViewSize(width: limit)`）：
/// 图与徽章都会在这个约束下给出**自己想要的宽度**（徽章按文字算、有 `width` 声明的图
/// 按声明值），而不是被撑满。⚠️ 这一点是它能工作的前提 —— 若给 `.unspecified`，
/// `Image.resizable()` 那类视图量不出确定宽度，整行会算崩。
///
/// ## ⚠️ 进来之前已经过滤过一轮
///
/// 哪些格能并排由**领域层**决定（`MarkdownRun` 的判据：连续 ≥2 个"宽度已知"的格）。
/// 这个布局只负责"排"，不负责"能不能一起排" —— 那种判据必须能跑单测，
/// 而 `make test` 不编译 App target。
struct MarkdownFlowLayout: Layout {

    /// 同一行里两格之间的距离。
    var spacing: CGFloat

    /// 行与行之间的距离。
    ///
    /// ⚠️ 与 `spacing` 分开：横着是"两个东西挨着"，竖着是"两行文字之间"，
    /// 后者的观感需要更紧一点才像一整块内容。
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let limit = proposal.width ?? .infinity
        let lines = lines(in: subviews, limit: limit)

        let width = proposal.width ?? lines.map(\.width).max() ?? 0
        return CGSize(width: width, height: totalHeight(of: lines))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY

        for line in lines(in: subviews, limit: bounds.width) {
            var x = bounds.minX
            for entry in line.entries {
                entry.subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(entry.size)
                )
                x += entry.size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    // MARK: - 分行

    private func totalHeight(of lines: [Line]) -> CGFloat {
        lines.reduce(0) { $0 + $1.height } + CGFloat(max(0, lines.count - 1)) * lineSpacing
    }

    /// 按可用宽度把各格分行。⚠️ `sizeThatFits` 与 `placeSubviews` **必须用同一套量法**
    /// （同一个 `limit`、同一个 `spacing`），否则算出来的高与实际摆的位置对不上，
    /// 表现是"最后一行被切掉"或"下面多出一块空白"。
    private func lines(in subviews: Subviews, limit: CGFloat) -> [Line] {
        var result: [Line] = []
        var current = Line()

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: limit, height: nil))
            let extended = current.entries.isEmpty
                ? size.width
                : current.width + spacing + size.width

            if !current.entries.isEmpty, extended > limit {
                result.append(current)
                current = Line()
                current.width = size.width
            } else {
                current.width = extended
            }

            current.height = max(current.height, size.height)
            current.entries.append(Entry(subview: subview, size: size))
        }

        if !current.entries.isEmpty { result.append(current) }
        return result
    }

    private struct Entry {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct Line {
        var entries: [Entry] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
}
