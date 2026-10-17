import SwiftUI

/// 顶栏里那颗「**大字 + 居左**」的页面标题（2026-10-16 走查第 86 条）。
///
/// ## 为什么要自绘：系统没有这一档
///
/// 用户要的形状是「标题在**顶栏**里、与右上角头像**同一行**、**居左**、**字号放大**」。
/// 系统给的两种标题档位都对不上：
///
/// | 档位 | 位置 | 字号 / 对齐 | 差在哪 |
/// |---|---|---|---|
/// | `.inline` | 顶栏 | 17pt、**居中**（没有 leading 项时） | 字号小、不靠左 |
/// | `.large` | 内容区顶部 | 34pt、靠左 | 不在顶栏，和头像不是一级 |
///
/// 而**字号放大 + 在顶栏**这两件事，SwiftUI 没有任何修饰符能同时给
/// （`navigationTitle` 的字号与位置都由系统定）⇒ 只能自己画一颗放 `topBarLeading`。
/// 这是本目录下**唯一**一处为观感自绘的导航栏件，理由写在这里而不是散在三个页面里。
///
/// ## ⚠️ 两条实测前提（iOS 27.0 模拟器探针 `/tmp/probe-titlebar/`）
///
/// 1. **`.fixedSize(horizontal: true, vertical: false)` 不能省** —— 工具栏会压缩
///    自定义视图，实测不加这一句，这颗 26pt 标题会被压到**几乎看不见**
///    （列投影分析里顶栏那块直接消失）。
/// 2. **必须再用一个透明的 `principal` 把系统 inline 标题顶掉** —— 否则屏幕上会同时
///    出现两遍标题（左边自绘大字 + 中间系统 17pt）。`principal` 位放一个 1×1 的
///    透明视图即可，而 `.navigationTitle` **照旧保留**（它还是返回按钮文案与
///    无障碍标题的来源）。
///
/// ## 不做的两件事
///
/// - **不用 `UINavigationBarAppearance` 改全局标题字体**：那会连推入页的标题一起改，
///   而这一档只属于四个 Tab 根页中的三个。
/// - **不把字号做成入参**：三处必须一样大，"某页更大一号"是漂移的开始。
struct TopBarTitleItem: ToolbarContent {

    let text: String

    /// 三处共用的字号。26pt 是量出来的：顶栏净高约 54pt，26pt 字的墨迹高约 25pt，
    /// 与右上角那颗 30pt 头像**垂直居中对齐**（探针实测两者中心都在 y≈92）。
    static let fontSize: CGFloat = 26

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Text(text)
                .font(.system(size: Self.fontSize, weight: .bold))
                // ⚠️ 见类型说明：不加这句会被工具栏压没。
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityAddTraits(.isHeader)
        }
        // 工具栏默认给自定义视图加玻璃胶囊背景 —— 标题不是按钮，不需要它。
        .sharedBackgroundVisibility(.hidden)

        // ⚠️ 占位用的空 `principal`：把系统 inline 标题从顶栏顶掉（类型说明第 2 条）。
        ToolbarItem(placement: .principal) {
            Color.clear.frame(width: 1, height: 1)
        }
        .sharedBackgroundVisibility(.hidden)
    }
}
