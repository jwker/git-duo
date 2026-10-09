import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 「我的收藏」管理页（PRD §4.19、TECH_SPEC §9.12）。
///
/// 结构（自上而下，顺序即原型 `SCR.folders.render`）：
/// 顶部说明行 · 收藏夹卡片（每行 = 书签图标 + 名称 + `{N} 项` + 「默认」标记或 `›`）·
/// 底部「新建收藏夹」· 两行页脚说明。
///
/// ## ⚠️ 这一页**一个请求都不发**
///
/// 收藏夹是 GitDuo 的私有概念，GitHub **连读接口都没有**（§9.12）⇒ 三档状态
/// （骨架 / 内容 / 失败）里**只有骨架与内容**：没有"加载失败"可放。
/// 唯一能发生的是"还没读出来"，那是首帧。
///
/// ## ⚠️ 两行道别（这一页最容易做错的都在这）
///
/// 1. **「默认收藏夹」那一行不是按钮** —— 行尾是「默认」标记，点它**不该有任何反应**。
///    走 `action: nil` 而不是 `.disabled`：后者会让它变灰、像"暂时不可用"（决策 #51）。
/// 2. **项目数全是派生值** —— 视图拿到的就是 `FolderSummary.itemCount`，
///    这里不做任何加减（§9.12：不存在"手工 +1/−1"的调用点）。
///
/// ## 四张弹层由一个枚举驱动
///
/// 见 `FoldersViewModel.SheetRoute`：动作菜单 → 重命名 / 删除确认之间只换值，
/// 不经过 `nil`（关一次再开一次会在中间空一帧）。
struct FoldersView: View {

    @State private var model: FoldersViewModel

    /// 依赖由**组合根**经 `RouteView` 传下来（本视图不构造存储）。
    ///
    /// ⚠️ 传进来的必须是**全 App 那一个** `FolderStore`：仓库详情页的
    /// 「选择收藏列表」弹层读的是同一份数据（§9.12 末段）。各建一份的表现是
    /// "在一边建了夹、另一边看不见"，而两边看起来都正常。
    init(store: any FolderStore, toast: ToastCenter) {
        _model = State(initialValue: FoldersViewModel(store: store, toast: toast))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                subtitle

                folderCard
                    // 原型 `.menu-card{margin-bottom:12px}`。
                    .padding(.bottom, Theme.Spacing.m)

                ActionButton(
                    title: FolderCopy.newFolderAction,
                    style: .ghost,
                    // 原型 `style="width:100%;padding:11px"`。
                    verticalPadding: 11
                ) {
                    model.openCreate()
                }

                footnotes
                    // 原型页脚 `margin-top:10px`（10 不在 4pt 阶里 ⇒ 写原值，
                    // 同 `SheetHint` 的 `padding-top:6`）。
                    .padding(.top, 10)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        .navigationTitle(FolderCopy.pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 下拉刷新：这一页没有网络，但**顺带把这份本地快照重读一次** ——
        // 与其余每一个页面挂 `.refreshable` 是同一条页面级约定（原型没有它，
        // 因为它是静态 HTML）。也让"另一个入口刚改过收藏夹"能手动对上表。
        .refreshable { await model.load() }
        .task { await model.load() }
        .sheet(item: $model.sheet) { route in
            presented(route)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 顶部说明行

    /// 原型 `.t3{padding:2px 2px 4px;line-height:1.6}`。
    ///
    /// ⚠️ `line-height:1.6` 在 SwiftUI 里没有对应物（单个 `Text` 的 `lineSpacing`
    /// 只作用于**折行之间**），这里取 `SheetHint` 用的同一档（2pt）——
    /// 这一行在窄屏上会折成两行，那点行距就是给折行用的。
    private var subtitle: some View {
        Text(FolderCopy.pageSubtitle)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            .lineSpacing(Theme.Spacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Spacing.xxs)
            .padding(.bottom, Theme.Spacing.xs)
    }

    // MARK: - 收藏夹卡片

    @ViewBuilder
    private var folderCard: some View {
        if model.hasLoaded {
            folderList
        } else {
            // 首帧：本地读取还没回来 ⇒ 骨架（§8.5：加载中 ≠ 无数据）。
            //
            // ⚠️ 它不是"网络请求的骨架" —— 这一页不发请求，读的是本机那份。
            // 之所以仍然画：不画的话第一帧会是一个**零行的卡片**（1pt 描边的一条细线），
            // 那比"等一下"更像个 bug。
            folderSkeleton
        }
    }

    private var folderList: some View {
        // 末行不画分隔线（原型 `.menu-item:last-child{border-bottom:none}`）——
        // 卡片不知道自己在装几行，所以由调用方传（见 `MenuCard` 的说明）。
        let list = model.summaries
        let lastID = list.last?.id

        return MenuCard {
            ForEach(list) { summary in
                MenuRow(
                    systemImage: GitHubIcon.bookmark,
                    title: summary.name,
                    value: FolderCopy.itemCount(summary.itemCount),
                    // 自建夹行尾是 `›`、默认夹行尾是「默认」标记（§4.19 第 2 条逐字）。
                    accessory: summary.isDefault
                        ? .tag(FolderCopy.defaultTag)
                        : .chevron,
                    showsSeparator: summary.id != lastID,
                    // ⚠️ 默认夹**不给动作**（`nil` ⇒ 根本不是 Button，不是变灰）。
                    action: summary.isDefault ? nil : { model.openActions(summary) }
                )
            }
        }
    }

    /// 收藏夹卡片的骨架 —— 尺寸照着 `MenuRow` 写（图标槽 22 / 上下 13 / 左右 14）。
    ///
    /// ⚠️ 行数 3 是**假想值**：本页真实行数 = 默认夹 + 用户自建，无从预知
    /// （同 `StarRowSkeleton` 的"默认 4 行"）。取 3 是因为默认夹 + 常见的两个自建夹
    /// 已经是这张卡片的常见样子，而它只在一帧里可见。
    ///
    /// ⚠️ §8.5 第 1 条：`MenuRow` 的内边距或图标槽一改，这里的数字必须跟着改
    /// —— 不跟的话数据到达时整张卡会跳一下。
    private var folderSkeleton: some View {
        MenuCard {
            ForEach(0 ..< 3, id: \.self) { _ in
                HStack(spacing: 12) {
                    // `MenuRow` 里图标是 `.frame(width: 22)` 的 19pt 方框。
                    SkeletonBar(height: 19, width: 22)
                    SkeletonBar(height: 15, width: 120)
                    Spacer(minLength: 0)
                    // 行尾那个 `{N} 项`（`caption` 一档）。
                    SkeletonBar(height: 11, width: 34)
                }
                .padding(.vertical, 13)
                .padding(.horizontal, 14)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.Palette.borderSoft)
                        .frame(height: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - 页脚

    /// 两行说明（原型一个 `div` 里的 `<br>`，PRD §4.19 拆成两条常量）。
    ///
    /// 这里用 `\n` 拼回一段而不是两个 `Text`：原型那两行是**同一个块**里的换行
    /// （共享 `line-height:1.7`），拆成两个 `Text` 就得自己造一档行距。
    private var footnotes: some View {
        Text(FolderCopy.pageFooterLine1 + "\n" + FolderCopy.pageFooterLine2)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            .lineSpacing(Theme.Spacing.xxs)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - 弹层

    @ViewBuilder
    private func presented(_ route: FoldersViewModel.SheetRoute) -> some View {
        switch route {
        case let .actions(name, count):
            FolderActionSheet(
                name: name,
                itemCount: count,
                // 两个动作各自把 `sheet` 换成另一张 —— **不经过 `nil`**
                // （见 `FolderActionSheet` 的说明）。
                onRename: { model.sheet = .rename(name: name) },
                onDelete: { model.sheet = .deleteConfirm(name: name, count: count) }
            )

        case let .rename(name):
            RenameFolderSheet(name: name) { newName in
                await model.rename(from: name, to: newName)
            }

        case let .deleteConfirm(name, count):
            DeleteFolderSheet(name: name, itemCount: count) {
                await model.delete(name: name)
            }

        case .create:
            // **管理页入口**（§5.6 后半）：按钮是「创建」，只新建、不收藏任何仓库。
            NewFolderSheet(entry: .management) { name in
                await model.create(name: name)
            }
        }
    }
}

#Preview {
    @Previewable @State var environment = AppEnvironment()

    NavigationStack {
        FoldersView(store: environment.folders, toast: environment.toast)
    }
    .environment(environment)
}
