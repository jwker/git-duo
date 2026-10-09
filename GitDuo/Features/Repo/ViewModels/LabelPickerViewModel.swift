import Foundation
import GitHubAPI
import GitDuoKit

/// 标签选择 / 新建弹层（PRD §5.2、决策 #56）的状态。
///
/// ## 一个弹层服务两处（2026-10-08 用户裁定）
///
/// | 宿主 | 选中集合是什么 | 操作之后的后果 |
/// |---|---|---|
/// | §4.10 新建 Issue 页 | 这条 Issue 要带的标签 | 刷新标签行（不发请求） |
/// | §4.4 分区二「筛选」 | 要筛的标签（**走服务端**，决策 #56） | 结果区按新标签重新加载 |
///
/// 两处的**弹层本体完全一样**（同样的标题、同样的两段、同样的色板与提示），
/// 差别只在宿主拿这个选中集合去做什么 ⇒ 本件不认识任何一个宿主，
/// 它只负责"把标签库取回来 + 把选中的标签交出去"。
///
/// ## ⚠️ 弹层的选中集合**不在本件里**
///
/// 它由宿主拥有（`LabelPickerSheet.selected`），本件通过 `onToggle*` 通知变化。
/// 理由是两处的"变化之后要发生什么"不同（一处只改本地集合、一处要重取数据），
/// 而那是**宿主的决定**，不是弹层的。
///
/// ## ⚠️ 标签库为空 ≠ 加载失败
///
/// `library == nil` 且 `loadError == nil` ⇒ **还没取过**（骨架态）；
/// `library` 非 nil 且 `labels` 为空 ⇒ 这个仓库**确实没有标签**（空态）。
/// 折成一个 `isEmpty` 会让一次网络抖动看起来像"我的标签全没了"
/// （`LabelCatalog.all` 的文档写了这条）。
@MainActor
@Observable
final class LabelPickerViewModel {

    private let catalog: LabelCatalog
    private let fullName: String

    /// 取回来的标签库；`nil` = **还没取过**（不是"取到了但没有"）。
    private(set) var library: LabelLibrary?

    private(set) var isLoading = false

    /// 取标签库失败。**与 `library` 并存** —— 重试时不该把已经拿到的那份抹掉。
    private(set) var loadError: GitHubError?

    /// **弹层内**那一行（`nil` = 不显示）：名称为空、或请求本身失败。
    ///
    /// ## ⚠️ 为什么它不是 `toast.show(…)`（决策 #77 / 偏差第 45 条）
    ///
    /// 提示条挂在**根容器**上，而弹层（`.sheet`）是一层**独立呈现** ⇒ **弹层开着时被整块盖住**。
    /// 而这一支恰恰是**不关弹层**的那种（用户还得接着打字 / 再点一次）⇒
    /// 走提示条的表现是"**点了没反应**"。
    ///
    /// ## ⚠️ 它与 `loadError` 是**两个操作的两个字段**，不能共用
    ///
    /// 共用的表现是"取库成功之后再新建失败 ⇒ 列表照画、而那句话无处可去"，
    /// 或者反过来（新建失败被当成"标签库没取到"、把已经拿到的整份列表换成一块失败块）。
    /// 而这两种都**不报错**，只是屏幕上少一句或错一块。
    /// （同理：本字段也**不**与"名称为空"共用一个布尔量 —— 那两句话不同。）
    ///
    /// ## ⚠️ 它取代了原先的 `createError: GitHubError?`
    ///
    /// 原先失败**抛给宿主**（`onFailure` 回调，宿主再 `toast.show(ActionCopy.failed)`），
    /// 那是因为"弹层不认识提示通道"这条设计。而弹层内那一行**就是弹层自己的东西**
    /// ⇒ 失败不再往外报，`createError` 随之失去唯一的读者（留着一个没人读的 `private(set)`
    /// 字段，下一个读代码的人会以为它有用）。**文案一个字都没变**（`ActionCopy.failed`）。
    private(set) var creationHint: String?

    /// 新建标签的名称输入。
    var newName = ""

    /// 色板上选中的色值（**不带 `#`**）。初值 = 色板第一格（原型 `pickedClr = LBL_COLORS[0]`）。
    var pickedColor = LabelPalette.initial

    /// 「创建并选中」在途（防重复提交，§8.5「操作类」）。
    private(set) var isCreating = false

    init(catalog: LabelCatalog, fullName: String) {
        self.catalog = catalog
        self.fullName = fullName
    }

    /// 进弹层取一次标签库。
    ///
    /// ⚠️ **取到过就不再发请求**（`guard library == nil`）：弹层在一次会话里会被
    /// 反复打开关闭（原型每次 `toggle` 都重开一次），每次都重取会把配额烧在同一个
    /// 不变的列表上。要强制刷新走 `retry()`（只在失败之后有入口）。
    func load() async {
        guard library == nil, !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            library = try await catalog.all(fullName: fullName)
            // ⚠️ 成功之后**清掉上一次的错误**：不然重试成功时弹层里还挂着一行红字。
            loadError = nil
        } catch {
            loadError = Self.failure(from: error)
        }
    }

    /// 失败之后的重试（弹层内失败块的唯一出口）。
    func retry() async {
        loadError = nil
        await load()
    }

    /// 点「创建并选中」。
    ///
    /// - Returns: 三种结局（`LabelCreation`）；`nil` = 这一发**没有结局** ——
    ///   被在途守卫挡住了（重入）。
    ///
    /// ⚠️ 空名与重名**不发请求**（`LabelCatalog.create` 提前本地挡掉），它们仍算"有结局"。
    ///
    /// ⚠️ 建成功之后**要把新标签加进本地那份库里**（原型的 `REPO_LABELS.push(l)`）：
    /// 不加的话，用户刚建的标签不在下面那份列表里 —— 他看得见的反馈只有一句提示，
    /// 而"我建的标签去哪了"是一个必然会被问的问题。
    ///
    /// ⚠️ 失败**不降级成任何一种成功**：`LabelCatalog.create` 只把"重名"当成正常路径，
    /// 其余（422 / 网络）都抛 —— 这里收成 `creationHint` 里那句通用失败提示
    /// （**不再抛给宿主**：弹层内那一行就是弹层自己的东西，见 `creationHint` 的说明）。
    ///
    /// ⚠️ 三档里**只有"空名"与"失败"**会写 `creationHint` ——
    /// 另外两档（重名 / 建成）弹层会**关掉**，那时照旧由宿主发提示条（看得见）。
    func create() async -> LabelCreation? {
        guard !isCreating else { return nil }

        isCreating = true
        // 这一次的结果说了算，先清上一次的。
        creationHint = nil
        defer { isCreating = false }

        do {
            let result = try await catalog.create(
                fullName: fullName,
                name: newName,
                colorHex: pickedColor,
                // ⚠️ 手上那份库就是"哪些名字已经存在"的唯一依据
                //    （`LabelCatalog.create` 据此提前挡掉必败的那一次请求）。
                existing: library?.labels ?? []
            )

            switch result {
            case let .created(label):
                if let current = library {
                    library = LabelLibrary(
                        labels: current.labels + [label],
                        hasMore: current.hasMore
                    )
                }
                // 建完把输入框清掉：留着它，用户会以为没建成、再点一次。
                newName = ""

            case .alreadyExists:
                // 关弹层 ⇒ 由宿主发提示条（"已存在，已为你选中"），弹层内不留话。
                break

            case .emptyName:
                // ⚠️ 这一档**不关弹层** ⇒ 话画在这里（`IssueCopy.emptyLabelNameHint`）。
                creationHint = IssueCopy.emptyLabelNameHint
            }

            return result
        } catch {
            // ⚠️ 请求失败同样**不关弹层**（用户还能改个名再试）⇒ 也画在弹层里。
            //    文案取切片 7.4 收的那句通用正本（§5.2 没给这条路径的话）。
            creationHint = ActionCopy.failed
            return nil
        }
    }

    /// 把任意错误收敛成 `GitHubError`（同其余 ViewModel：映射失败归 `.decoding`，
    /// **不是** `.transport` —— 后者会谎称网络问题、给出"检查网络"的错误引导）。
    ///
    /// ⚠️ 现在它**只服务 `load()`**（取标签库那一支）—— 新建那一支不再需要它，
    /// 因为失败不再往外报类型、只写一句给用户看的话（见 `creationHint`）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}
