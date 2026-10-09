import Foundation
import GitDuoDesign
import GitDuoKit

/// 「我的收藏」管理页的状态（PRD §4.19、TECH_SPEC §9.12）。
///
/// ## ⚠️ 这一页**一发请求都不发**
///
/// 收藏夹是 GitDuo 自己的概念，GitHub **连读接口都没有**（§9.12 首段）⇒
/// 本类型只跟 `FolderStore` 打交道，不持有任何网络用例。所以这里没有
/// "加载失败"这一档可放：能失败的只有一次本地读取，而它失败的样子是空列表 ——
/// 那件事由 `summaries` 自己说明。
///
/// ## 它不算任何计数
///
/// 项目数是**派生值**（§9.12 归属表末句：不存在"手工 +1/−1"的调用点）。
/// 本类型**只把 `summaries()` 的结果原样交给视图**，从不自己加减 ——
/// 原型第一版用独立计数器，"删除收藏夹时把项搬去默认夹"那一步就让默认夹
/// 那一格纹丝不动（而屏幕上看起来只是"数字没变"）。
///
/// ## 四张弹层由一个枚举驱动
///
/// 与 `FileViewModel.sheet` 同一处置：`.sheet(item:)` + `Identifiable` 枚举，
/// 动作菜单 → 重命名 / 删除确认之间**只换值、不经过 `nil`**
/// （关一次再开一次会在中间空一帧）。
///
/// ⚠️ 枚举里**带着当时那份快照**（夹名 + 项目数），不是只存一个名字再回读：
/// §5.12 的标题与 §5.14 的说明都要回显 `{N}`，而弹层开着的时候列表可能正在重读
/// —— 那时回读会拿到新的数，于是"标题说的 3 项"与"删除后实际回落 5 项"对不上。
@MainActor
@Observable
final class FoldersViewModel {

    /// 本页的弹层路由。
    enum SheetRoute: Identifiable, Hashable, Sendable {

        /// §5.12 收藏夹操作菜单。
        case actions(name: String, count: Int)

        /// §5.13 重命名收藏夹。
        case rename(name: String)

        /// §5.14 删除收藏夹确认。
        case deleteConfirm(name: String, count: Int)

        /// §5.6 新建收藏夹（**管理页入口** —— 按钮是「创建」、只新建不收藏）。
        case create

        var id: String {
            switch self {
            case let .actions(name, _): "actions:\(name)"
            case let .rename(name): "rename:\(name)"
            case let .deleteConfirm(name, _): "delete:\(name)"
            case .create: "create"
            }
        }
    }

    /// 全部收藏夹 + 项目数，**顺序即展示顺序**（默认夹恒在第一位，由存储保证）。
    private(set) var summaries: [FolderSummary] = []

    /// 是否已经读过一次。视图用它区分"还没读"与"读出来是空的"。
    ///
    /// ⚠️ 空列表在本页**不可达**（默认夹永远在），所以这一位不驱动空态，
    /// 只驱动首帧那一下（见 `FoldersView` 的骨架说明）。
    private(set) var hasLoaded = false

    var sheet: SheetRoute?

    /// **弹层内**那一行校验提示（`nil` = 不显示）。
    ///
    /// ## ⚠️ 为什么它不是 `toast.show(…)`
    ///
    /// 提示条挂在**根容器**（`MainTabView`）上，而弹层是一层**独立呈现** ⇒
    /// **弹层开着时提示条被整块盖住**。于是"点了创建却没反应"成了用户唯一能看到的现象
    /// —— 而文案、判定、单测全都对（走查报回的就是这个，偏差第 **45** 条 / 决策 **#77**）。
    ///
    /// ⇒ 分工是：**弹层留着**的那几档写这里（视图把它画在动作按钮上方），
    /// **关弹层**的那几档照旧 `toast.show(…)` —— 那时弹层已经不在了，提示条看得见。
    ///
    /// ⚠️ 它跟着**执行动作的人**走：创建与改名都在本类型里执行 ⇒ 状态在这里、由视图传给弹层。
    /// （标签新建那个弹层是反例：动作在**它自己的** ViewModel 里执行 ⇒ 那边自己持有。）
    private(set) var sheetHint: String?

    private let store: any FolderStore
    private let toast: ToastCenter

    init(store: any FolderStore, toast: ToastCenter) {
        self.store = store
        self.toast = toast
    }

    // MARK: - 读

    /// 进页 / 下拉刷新 / 每次改动之后重读。
    ///
    /// ⚠️ **重读而不是就地改数组**：一条归属的变动会同时改两个夹的计数
    /// （源夹 −1、目标夹 +1，§9.12 归属表），就地改就得在这里再实现一遍那条规则
    /// —— 而它已经在 `FolderStore` 里有一份实现、在领域层有单测了。
    func load() async {
        summaries = await store.summaries()
        hasLoaded = true
    }

    // MARK: - 用户动作

    func openActions(_ summary: FolderSummary) {
        // 开弹层先清一次：上一次那一行不该留到这一次（同 `sheet` 换值时不留旧快照的理由）。
        sheetHint = nil
        sheet = .actions(name: summary.name, count: summary.itemCount)
    }

    func openCreate() {
        sheetHint = nil
        sheet = .create
    }

    /// **管理页入口**的新建（§5.6 后半）：只新建，**不改变任何仓库的收藏状态**。
    ///
    /// ⚠️ 重名时**只提示、不创建**，而且是**留在弹层里**（用户还能改名再试）。
    /// 仓库详情那个入口（§5.6 前半）的重名处置**有意不同**：提示"已为你选中"
    /// 并照样把仓库放进去 —— 两句话的差别就是那条行为差别的唯一可见证据
    /// （见 `FolderCopy.duplicateInManagement` 的说明，别合并）。
    ///
    /// ⚠️ 两条校验的提示落点是 **`sheetHint`（弹层内那一行）**，不是提示条 ——
    /// 这两档**不关弹层**，而提示条会被弹层盖住（见 `sheetHint` 的说明 / 决策 #77）。
    func create(name: String) async {
        // 这一次的结果说了算，先清上一次的。
        sheetHint = nil

        switch await store.create(name: name) {
        case let .created(created):
            toast.show(FolderCopy.created(created))
            sheet = nil
            await load()

        case .duplicate:
            sheetHint = FolderCopy.duplicateInManagement

        case .emptyName:
            sheetHint = FolderCopy.emptyName
        }
    }

    /// §5.13 重命名。
    ///
    /// ⚠️ 五档的**可见差别**（PRD §5.13 逐条）：
    ///
    /// | 结果 | 弹层 | 提示 | 落点 |
    /// |---|---|---|---|
    /// | 改名成功 | 关 | `已重命名为「{新名}」` | 提示条 |
    /// | **与原名相同** | 关 | **不给任何提示** | — |
    /// | 空名 / 与别的夹重名 | **留着** | 对应的那一句 | **弹层内那一行**（决策 #77） |
    ///
    /// 第二行是**有意**的（`FolderRenameOutcome.unchanged` 的说明）：它不是失败，
    /// 是"用户按了保存但等于没改"；对它报一句"已重命名为 X"会让用户下一次
    /// 怀疑别的提示也是假的。
    ///
    /// ⚠️ 第三列的落点不一样，正是因为**弹层留不留**：留着 ⇒ 提示条看不见（盖住），
    /// 关掉 ⇒ 看得见。**别把两列合成一列**（合了必然有一处静默失效）。
    func rename(from oldName: String, to newName: String) async {
        sheetHint = nil

        switch await store.rename(from: oldName, to: newName) {
        case let .renamed(_, to):
            toast.show(FolderCopy.renamed(to: to))
            sheet = nil
            await load()

        case .unchanged:
            sheet = nil

        case .emptyName:
            sheetHint = FolderCopy.emptyName

        case .duplicate:
            sheetHint = FolderCopy.duplicateInRename

        case .protectedDefault:
            // 界面**不给**这一行入口（默认夹那一行不是按钮），这里是逻辑层的
            // 第二道拦截（§9.12：「UI 不给入口 + 逻辑层二次拦截」）。
            // 文案取 PRD §4.19 页脚那句逐字（`FolderCopy.defaultNotRenamable`）。
            toast.show(FolderCopy.defaultNotRenamable)
            sheet = nil

        case .notFound:
            // ⚠️ 本页**不可达**：能删夹的只有本页，而弹层开着的时候它删不了自己。
            // 处理方式是"关掉 + 重读列表"—— 让屏幕自己说话（那一行已经不存在了），
            // **不编一句文档里没有的话**（同偏差第 27 条的处置）。
            sheet = nil
            await load()
        }
    }

    /// §5.14 删除。
    ///
    /// ⚠️ 成功那一句里的 `{moved}` **必须真的报出来**（`FolderCopy.deleted`）：
    /// 回落是**静默发生**的，少了这半句，用户看到的是"我删了一个夹，
    /// 那 12 个项目去哪了"（屏幕上什么都不会再提）。
    func delete(name: String) async {
        switch await store.delete(name: name) {
        case let .deleted(deleted, moved):
            toast.show(FolderCopy.deleted(name: deleted, moved: moved))
            sheet = nil
            await load()

        case .protectedDefault:
            // 与上面重命名同理：界面到不了，逻辑层拦下来。
            // 这一句是原型 `deleteFolderConfirm` 逐字（`FolderCopy.defaultNotDeletable`）。
            toast.show(FolderCopy.defaultNotDeletable)
            sheet = nil

        case .notFound:
            // 同 `rename` 的最后一档：不编话，关掉 + 让列表说话。
            sheet = nil
            await load()
        }
    }
}
