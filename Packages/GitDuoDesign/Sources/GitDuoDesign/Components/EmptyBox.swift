import SwiftUI

/// 空态框 —— 官方 `ContentUnavailableView` 的一层薄壳（NATIVE-MIGRATION P1）。
///
/// ⚠️ 上面那段原型 CSS（`.empty-box` 虚线框）**已作废**：原型现在是**功能清单**，
/// 视觉正本是 Apple HIG（`AGENTS.md §0`）。虚线框那套形状不再有依据。
///
/// 用在首页的两处（无置顶 / 无最近访问）、探索榜的无结果、Issues / PR 空态等。
///
/// ## 空态与"加载中"必须**一眼可分**（§8.5 末条：加载中 ≠ 无数据）
///
/// 这条要求没变，但**实现方式换了**：从前靠那个虚线框（一个明确的"这里是空的、
/// 不会自己变出东西来"的信号），现在靠系统的 `ContentUnavailableView`
/// —— 它自带"图标 + 标题 + 说明"这个**只在空态出现**的组合，与 `.redacted` 的
/// 灰块系统性地不像（一个是有图标的一句话，一个是无字的条）。
/// ⚠️ 所以**不要为了省事把它换成一行居中灰字** —— 那正是当年特意避开的样子。
///
/// ## 两行而不是一行
///
/// PRD §7 给每条空态都配了两句：第一句说**是什么都没有**，第二句说**怎么让它有**
/// （`去个人主页「Customize your pins」挑几个…`）。只说第一句等于把用户丢在原地。
/// 第二句因此是可空的 —— 有例外（探索榜的无结果就只有一句）。
///
/// ## ⚠️ 2026-10-16 起它**只是 `ContentUnavailableView` 的一层薄壳**（NATIVE-MIGRATION P1）
///
/// 从前它是"虚线圆角框 + 两行居中灰字"那一整套自绘形状。换成官方 `ContentUnavailableView`
/// 之后，**空态的排版、字号层级、图标与标题的间距、深浅两档的配色、Dynamic Type**
/// 全部由系统给出 —— 自绘版要手工维护的正是这些。
///
/// 壳子本身留着是因为它承载**产品的那一层**：标题 / 第二句（怎么做）两句的分工
/// （PRD §7 给每条空态都配了两句），以及 24 个调用点。等 P3 把列表主干也原生化时，
/// 调用点会直接写 `ContentUnavailableView`，这一层壳就可以删了。
///
/// ⚠️ `systemImage` 是这次新增的（官方空态**带图标**）。默认 `tray`（"这里是空的"的通用形）；
///    调用方有更贴切的字形时应当传 —— 见 `GitHubIcon` 抬头那条告诫：
///    **字形名写错不会报错，只会在界面上凭空消失**。
public struct EmptyBox: View {

    public let title: String

    /// 第二句（怎么做）。`nil` = 只显示第一行。
    public let hint: String?

    /// 空态图标（SF Symbol 名）。
    public let systemImage: String

    public init(title: String, hint: String? = nil, systemImage: String = "tray") {
        self.title = title
        self.hint = hint
        self.systemImage = systemImage
    }

    public var body: some View {
        // 两种分支而不是"给 description 传一个空 `Text`" —— 后者会画出一个**空行**
        //（系统不知道那句该不该占地方），而"只有一句"与"两句"是两种真实形态。
        if let hint {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(hint)
            }
        } else {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            }
        }
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.l) {
        EmptyBox(
            title: "GitHub 个人主页还没有置顶仓库",
            hint: "去个人主页「Customize your pins」挑几个，回到首页下拉即可看到"
        )
        EmptyBox(title: "没有符合条件的仓库，试试放宽筛选")
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
