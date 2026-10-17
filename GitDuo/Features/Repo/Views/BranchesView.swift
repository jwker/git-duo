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
///
/// ## ⚠️ 2026-10-16 起主干是 **`List`**（NATIVE-MIGRATION P3 第二批）
///
/// 从前是 `ScrollView + VStack` + 一张 `CardBox`（`BranchRow` 自己画内边距与底线）。
/// 现在两个分区各是一个 `Section`：分隔线与行内边距由系统给，`BranchRow` 只画内容
/// ⇒ 它的 `showsSeparator` 随之删除。骨架仍走**同一个** `loaded(_:isPlaceholder:)`
/// 喂占位列表（P1 判据 ②）。
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
        List {
            content
        }
        .listStyle(.insetGrouped)
        // 主题的页面底 / 行底不交给系统（P5 才动令牌）—— 只把 `List` 自带的底色让开。
        .scrollContentBackground(.hidden)
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

    /// ⚠️ 2026-10-16 起三支**都是 `List` 的内容**（`Section`），不是一整屏 `ScrollView`
    /// —— 见 `loaded(_:isPlaceholder:)` 那条说明。
    @ViewBuilder
    private var content: some View {
        switch model.list.presentation {
        case .skeleton:
            // 骨架 = **真实的 `loaded(_:)` 喂一份占位列表**（P1 判据 ②）：
            // 骨架与内容走同一个渲染函数 ⇒ "骨架与内容失配"在结构上不可能发生。
            loaded(BranchList.placeholder(), isPlaceholder: true)

        case .content:
            if let list = model.list.value {
                loaded(list, isPlaceholder: false)
            }

        case let .failure(error):
            Section {
                failureState(error)
                    // 失败态**不是列表内容** ⇒ 不坐白卡、不画分隔线（同 `HomeView`）。
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    /// 两个分区：**分支列表** + **两个动作**（新建 / 合并）。
    ///
    /// ## ⚠️ 2026-10-16 起主干是 `List` 的 `Section`（NATIVE-MIGRATION P3 第二批）
    ///
    /// 从前是 `VStack` + `SectionHeader` + `CardBox`（`BranchRow` 自己画内边距与底线）。
    /// 现在行内边距与分隔线由系统给，`BranchRow` 只画内容 ⇒ 它的 `showsSeparator`
    /// 一并删除（它本来也关不掉系统的线）。
    ///
    /// ## ⚠️ `isPlaceholder` 是"骨架态"的开关，不是第二份渲染路径
    ///
    /// 两个分区共用这一个函数（P1 判据 ②）。⚠️ 遮罩**逐行 / 逐块加**，不加在
    /// `ForEach` 上 —— `List` 对"带修饰符的 `ForEach`"识别得不如逐行稳
    /// （同 `PinRowsSkeleton` 那条）。
    ///
    /// ⚠️ `.redacted` **不拦截点击** ⇒ 遮住的行与按钮必须一起 `allowsHitTesting(false)`：
    /// 否则骨架期点「新建分支」会真的翻开一张空弹层（P1 那条坑）。
    @ViewBuilder
    private func loaded(_ list: BranchList, isPlaceholder: Bool) -> some View {
        Section {
            ForEach(list.branches) { branch in
                BranchRow(
                    name: branch.name,
                    badgeTitle: branch.name == model.currentBranch ? BranchCopy.currentPill : nil,
                    // ⚠️ 唯一判据在领域层（决策 #53），视图只转发结果。
                    canDelete: branch.canDelete(defaultBranch: model.defaultBranch),
                    deleteTitle: BranchCopy.deleteAction,
                    onSelect: { Task { await model.switchTo(branch) } },
                    onDelete: { model.sheet = .deleteBranch(branch) }
                )
                .redacted(reason: isPlaceholder ? .placeholder : [])
                .allowsHitTesting(!isPlaceholder)
            }
            .listRowBackground(Theme.Palette.surface)
        } header: {
            // ⚠️ `margins: .none` —— 组间距由 `List` 的 section 机制给，
            //    标题再自带 22 的上边距就叠了一层（同 `SettingsView`）。
            SectionHeader(
                title: BranchCopy.sectionTitle(fullName: fullName, count: list.count),
                margins: .none
            )
        }

        Section {
            // ⚠️ 两个按钮合成**一行**：`List` 里每多一个子视图就多一行，
            //    两个按钮摆成两行会在中间插一条分隔线（本批那条判据）。
            VStack(spacing: Theme.Spacing.s) {
                ActionButton(
                    title: BranchCopy.createAction,
                    style: .primary,
                    isWorking: model.isWorking
                ) {
                    model.sheet = .createBranch
                }

                ActionButton(
                    title: BranchCopy.mergeAction(current: model.currentBranch),
                    style: .ghost
                ) {
                    model.sheet = .merge
                }
                // ⚠️ 在途时禁用（同那把锁）：`isWorking` 时三个写入口一起停。
                .disabled(model.isWorking)
            }
            .redacted(reason: isPlaceholder ? .placeholder : [])
            .allowsHitTesting(!isPlaceholder)
            // 按钮**不坐白卡**（它们是页面级动作，不是一条记录）。
            .listRowBackground(Color.clear)
        } footer: {
            Text(BranchCopy.footer)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .redacted(reason: isPlaceholder ? .placeholder : [])
        }
    }

    /// 首屏失败 —— 必须留一个出口（PRD §1 设计原则 4）。
    ///
    /// ⚠️ 走共用件 `PageFailure`（切片 7.4 收口）：本页原来那份与
    /// `RepoDetailView` / `CommitDetailView` 的**逐字相同**。
    private func failureState(_ error: GitHubError) -> some View {
        PageFailure(error: error) { Task { await model.refresh() } }
    }
}
