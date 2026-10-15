import SwiftUI
import GitDuoDesign
import GitDuoKit

/// **PR 卡片** —— §4.15 探索 PR 列表与 §4.4 分区三（仓库详情 PR 段）
/// **两处共用**（决策 #61）。
///
/// 形状逐字对齐原型 `10-explore-repo.js:118-121`，与 `IssueCard` 同构
/// （状态图标 + 标题 + 副标题），**唯一差别是状态档数**：
///
/// | | `IssueCard` | `PullCard` |
/// |---|---|---|
/// | 状态 | 只有开放（决策 #38） | 开放 + 已合并（决策 #39） |
///
/// ## ⚠️ 它为什么从 `Features/Explore/` 搬到了这里
///
/// 与 `IssueCard` 同一件事、同一时刻：切片 7 的 §4.4 分区三要画**同一张**卡片。
/// 落点与判据跟 6.4d 的 `RepoTreeSection` 相同 —— **搬进接收方的目录**，
/// 原调用方改为引用它。搬迁是**纯整理 + 加一个参数**，版式一行没动。
///
/// ## 两处的差异只有"多不多第三行"
///
/// | | §4.15（探索） | §4.4 分区三（仓库详情） |
/// |---|---|---|
/// | 第三行 `{作者} 更新于 {时间}` | **不画**（原型那张卡片只有两行） | 画（`now` 非 `nil`） |
/// | 增删统计 | 无 | **也没有** —— 列表端点不返回（决策 #58） |
///
/// 副标题 `#57 · feature/repo-hub → main` **两处相同**，都由 `PullRow.metaLabel` 给
/// —— 原型两处就是同一句（`PullRow` 的类型说明记着这条）。
///
/// ⚠️ 第三行**不能靠 `row.updatedAt != nil` 来判断要不要画**：
/// 那个字段两处**都拿得到**（列表端点返回 `updated_at`），
/// "这一页画不画"纯粹是页面口径 —— 用 `now: Date?` 显式表达，
/// 与 `IssueCard.showsLabels` 是同一种做法。
///
/// ## 它为什么留在 Feature 层（决策 #43）
///
/// 入参是 `PullRow`（领域模型）⇒ 它认识业务。设计包里只有"与业务无关的视觉件"。
struct PullCard: View {

    let row: PullRow

    /// 相对时间现算用的"现在"。
    ///
    /// **`nil` = 不渲染第三行**（探索页 §4.15）。非 `nil` 时若 `PullRow.updatedAt`
    /// 也拿不到，`PullRow.updateLine(now:)` 会返回 `nil`，那一行同样不画。
    ///
    /// ⚠️ 由视图在渲染那刻传进来，**不在卡片内部取 `Date()`** ——
    /// 否则相对时间会变成渲染时机的一部分（`IssueCard.now` 的同一处置）。
    let now: Date?

    /// 顶上一条内嵌 hairline（方案 D 的 `.card+.card{border-top:…}`）——
    /// 列表里**第一行传 `false`**。与 `IssueCard.showsTopSeparator` 同一条处置。
    var showsTopSeparator: Bool = false

    /// ⚠️ 显式写初始化器：带初始值的 `let` 属性**不会**出现在自动生成的
    /// memberwise init 里（只有 `var` 才会）⇒ 靠语法糖会让 `now` 变成一个
    /// 设不进去的参数，而错误出现在调用点。理由同 `IssueCard.init`。
    init(row: PullRow, now: Date? = nil, showsTopSeparator: Bool = false) {
        self.row = row
        self.now = now
        self.showsTopSeparator = showsTopSeparator
    }

    var body: some View {
        CardBox(showsTopSeparator: showsTopSeparator) {
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

                    if let updateLine {
                        Text(updateLine)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.state.label) · \(row.title)")
    }

    /// 第三行的文案；`nil` = 整行不画。
    ///
    /// 两种 `nil` 在这里合流、结果也相同（都不画），所以合成一个计算属性：
    /// ① 调用方没给"现在"（探索页）；② 给了、但服务端没给 `updated_at`。
    /// ⚠️ 合流是**在这里**做的 —— 别让它变成"两处各自判断一次"：
    /// 那样某天有一处漏判，屏幕上会出现一行 ` 更新于 `（前面多一个空格）。
    private var updateLine: String? {
        guard let now else { return nil }
        return row.updateLine(now: now)
    }

    // MARK: - 状态 → 图标 / 配色

    /// ⚠️ `StateIcon` 里只有**开放**与**已合并**两个 PR 符号（对齐原型
    /// `02-icons.js` 的 `I.pr` / `I.merge`）。
    ///
    /// `.closed`（关闭但**未**合并）复用开放那一个字形 —— 它与开放 PR 是同一个
    /// 图形对象，只是配色不同（红）。这也是 GitHub 网页端的画法。
    ///
    /// ⚠️ 两个列表**都会先滤掉 `.closed`**（PRD §4.15 / §4.4 分区三、`LoadRepoPulls`），
    /// 所以这一档在两条路径上都不会出现。留着它是为了两件事：① `switch` 穷尽
    /// （不然将来 `PullRequestState` 加一档就静默走了别的分支）；
    /// ② 它是 `StateIcon` 那套图标词汇的完整说明。
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
        // §4.15 那一档：两行（不给 `now`）。
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
        // §4.4 分区三那一档：三行（给了 `now`）。
        PullCard(
            row: PullRow(
                number: 33,
                title: "refactor(nav): 路由参数改为显式只读位",
                state: .open,
                headRef: "refactor/routes",
                baseRef: "main",
                authorLogin: "reviewer-a",
                updatedAt: .now.addingTimeInterval(-7_200)
            ),
            now: .now
        )
        // 服务端没给 `updated_at` ⇒ 第三行整行不画（不是画一行空的）。
        PullCard(
            row: PullRow(
                number: 29,
                title: "docs: 补 §9.9 的三条外部事实",
                state: .merged,
                headRef: "docs/spec",
                baseRef: "main",
                authorLogin: "reviewer-b",
                updatedAt: nil
            ),
            now: .now
        )
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
