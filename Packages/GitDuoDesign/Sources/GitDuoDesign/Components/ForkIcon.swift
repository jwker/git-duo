import SwiftUI

/// 自定义的 **Fork** 图标。
///
/// SF Symbols 里没有一个「三个空心圆 + 实线」的 fork 字形：
/// `point.3.connected.trianglepath.dotted` 的连线是**虚点**、且第三个点在下方正中，
/// 而用户给的参考图是**实线**、第三个点在**左下**（与 GitHub 的 `repo-forked` octicon 同形）。
/// 所以自绘一个轻量 `Path`。
///
/// ## 形状：一个上下翻转的小写 `h`，三个线头各套一个空心圆
///
/// 用户给的判据（2026-10-11，原话）：
///
/// > 整体结构像一个上下翻转后的小写英文字母 h，然后有三个小的空心圆
/// > 分别画到上方两个端点和下方端点，线条弯曲顺滑不生硬
///
/// 即：
///
/// - **左竖线**是一根**完整**的竖线，上接左上圆、下接左下圆（`h` 那根贯穿的主干）；
/// - **右竖线**从右上圆垂下，到中部后**以圆角**拐成横向，接进左竖线；
/// - 三个空心圆分别在 **左上 / 右上 / 左下** 三个线头。
///
/// ⚠️ 三点都要注意：
/// 1. **左下才是第三个圆**，不是下方正中 —— 早期版本画成了等腰三角形（第三点在正中），
///    用户看到的就是"和参考图差太多"。
/// 2. **左竖线是通的**：左上圆与左下圆之间没有断口，中途只是被横向那根"搭"上去。
/// 3. **右竖线的拐角是圆弧**（`addQuadCurve`），不是直角 —— 这是用户点名的"顺滑不生硬"。
///
/// ## 尺寸与比例
///
/// 形状按 **22 × 28** 的参考网格绘制（比例取自用户参考图的实测边界框，
/// ≈ GitHub `repo-forked` 的 11 × 14 内容框），再整体缩放到传入的 frame。
/// 因此调用方给**正方形** frame 时，图形会按 22:28 适配居中 —— 比强行拉成正方更接近参考图。
///
/// ⚠️ 只画轮廓：颜色随当前 `foregroundStyle`，和 SF Symbols 一样可被按钮统一染色。
public struct ForkIcon: View {

    /// 参考网格（单位：无因次），等价于实测的 22×28 内容框。
    private enum Grid {
        /// 内容框宽高比：22 / 28 ≈ 0.786（≈ GitHub `repo-forked` 的 11 / 14）。
        static let aspect: CGFloat = 22.0 / 28.0
        static let width: CGFloat = 22
        static let leftX: CGFloat = 4.5
        static let rightX: CGFloat = 17.5
        static let topY: CGFloat = 4.5
        static let bottomY: CGFloat = 23.5
        static let joinY: CGFloat = 16.0
        /// 空心圆的**中线**半径（圆环外沿 = 它 + 线宽 / 2）。
        static let ringRadius: CGFloat = 3.0
        /// 线宽与圆环描边同宽。
        static let lineWidth: CGFloat = 3.0
        /// 右竖线拐成横向处的圆角。
        static let corner: CGFloat = 3.0
    }

    public init() {}

    public var body: some View {
        Canvas { context, size in
            let s = size.width / Grid.width   // 缩放因子：参考网格 → 实际尺寸

            let leftX = Grid.leftX * s
            let rightX = Grid.rightX * s
            let topY = Grid.topY * s
            let bottomY = Grid.bottomY * s
            let joinY = Grid.joinY * s
            let ringRadius = Grid.ringRadius * s
            let lineWidth = Grid.lineWidth * s
            let corner = Grid.corner * s

            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .round)

            // ① 左竖线：从上圆边缘直通下圆边缘（中途不断开）。
            var stem = Path()
            stem.move(to: CGPoint(x: leftX, y: topY + ringRadius))
            stem.addLine(to: CGPoint(x: leftX, y: bottomY - ringRadius))
            context.stroke(stem, with: .foreground, style: stroke)

            // ② 右竖线 + 圆角 + 横向连接段，一笔画成。
            var arm = Path()
            arm.move(to: CGPoint(x: rightX, y: topY + ringRadius))
            arm.addLine(to: CGPoint(x: rightX, y: joinY - corner))
            arm.addQuadCurve(
                to: CGPoint(x: rightX - corner, y: joinY),
                control: CGPoint(x: rightX, y: joinY)
            )
            arm.addLine(to: CGPoint(x: leftX, y: joinY))
            context.stroke(arm, with: .foreground, style: stroke)

            // ③ 三个空心圆。用 stroke 画圆环，与 SF Symbols 的 outline 风格一致。
            let centers = [
                CGPoint(x: leftX, y: topY),
                CGPoint(x: rightX, y: topY),
                CGPoint(x: leftX, y: bottomY),
            ]
            for center in centers {
                var ring = Path()
                ring.addEllipse(in: CGRect(
                    x: center.x - ringRadius,
                    y: center.y - ringRadius,
                    width: ringRadius * 2,
                    height: ringRadius * 2
                ))
                context.stroke(ring, with: .foreground, lineWidth: lineWidth)
            }
        }
        // 按参考内容的 22:28 适配（正方形 frame 里会左右留白，而不是被拉扁）。
        .aspectRatio(Grid.aspect, contentMode: .fit)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.l) {
        // 与真机同尺寸（统计按钮里的那颗）。
        HStack(spacing: Theme.Spacing.xs) {
            ForkIcon()
                .frame(width: 12, height: 12)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Fork · 88")
                .font(Theme.Font.label)
        }
        // 放大看形状。
        ForkIcon()
            .frame(width: 88, height: 112)
            .foregroundStyle(Theme.Palette.textPrimary)
    }
    .padding()
    .background(Theme.Palette.background)
}
