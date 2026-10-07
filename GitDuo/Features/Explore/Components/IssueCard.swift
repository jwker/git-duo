import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 探索 Issues 列表的一行（PRD §4.14 结构一行）。
///
/// 形状逐字对齐原型 `10-explore-repo.js:121-124`：
/// **状态图标 + 标题（`t1`）+ 副标题（`t3`）**，整体是一张 `.card`。
///
/// ## 它为什么留在 Feature 层（决策 #43）
///
/// 判据是"参数用不用领域模型"：本组件的入参是 `IssueRow` ⇒ 它认识业务，
/// 属于 `GitDuo` 而不是 `GitDuoDesign`。设计包里只有那些"与业务无关的视觉件"。
///
/// ## 与 `LinkRow` 的区别
///
/// `LinkRow` 是 `.file-row`（左侧图标 + 右侧尖角 + 行内分隔线），用于"参与协作"
/// 那两条**入口**；本卡片是 `.card`，用于列表里的**内容行**。两者在原型里
/// 就是两套样式，不要因为"看着都是图标加文字"而合并。
struct IssueCard: View {

    let row: IssueRow

    /// 相对时间现算用的"现在"。由视图在渲染那刻传进来 ——
    /// **不在卡片内部取 `Date()`**：那会让每次重绘都拿到不同的值，
    /// 于是相对时间变成渲染时机的一部分，测试与截图都无从稳定。
    let now: Date

    var body: some View {
        CardBox {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                Image(systemName: icon)
                    .font(Theme.Font.body)
                    .foregroundStyle(tint)
                    // 图标与后文的 `accessibilityLabel` 说的是同一件事 ⇒ 不让它单独被读。
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(row.title)
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.leading)

                    Text(row.metaLabel(now: now))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        // 读屏时**先报状态**：图标传达的正是它，而形状不该是唯一的载体。
        .accessibilityLabel("\(row.stateLabel) · \(row.title)")
    }

    /// ⚠️ 本列表**只会有开放**（决策 #38），但这里仍按 `row.isOpen` 分支 ——
    /// 与 `IssueRow.isOpen` 保留字段同一个理由：视图不该比模型更懂业务。
    /// 将来「我的仓库」四分区（切片 7）直接复用本组件时，那个分支就是现成的。
    private var icon: String {
        row.isOpen ? StateIcon.issueOpen : StateIcon.issueClosed
    }

    private var tint: Color {
        row.isOpen ? Theme.Palette.stateOpenIcon : Theme.Palette.stateCompletedIcon
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.s) {
        IssueCard(
            row: IssueRow(
                number: 128,
                title: "滚动到底时列表偶尔会重复渲染同一行",
                isOpen: true,
                comments: 3,
                createdAt: .now.addingTimeInterval(-7_200),
                authorLogin: "reviewer-a"
            ),
            now: .now
        )
        IssueCard(
            row: IssueRow(
                number: 96,
                title: "README 里的安装命令在 zsh 下报错",
                isOpen: true,
                comments: 0,
                createdAt: .now.addingTimeInterval(-172_800),
                authorLogin: nil
            ),
            now: .now
        )
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
