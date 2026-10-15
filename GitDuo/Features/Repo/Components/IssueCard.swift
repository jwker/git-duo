import SwiftUI
import GitDuoDesign
import GitDuoKit

/// **Issue 卡片** —— §4.14 探索 Issues 列表与 §4.4 分区二（仓库详情 Issues 段）
/// **两处共用**（决策 #61）。
///
/// 形状逐字对齐原型 `10-explore-repo.js:103-106`：
/// **状态图标 + 标题（`t1`）+ 副标题（`t3`）**，整体是一张 `.card`。
///
/// ## ⚠️ 它为什么从 `Features/Explore/` 搬到了这里
///
/// 切片 4 造它时只有一个调用方（探索页），放 `Explore/Components/` 是对的。
/// 切片 7 的 §4.4 分区二要画**同一张**卡片 ⇒ 两处各留一份的下场是
/// 「把标题字号改小 0.5pt」这种改动只落到其中一页，而另一页看起来"也没错"。
///
/// 落点与判据跟 6.4d 的 `RepoTreeSection` 完全相同：**搬进接收方的目录**
/// （`Features/Repo/Components/`，切片 7 的主场），原调用方改为引用它。
/// ⚠️ 这次搬迁是**纯整理 + 加一个参数**，版式一行没动。
///
/// ## 两处的差异**只有一处**
///
/// | | §4.14（探索） | §4.4 分区二（仓库详情） |
/// |---|---|---|
/// | 标签胶囊 | **不画**（原型那张卡片只有两行） | 画（`showsLabels: true`） |
///
/// 其余一切（状态图标与配色、标题字号、副标题由 `IssueRow.metaLabel` 拼、
/// 间距、`CardBox`、读屏标签）**只有这一份**。
///
/// ⚠️ **标签不是"有就画"**：原型 §4.4 那张卡片上确实有一枚胶囊，但它画的是
/// **评论数**、用的还是绿色状态胶囊（`05-repo.js:243` 的 `<span class="pill open">${i.c}</span>`）
/// —— 照抄会得到"一枚看起来在说状态的东西里写着 3"。
/// 用户裁定按 PRD 的执行「标签胶囊」：画**真实标签**（`LabelPill` + 标签自己的颜色），
/// 不照原型的形状。已登记为**有意偏差**（原型 ↔ PRD 冲突，取 PRD）。
///
/// ⚠️ 因此"这一页画不画标签"是**页面口径**，不能靠 `row.labels` 是否为空来判断
/// —— 模型里那个空数组分不出"没有标签"与"这一页不画标签"
/// （`IssueRow.labels` 的说明写了这条）⇒ 用参数显式表达。
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

    /// 是否渲染标签行。**默认 `false`** = 探索页那张卡片（§4.14，原型没有这一行）。
    let showsLabels: Bool

    /// 顶上一条内嵌 hairline（方案 D 的 `.card+.card{border-top:…}`）——

    /// ⚠️ 显式写初始化器、而不是靠"属性带默认值 = 参数带默认值"那个语法糖：
    /// 带初始值的 `let` 属性**不会**出现在自动生成的 memberwise init 里
    /// （只有 `var` 才会）⇒ 那种写法会让 `showsLabels` 变成一个设不进去的参数，
    /// 而错误出现在调用点、看起来像"这个组件没有那个参数"。
    init(row: IssueRow, now: Date, showsLabels: Bool = false,
    ) {
        self.row = row
        self.now = now
        self.showsLabels = showsLabels
    }

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

                    if showsLabels, !row.labels.isEmpty {
                        labelRow
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        // 读屏时**先报状态**：图标传达的正是它，而形状不该是唯一的载体。
        .accessibilityLabel("\(row.stateLabel) · \(row.title)")
    }

    /// 标签行 —— 原型 §4.4 那句是 `<div style="margin-top:5px">`。
    ///
    /// ⚠️ 用 `FlowLayout` 而不是 `HStack`：标签个数不定（0–20 个）、长度也不定
    /// （`bug` 三个字符、`good first issue` 十五个）—— `HStack` 放不下会**压缩**，
    /// 于是标签名被截成 `good firs…`，而原型是换行（`RepoHeroCard.topics` 的同一处置）。
    ///
    /// ⚠️ 也**不排序**：顺序就是服务端给的顺序（`IssueRow.labels` 的说明写了理由）——
    /// 按名字重排会让同一张卡片在网页端与这里长得不一样。
    private var labelRow: some View {
        FlowLayout(spacing: Theme.Spacing.xs, lineSpacing: Theme.Spacing.xs) {
            ForEach(row.labels) { label in
                LabelPill(name: label.name, colorHex: label.colorHex)
            }
        }
        // ⚠️ 不加这一句换行会失效：`FlowLayout` 拿到未指定的宽度时按"一行放得下"算，
        //    于是永远不折行、直接撑出卡片。占满可用宽度后它才有宽度可依。
        .frame(maxWidth: .infinity, alignment: .leading)
        // 原型 `margin-top:5px` —— 4pt 阶里最接近的是 `xs`（4）。
        // 不新造一个 5pt 的档：那会让"间距只有一套"这件事从这一处开始漏。
        .padding(.top, Theme.Spacing.xs)
    }

    /// ⚠️ 本列表**只会有开放**（决策 #38），但这里仍按 `row.isOpen` 分支 ——
    /// 与 `IssueRow.isOpen` 保留字段同一个理由：视图不该比模型更懂业务。
    /// 切片 7 起 §4.4 分区二真的会传 `false` 进来（「已关闭」档）。
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
        // §4.4 分区二那一档：带标签（`showsLabels: true`）。
        IssueCard(
            row: IssueRow(
                number: 84,
                title: "标签筛选后计数与实际条数对不上",
                isOpen: true,
                comments: 2,
                createdAt: .now.addingTimeInterval(-86_400),
                authorLogin: "reviewer-b",
                labels: [
                    Label(name: "bug", colorHex: "d73a4a"),
                    Label(name: "good first issue", colorHex: "8250df"),
                ]
            ),
            now: .now,
            showsLabels: true
        )
        // 已关闭那一档（视图不该按"只会有开放"写死）。
        IssueCard(
            row: IssueRow(
                number: 61,
                title: "深色模式下置顶卡闪白",
                isOpen: false,
                comments: 1,
                createdAt: .now.addingTimeInterval(-604_800),
                authorLogin: "reviewer-a",
                labels: [Label(name: "本期不做", colorHex: "6a737d")]
            ),
            now: .now,
            showsLabels: true
        )
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
