import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 探索 PR 列表的一行（PRD §4.15 结构一行）。
///
/// 形状逐字对齐原型 `10-explore-repo.js:136-139`，与 `IssueCard` 同构
/// （状态图标 + 标题 + 副标题），**唯一差别是状态档数**：
///
/// | | `IssueCard` | `PullCard` |
/// |---|---|---|
/// | 状态 | 只有开放（决策 #38） | 开放 + 已合并（决策 #39） |
///
/// 副标题是 `#57 · feature/repo-hub → main` —— **不含作者**，因为原型卡片上就没有
/// （`PullRow` 的类型说明记着这条不对称）。
///
/// ## 它为什么留在 Feature 层（决策 #43）
///
/// 入参是 `PullRow`（领域模型）⇒ 它认识业务。设计包里只有"与业务无关的视觉件"。
struct PullCard: View {

    let row: PullRow

    var body: some View {
        CardBox {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                Image(systemName: Self.icon(for: row.state))
                    .font(Theme.Font.body)
                    .foregroundStyle(Self.tint(for: row.state))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(row.title)
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.leading)

                    // `metaLabel` 不带 `now`：它只有编号与分支名，没有相对时间。
                    Text(row.metaLabel)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.state.label) · \(row.title)")
    }

    // MARK: - 状态 → 图标 / 配色

    /// ⚠️ `StateIcon` 里只有**开放**与**已合并**两个 PR 符号（对齐原型
    /// `02-icons.js` 的 `I.pr` / `I.merge`）。
    ///
    /// `.closed`（关闭但**未**合并）复用开放那一个字形 —— 它与开放 PR 是同一个
    /// 图形对象，只是配色不同（红）。这也是 GitHub 网页端的画法。
    ///
    /// ⚠️ 本列表**会先滤掉 `.closed`**（PRD §4.15、`LoadRepoPulls`），所以这一档
    /// 在探索路径上不会出现。留着它是为了两件事：① `switch` 穷尽（不然将来
    /// `PullRequestState` 加一档就静默走了别的分支）；② 切片 7 的 PR 详情列表
    /// 要用到已关闭的。
    static func icon(for state: PullRequestState) -> String {
        switch state {
        case .open, .closed: StateIcon.pullRequestOpen
        case .merged: StateIcon.pullRequestMerged
        }
    }

    /// 三档配色 —— 用的是**状态图标**那一族 token（`stateOpenIcon` /
    /// `stateCompletedIcon`），**不是**状态胶囊那一族（`stateOpen` / `stateMerged`）。
    /// 两族值不同（图标色比标签色亮一档），混用会让图标与旁边的文字串味 ——
    /// 见 `Theme.Palette.stateOpenIcon` 的说明。
    static func tint(for state: PullRequestState) -> Color {
        switch state {
        case .open: Theme.Palette.stateOpenIcon
        case .merged: Theme.Palette.stateCompletedIcon
        case .closed: Theme.Palette.stateClosed
        }
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.s) {
        PullCard(
            row: PullRow(
                number: 57,
                title: "feat(explore): 趋势卡支持自定义角标",
                state: .open,
                headRef: "feature/repo-hub",
                baseRef: "main"
            )
        )
        PullCard(
            row: PullRow(
                number: 41,
                title: "fix(home): 置顶卡在深色下拉时闪白",
                state: .merged,
                headRef: "fix/pin-flash",
                baseRef: "main"
            )
        )
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
