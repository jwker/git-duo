import SwiftUI

/// 空态框 —— 虚线边框的两行提示（原型 `styles/03-components.css` 的 `.empty-box`）。
///
/// ```css
/// .empty-box{border:1px dashed var(--border);border-radius:12px;padding:20px 14px;
///            text-align:center;font-size:12.5px;color:var(--text3);line-height:1.7}
/// ```
///
/// 用在首页的两处（无置顶 / 无最近访问）与探索榜的无结果。
///
/// ## 为什么要一个"框"而不是一行灰字
///
/// 空态与"内容还在加载"必须**一眼可分**（§8.5 末条：加载中 ≠ 无数据）。
/// 一个虚线框是一个明确的"这里是空的、而且不会自己变出东西来"的信号；
/// 而一行居中灰字在视觉上与骨架屏的占位条太像。
///
/// ## 两行而不是一行
///
/// PRD §7 给每条空态都配了两句：第一句说**是什么都没有**，第二句说**怎么让它有**
/// （`去个人主页「Customize your pins」挑几个…`）。只说第一句等于把用户丢在原地。
/// 第二句因此是可空的 —— 有例外（探索榜的无结果就只有一句）。
///
/// ## 它是内容层
///
/// **实色、虚线边，不加 Liquid Glass**（§10.2）。
public struct EmptyBox: View {

    public let title: String

    /// 第二句（怎么做）。`nil` = 只显示第一行。
    public let hint: String?

    public init(title: String, hint: String? = nil) {
        self.title = title
        self.hint = hint
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(title)
            if let hint {
                Text(hint)
            }
        }
        .font(Theme.Font.label)
        .foregroundStyle(Theme.Palette.textTertiary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        // 20 / 14 是原型原值（4pt 阶里没有 20 这一档）。
        .padding(.vertical, 20)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .strokeBorder(
                    Theme.Palette.border,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        )
        .accessibilityElement(children: .combine)
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
