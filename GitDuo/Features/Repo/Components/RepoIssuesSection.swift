import GitHubAPI
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 仓库详情「Issues」分区（PRD §4.4 分区二、TECH_SPEC §9.8.1、决策 #56 / #61）。
///
/// 结构：分段条（`开放 (N)` / `已关闭` / `筛选`）→ 已选标签行（没筛时不画）→
/// Issue 卡片列表 → 「＋ 新建 Issue」。
///
/// ## 与探索 Issues 列表（§4.14）的四处不同，全部是**有意**的
///
/// | | §4.14 | 本分区 |
/// |---|---|---|
/// | 档位 | 只有「开放」（决策 #38） | 「开放」+「已关闭」两档 |
/// | 筛选 | 无 | 标签多选（**走服务端**，决策 #56） |
/// | 卡片标签 | 不画 | 画（`showsLabels: true`，决策 #61） |
/// | 新建入口 | 无 | 有 |
///
/// 卡片本身**只有一份**（`IssueCard`，切片 7 搬到了 `Repo/Components/`）。
/// 首屏骨架也复用同一份（`ExploreSubListSkeleton`）—— 那件的几何与卡片是绑的，
/// 抄第二份等于给自己留一个"卡片改了、骨架没跟"的坑。
/// ⚠️ 它住在 `Features/Explore/`：本片没有搬它（决策 #61 只点了两个卡片），
/// 但**定义仍然只有一处**。
///
/// ## ⚠️ 取数不由本件发起
///
/// 两档各自的加载时机在 `RepoSectionViewModel`（**切到这一档才取**，且
/// **每档各自持有游标与失败态**）—— 那是一条业务规则，散进视图就没人守得住。
/// 本件只做两件事：画，以及把点击翻成对 `list` 的调用。
struct RepoIssuesSection: View {

    /// **当前档**的取数状态机 —— 两档各持一份，成对存在 `RepoSectionViewModel` 里。
    ///
    /// ⚠️ 传实例而不是"当前档的数据"：分页（滚到底自动加载 / 底部重试）要能
    /// **作用在这一档上**，而那个状态只有它有。
    let list: RepoSubListViewModel<IssueRow>

    /// 当前选中的档。
    let segment: RepoSectionSegment

    /// 两格的文案（**已算好**，含计数）。
    ///
    /// ⚠️ 计数为什么由外面给：`开放 (N)` 里的 `N` 要区分"这一档还没加载过"与
    /// "确实是 0"，而**另一档**的加载状态只有 ViewModel 知道
    /// （本件手上只有当前档的 `list`）。
    let openTitle: String
    let closedTitle: String

    /// 已选标签（空 = 没筛）。
    ///
    /// ⚠️ 必须写全 `GitDuoKit.Label` —— 本文件 import 了 SwiftUI，而 `SwiftUI.Label`
    /// 与它**同名**，裸写是硬歧义（同 `SelectedLabelRow` 的说明）。
    let selectedLabels: [GitDuoKit.Label]

    /// 「现在」由调用方给（同 `IssueCard`：不在 `body` 里取 `Date()`）。
    let now: Date

    let onSelectSegment: (RepoSectionSegment) -> Void

    /// 点「筛选」—— 打开标签多选弹层（§5.2，与新建 Issue 页**同一个**弹层）。
    let onTapFilter: () -> Void

    /// 点掉一颗已选标签（同上的 `GitDuoKit.Label`）。
    let onRemoveLabel: (GitDuoKit.Label) -> Void

    /// 点一张卡片 —— 参数是 Issue 编号。
    let onOpen: (Int) -> Void

    /// 点「＋ 新建 Issue」。
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            segmentBar
                // 原型 `.segbar` 与列表之间的间隔。有标签行时它自己带下边距，
                // 这里就不重复给（两处都给会变成 12 + 标签行高度 + 8，列表被推得太远）。
                .padding(.bottom, selectedLabels.isEmpty ? Theme.Spacing.m : Theme.Spacing.xs)

            if !selectedLabels.isEmpty {
                // ⚠️ 不传 `addLabelTitle` —— 这一行的末尾**没有**那颗「＋ 标签 / 新建」：
                //    本分区的「筛选」按钮在分段条上（它才是打开弹层的入口）。
                //    这是两处宿主唯一的形状差别（见 `SelectedLabelRow` 的说明）。
                SelectedLabelRow(
                    labels: selectedLabels,
                    onRemove: onRemoveLabel,
                    hint: RepoIssuesSectionCopy.cancelFilterHint
                )
                .padding(.bottom, Theme.Spacing.m)
            }

            content

            if showsCreateButton {
                createButton
                    .padding(.top, Theme.Spacing.m)
            }
        }
    }

    // MARK: - 分段条

    private var segmentBar: some View {
        SegmentedBar(
            segments: [
                .init(id: RepoSectionSegment.open.rawValue, title: openTitle),
                .init(id: RepoSectionSegment.closed.rawValue, title: closedTitle),
                // 第三格是**按钮**、不是分段（2026-10-08 裁定）：点它开标签弹层，
                // 它自己**永远不高亮**（`isAction`）—— "选中"这个状态只属于上面两档。
                .init(id: Self.filterID, title: RepoIssuesSectionCopy.filterAction, isAction: true),
            ],
            selectedID: segment.rawValue,
            // ⚠️ 本件在**已经内缩的内容区**里（`RepoSectionListView` 的外层有页面边距）
            //    ⇒ 分段条不能再自带一层，否则会缩成 32pt、与卡片左边缘对不齐。
            padsHorizontally: false
        ) { picked in
            if picked.isAction {
                onTapFilter()
            } else if let picked = RepoSectionSegment(rawValue: picked.id) {
                onSelectSegment(picked)
            }
        }
    }

    /// 「筛选」那一格的 `id` —— 它不参与选中比对（`isAction` 已经保证），
    /// 但仍需要一个稳定的值给 `ForEach`。
    private static let filterID = "filter"

    // MARK: - 列表

    @ViewBuilder
    private var content: some View {
        switch list.content {
        case .skeleton:
            ExploreSubListSkeleton()

        case .items:
            rows

        case .needsMore, .empty:
            // 「还有下一页但这一页被滤空了」与「确实一条都没有」共用同一个空态框 ——
            // 两者在分段条上仍可分辨（前者写着 `开放 30+`，是个下界）。
            emptyBox

        case let .failure(error):
            // ⚠️ 分区内的失败**不掀翻整页**（§8.5）：头部与分段条都还在。
            SectionFailure(error: error) { Task { await list.refresh() } }
        }
    }

    private var rows: some View {
        // 只算一次：在 `onAppear` 里逐行判断"是不是最后一行"是 O(n²)。
        let items = list.rows
        let lastID = items.last?.id

        return VStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, row in
                Button {
                    onOpen(row.number)
                } label: {
                    // ⚠️ `showsLabels: true` —— 这是本分区与 §4.14 在卡片上的**唯一**差别
                    //    （决策 #61 用参数表达，不复制组件）。
                    IssueCard(row: row, now: now, showsLabels: true)
                }
                .buttonStyle(.plain)
                .onAppear {
                    // §4.4：普通列表**滚到底自动加载**（只有搜索用「加载更多」按钮）。
                    // 只对最后一行触发，否则每出现一行都打一次请求。
                    if row.id == lastID {
                        Task { await list.loadMore() }
                    }
                }
            }

            listFooter
        }
    }

    /// 列表底部：分页在途 → 转圈；分页失败 → 重试行。**不遮挡已有内容**（§8.5）。
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
        // ⚠️ 两档各说各的：说"没有 Issue"会把"已关闭的一堆"也一起否掉（§4.4 分区二）。
        switch segment {
        case .open:
            EmptyBox(
                title: RepoIssuesSectionCopy.emptyOpenTitle,
                hint: RepoIssuesSectionCopy.emptyOpenHint
            )
        case .closed:
            EmptyBox(
                title: RepoIssuesSectionCopy.emptyClosedTitle,
                hint: RepoIssuesSectionCopy.emptyClosedHint
            )
        }
    }

    // MARK: - 新建入口

    /// ⚠️ **只在有内容时画**。
    ///
    /// 三个状态下它都不该出现：
    /// - 骨架态：还没确认这个仓库有没有 Issue，先给一个"新建"显得答非所问；
    /// - 失败态：连列表都没拿到，此时能做的只有重试（§8.5 的"失败态只留一个出口"）；
    /// - 空态：**这一条是产品判断** —— 空态框已经说了"没有开放的 Issue"，
    ///   下面紧跟一个"新建 Issue"是这一页最自然的下一步 ⇒ **空态要画它**。
    ///
    /// 所以判据是"骨架与失败时不画"，而不是"有内容才画"。
    private var showsCreateButton: Bool {
        switch list.content {
        case .skeleton, .failure: false
        case .items, .empty, .needsMore: true
        }
    }

    private var createButton: some View {
        ActionButton(
            title: RepoIssuesSectionCopy.newIssueAction,
            style: .primary,
            // 原型 `style="width:100%;padding:12px"` —— 12 是原型原值覆写。
            verticalPadding: 12,
            action: onCreate
        )
    }
}

#Preview {
    @Previewable @State var environment = AppEnvironment()

    ScrollView {
        RepoIssuesSection(
            list: RepoSubListViewModel { _, _ in throw GitHubError.notFound },
            segment: .open,
            openTitle: "开放 (12)",
            closedTitle: "已关闭",
            selectedLabels: [
                Label(name: "bug", colorHex: "d73a4a"),
                Label(name: "help wanted", colorHex: "0e8a16"),
            ],
            now: .now,
            onSelectSegment: { _ in },
            onTapFilter: {},
            onRemoveLabel: { _ in },
            onOpen: { _ in },
            onCreate: {}
        )
        .padding(.horizontal, Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
