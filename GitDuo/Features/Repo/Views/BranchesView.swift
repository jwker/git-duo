import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 分支管理页（PRD §4.8、TECH_SPEC §9.7.1）。
///
/// 结构（原型 `SCR.branches` 逐条）：分区标题 `{仓库} · 全部分支（N）` →
/// 分支列表（当前那条带「当前」胶囊，可删的带「删除」）→「＋ 新建分支」→
/// 「合并分支到 {当前分支}…」→ 页脚说明。
///
/// ## ⚠️ 三种写操作共用一把锁
///
/// 建 / 删 / 合并都改同一条仓库的分支状态，两个同时发会造出很难看的状态
/// （一边在删 `feature/x`、一边在把它合并到 `main`）。`BranchesViewModel.isWorking`
/// 一把锁全占 —— 三个入口在途时**都**禁用。
///
/// ## ⚠️ 删除入口的有无由领域层说了算
///
/// `BranchSummary.canDelete(defaultBranch:)`（决策 #53：非默认 **且** 非受保护）
/// 是唯一判据。本视图只把它翻成一个 `Bool` 交给 `BranchRow` ——
/// 视图拿不到默认分支名，只能靠猜，而猜错的后果是给受保护分支画一个必然失败的删除按钮。
///
/// ## 三张弹层由**一个**枚举驱动
///
/// `BranchesViewModel.sheet`（见该类型的说明）。这里不再出现第二个 `isPresented`。
struct BranchesView: View {

    let fullName: String

    @State private var model: BranchesViewModel

    init(
        fullName: String,
        detail: LoadRepoDetail,
        branches: LoadBranches,
        deleteBranch: DeleteBranch,
        createBranch: CreateBranch,
        mergeBranch: MergeBranch,
        memory: any BranchMemoryStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        _model = State(initialValue: BranchesViewModel(
            fullName: fullName,
            detail: detail,
            branches: branches,
            deleteBranch: deleteBranch,
            createBranch: createBranch,
            mergeBranch: mergeBranch,
            memory: memory,
            toast: toast
        ))
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        // 原型 `SCR.branches.inline = () => '分支管理'`。
        .navigationTitle("分支管理")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
        .task { await model.start() }
        .sheet(item: $model.sheet) { route in
            presented(route)
                .presentationDetents(detents(for: route))
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 弹层

    @ViewBuilder
    private func presented(_ route: BranchesViewModel.SheetRoute) -> some View {
        switch route {
        case .createBranch:
            CreateBranchSheet(current: model.currentBranch, isWorking: model.isWorking) { name in
                await model.create(name: name)
            }

        case .merge:
            MergeSheet(
                candidates: model.mergeCandidates,
                target: model.currentBranch,
                isWorking: model.isWorking
            ) { source, message in
                await model.merge(source: source, message: message)
            }

        case let .deleteBranch(branch):
            DeleteBranchSheet(branch: branch, isWorking: model.isWorking) {
                await model.confirmDelete(branch)
            }
        }
    }

    /// 合并弹层要更高（源分支列表 + 输入框 + 两个按钮），其余 `.medium` 够。
    private func detents(for route: BranchesViewModel.SheetRoute) -> Set<PresentationDetent> {
        switch route {
        case .merge: [.medium, .large]
        case .createBranch, .deleteBranch: [.medium]
        }
    }

    // MARK: - 主区域

    @ViewBuilder
    private var content: some View {
        switch model.list.presentation {
        case .skeleton:
            skeleton

        case .content:
            if let list = model.list.value {
                loaded(list)
            }

        case let .failure(error):
            failureState(error)
        }
    }

    private func loaded(_ list: BranchList) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: BranchCopy.sectionTitle(fullName: fullName, count: list.count))

            CardBox(vertical: 0, horizontal: 0) {
                ForEach(Array(list.branches.enumerated()), id: \.element.id) { index, branch in
                    BranchRow(
                        name: branch.name,
                        badgeTitle: branch.name == model.currentBranch ? BranchCopy.currentPill : nil,
                        // ⚠️ 唯一判据在领域层（决策 #53），视图只转发结果。
                        canDelete: branch.canDelete(defaultBranch: model.defaultBranch),
                        deleteTitle: BranchCopy.deleteAction,
                        showsSeparator: index < list.branches.count - 1,
                        onSelect: { Task { await model.switchTo(branch) } },
                        onDelete: { model.sheet = .deleteBranch(branch) }
                    )
                }
            }

            ActionButton(
                title: BranchCopy.createAction,
                style: .primary,
                verticalPadding: 12,
                isWorking: model.isWorking
            ) {
                model.sheet = .createBranch
            }
            .padding(.top, Theme.Spacing.m)

            ActionButton(
                title: BranchCopy.mergeAction(current: model.currentBranch),
                style: .ghost,
                verticalPadding: 12
            ) {
                model.sheet = .merge
            }
            // ⚠️ 在途时禁用（同那把锁）：`isWorking` 时三个写入口一起停。
            .disabled(model.isWorking)
            .padding(.top, Theme.Spacing.s)

            Text(BranchCopy.footer)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.s)
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkeletonBar(height: 12, width: 200)
                .padding(.top, Theme.Spacing.l)
                .padding(.horizontal, Theme.Spacing.xxs)

            CardBox(vertical: Theme.Spacing.m, horizontal: 14) {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonBar(height: 18, width: 170)
                }
            }

            SkeletonBar(height: 40)
                .padding(.top, Theme.Spacing.m)
            SkeletonBar(height: 40)
                .padding(.top, Theme.Spacing.s)
        }
        .accessibilityHidden(true)
    }

    /// 首屏失败 —— 必须留一个出口（PRD §1 设计原则 4）。
    ///
    /// ⚠️ 走共用件 `PageFailure`（切片 7.4 收口）：本页原来那份与
    /// `RepoDetailView` / `CommitDetailView` 的**逐字相同**。
    private func failureState(_ error: GitHubError) -> some View {
        PageFailure(error: error) { Task { await model.refresh() } }
    }
}
