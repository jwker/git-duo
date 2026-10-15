import GitHubAPI
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 仓库详情「Pull Requests」分区（PRD §4.4 分区三、TECH_SPEC §9.8.1、决策 #58 / #61）。
///
/// 结构：分段条（`开放 (N)` / `已合并`）→ PR 卡片列表。
///
/// ## 与探索 PR 列表（§4.15）的三处不同，全部是**有意**的
///
/// | | §4.15 | 本分区 |
/// |---|---|---|
/// | 档位 | 「开放 + 已合并」一次取回（决策 #39） | 「开放」/「已合并」**分别取数** |
/// | 卡片第三行 | 不画 | `{作者} 更新于 {时间}`（`PullCard(now:)`） |
/// | 新建入口 | 无 | **也没有** —— 但理由不同（见下） |
///
/// 卡片本身**只有一份**（`PullCard`，切片 7 搬到了 `Repo/Components/`），
/// 首屏骨架复用同一份（`ExploreSubListSkeleton`，理由同 `RepoIssuesSection`）。
///
/// ## ⚠️ 本分区**没有**「＋ 新建 PR」，而这不是还没做
///
/// §4.15 没有那个入口是因为"别人的仓库里你开不了 PR"；这里**自己的仓库**仍然没有，
/// 因为 PR 不是凭空建出来的：它得先有一条分支、一次提交，然后从提交面板里
/// 「提交到新分支 + PR」（§5.8）。给这一页放一个"新建 PR"按钮，点开只能是
/// 一个不知道基于哪条分支的空表单。
///
/// ## ⚠️ 与 `RepoIssuesSection` 长得像，但**不要合并成一个泛型组件**
///
/// 两者的骨架确实同构（分段条 + 卡片列表 + 分页行），差别在
/// **三个能力**（筛选 / 新建入口 / 卡片第三行）。合成一个泛型件要把这三处
/// 全部参数化（`trailing` / `emptyCopy` / `card` 三个构建器 + 两个可选闭包），
/// 结果是**每一个新读者都要先在脑子里把两个分区展开一遍**才能看明白其中任一个。
/// 已有的那处抽象（`RepoSubListViewModel`）恰好抽象的是**真正同构**的那一半
/// （分页 / 守卫 / 失败），而这两段**都在用它** —— 重复的只有版式，不是逻辑。
struct RepoPullsSection: View {

    /// **当前档**的取数状态机 —— 两档各持一份，成对存在 `RepoSectionViewModel` 里。
    ///
    /// ⚠️ 两档都取 `state=` 的**不同取值**（开放 → `open`，已合并 → `closed`）：
    /// GitHub 没有"只看已合并"这一个筛选项，「已关闭但没合并」的靠 `LoadRepoPulls`
    /// 本地滤掉（决策 #39 / #61 的同一口径）。
    let list: RepoSubListViewModel<PullRow>

    /// 当前选中的档。
    let segment: RepoSectionSegment

    /// 两格的文案（**已算好**，含计数）—— 理由同 `RepoIssuesSection.openTitle`。
    let openTitle: String
    let mergedTitle: String

    /// 「现在」由调用方给（同 `IssueCard`：不在 `body` 里取 `Date()`）。
    ///
    /// ⚠️ 本分区的卡片**要**它（第三行 `{作者} 更新于 {时间}`）——
    /// 这正是 `PullCard(now:)` 那个参数存在的理由。
    let now: Date

    let onSelectSegment: (RepoSectionSegment) -> Void

    /// 点一张卡片 —— 参数是 PR 编号。
    let onOpen: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            segmentBar
                .padding(.bottom, Theme.Spacing.m)

            content
        }
    }

    // MARK: - 分段条

    /// ⚠️ 只有两格（**没有** Issue 段那第三个「筛选」按钮）：PR 这一档没有
    /// 标签筛选这一说（PRD §4.4 分区三只写了「开放 / 已合并」两格）。
    private var segmentBar: some View {
        SegmentedBar(
            segments: [
                .init(id: RepoSectionSegment.open.rawValue, title: openTitle),
                .init(id: RepoSectionSegment.closed.rawValue, title: mergedTitle),
            ],
            selectedID: segment.rawValue,
            // 同 `RepoIssuesSection`：本件在已内缩的内容区里。
            padsHorizontally: false
        ) { picked in
            guard let picked = RepoSectionSegment(rawValue: picked.id) else { return }
            onSelectSegment(picked)
        }
    }

    // MARK: - 列表

    @ViewBuilder
    private var content: some View {
        switch list.content {
        case .skeleton:
            ExploreSubListSkeleton()

        case .items:
            rows

        case .needsMore, .empty:
            emptyBox

        case let .failure(error):
            // 分区内的失败**不掀翻整页**（§8.5）。
            SectionFailure(error: error) { Task { await list.refresh() } }
        }
    }

    private var rows: some View {
        let items = list.rows
        let lastID = items.last?.id

        return VStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, row in
                Button {
                    onOpen(row.number)
                } label: {
                    // ⚠️ 给 `now` ⇒ 画第三行。只读位由**路由**决定（铁律 #7），
                    //    本件不推断仓库归属。
                    //    方案 D：行间靠顶上那条内嵌 hairline 分隔 —— 首行不画。
                    PullCard(row: row, now: now)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if row.id == lastID {
                        Task { await list.loadMore() }
                    }
                }
            }

            listFooter
        }
    }

    @ViewBuilder
    private var listFooter: some View {
        if list.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.m)
        } else if list.error != nil {
            Button("加载失败 · 重试") {
                Task { await list.loadMore() }
            }
            .font(Theme.Font.footnote)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.m)
        }
    }

    private var emptyBox: some View {
        // ⚠️ 两档各说各的，且**都不是** §4.15 那一句：那一页是"开放 + 已合并"混排，
        //    一个"没有 PR"说得通；这一页的档位是分开的，说"没有 PR"会把
        //    "已合并的有一堆"也一起否掉。
        switch segment {
        case .open:
            EmptyBox(
                title: RepoPullsSectionCopy.emptyOpenTitle,
                hint: RepoPullsSectionCopy.emptyOpenHint
            )
        case .closed:
            EmptyBox(
                title: RepoPullsSectionCopy.emptyMergedTitle,
                hint: RepoPullsSectionCopy.emptyMergedHint
            )
        }
    }
}

#Preview {
    ScrollView {
        RepoPullsSection(
            list: RepoSubListViewModel { _, _ in throw GitHubError.notFound },
            segment: .open,
            openTitle: "开放 (5)",
            mergedTitle: "已合并",
            now: .now,
            onSelectSegment: { _ in },
            onOpen: { _ in }
        )
        .padding(.horizontal, Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
