import Foundation

/// 收藏夹相关的**全部可见文案**（PRD §4.19 / §5.5 / §5.6 / §5.12 / §5.13 / §5.14、TECH_SPEC §9.12）。
///
/// ## 为什么放在领域层
///
/// 与 `SearchCopy` / `IssueCopy` 同源：这些是**可见契约**（PRD §7 的那张清单逐条列着它们），
/// 而"什么时候该说哪一句"是一条业务规则，不是排版选择。放进 `GitDuoKit` 才能被单测钉住
/// —— App target 没有测试 target。
///
/// ## ⚠️ 文案**逐字取自原型** `scripts/11-favorites.js`
///
/// 按事实优先级（原型 > TECH_SPEC > PRD）照抄，标点（全角括号、`·`、`「」`）一律不动。
/// PRD §7 的清单与原型在这几处是一致的，可以互相对照。
public enum FolderCopy {

    // MARK: - 页面级

    /// 管理页的推入标题（原型 `SCR.folders.inline`）。
    public static let pageTitle = "我的收藏"

    /// 管理页顶部说明行（原型逐字）。
    public static let pageSubtitle = "私人整理 · 仅你自己可见，不影响仓库的 Star 数"

    /// 管理页底部的两行说明（原型逐字，`<br>` 拆成两条）。
    public static let pageFooterLine1 = "「默认收藏夹」是新收藏的默认去处，不可重命名或删除"
    public static let pageFooterLine2 = "删除其它收藏夹不会取消 Star，也不会影响仓库本身"

    /// 管理页底部那颗按钮（原型逐字，带一个 `＋`）。
    public static let newFolderAction = "新建收藏夹"

    /// 内置默认收藏夹行尾的标记（原型 `<span class="ftag">默认</span>`）。
    public static let defaultTag = "默认"

    /// 项目数（原型 `${favTotal(f.n)} 项`）。
    ///
    /// ⚠️ **不加千分位也不缩写**：这是"我自己整理了几条"，量级很小，
    /// 而千分位在这里只会让四个数字看起来像四种格式。
    public static func itemCount(_ count: Int) -> String { "\(count) 项" }

    // MARK: - 仓库详情页那个入口（PRD §4.13 的「我的收藏」分区）

    /// 没收藏时那颗按钮（原型 `10-explore-repo.js` 逐字）。
    public static let favoriteAction = "收藏到我的列表"

    /// 已收藏时那颗按钮的前半句（原型 `${svg(I.bm)} 已收藏 · ${favFolderOf(p.repo)}`）。
    ///
    /// 夹名跟在它后面由视图拼 —— 这里只给固定部分，免得把"哪个夹"变成一个文案参数。
    public static let favoritedActionPrefix = "已收藏 · "

    /// 没收藏时按钮下面那行灰字（原型逐字）。
    public static let favoriteHintIdle = "私人收藏夹，不影响仓库的 Star 数"

    /// 已收藏时按钮下面那行灰字（原型逐字）。
    public static let favoriteHintFavorited = "已加入收藏 · 再点可选择 / 更换收藏列表"

    // MARK: - 收藏 / 取消的轻提示

    /// 首次收藏（原型 `favNow` 逐字）。
    ///
    /// ⚠️ 后半句「再点可选择列表」是**一次性的引导**，而它必须在第一次兑现：
    /// 用户第一次点收藏时并不知道"再点一下能换夹"这件事（`TECH_SPEC §9.12` 的两段式交互）。
    public static let favoritedToDefault = "已收藏到「默认收藏夹」（私人，不影响 Star 数）· 再点可选择列表"

    /// 换到别的夹（原型 `pickFav` 逐字）。
    public static func favorited(to folderName: String) -> String {
        "已收藏到「\(folderName)」（私人收藏夹）"
    }

    /// 取消收藏（原型 `pickFav` 逐字）。
    public static let removed = "已从收藏移除"

    // MARK: - 校验

    /// 空名（原型 `createFav` / `createFolder` / `renameFolder` 三处同一句）。
    ///
    /// ⚠️ **三处都画在弹层内**（决策 #77，2026-10-09）：这三个入口的"空名"**都不关弹层**
    /// （用户还得接着打字），而提示条挂在根容器上、会被弹层整块盖住
    /// ⇒ 它们一律走 `SheetFailureHint`（动作按钮上方那一行），**不再走提示条**。
    public static let emptyName = "先输入收藏夹名称"

    /// **仓库详情入口**的重名提示（原型 `createFav` 逐字）。
    ///
    /// ⚠️ 与下面那句**不是重复** —— 见 `duplicateInManagement`。
    ///
    /// ⚠️ 载体是**提示条**（不是弹层内那一行）：这一档会**关掉弹层**（原型 `closeSheet()`）
    /// ⇒ 提示条看得见。这也是它与下面那句的**第二处**差别（第一处是那半句话）。
    public static let duplicateInRepository = "收藏夹已存在，已为你选中"

    /// **管理页入口**的重名提示（原型 `createFolder` 逐字）。
    ///
    /// ## ⚠️⚠️ 两个入口的重名处置**有意不同**（`TECH_SPEC §9.12`）
    ///
    /// | 入口 | 按钮 | 重名时 | 提示画在哪 |
    /// |---|---|---|---|
    /// | 仓库详情（§5.6 前半） | `创建并收藏` | 提示**并自动选中**，照样把仓库放进去 | 提示条（**关**弹层） |
    /// | 管理页（§5.6 后半） | `创建` | 只提示，**不创建、不动任何仓库** | **弹层内那一行**（**不关**弹层） |
    ///
    /// 所以这两句话的差别（"已为你选中" vs 没有）**是行为差别的唯一可见证据**。
    /// 谁要是把它们合并成一句，两个入口就会悄悄变成同一个 —— 而屏幕上只差半句话，
    /// 评审时几乎看不出来。**看到这里请把两句一起读一遍。**
    public static let duplicateInManagement = "收藏夹已存在"

    /// 重命名时与**其它**夹重名（原型 `renameFolder` 逐字）。
    ///
    /// ⚠️ 与上面两句都不一样：这一处的语境是"你正在改名字"，所以主语是"名字"而不是"夹"。
    ///
    /// ⚠️ 载体是**弹层内那一行**：这一档不关弹层（用户改个名字就能过），
    /// 而提示条会被弹层盖住（决策 #77）。
    public static let duplicateInRename = "已有同名收藏夹"

    /// 试图重命名默认夹（**原型没有这一句** —— 它那一行不给入口，走不到）。
    ///
    /// ⚠️ 这是**规格未给**的一处，按 PRD §4.19 页脚那句「不可重命名或删除」
    /// 依样造句（与下面那句删除的提示同构）。登记原因：逻辑层有这么一道拦截，
    /// 就必然有一句话要说；留空会让那个分支变成一个静默的 `return`。
    public static let defaultNotRenamable = "「默认收藏夹」不可重命名"

    /// 试图删除默认夹（原型 `deleteFolderConfirm` 逐字）。
    public static let defaultNotDeletable = "「默认收藏夹」不可删除"

    // MARK: - 建 / 改名 / 删的成功提示

    /// 新建成功（原型 `createFav` / `createFolder` 逐字，两处是同一句）。
    public static func created(_ name: String) -> String { "已创建收藏夹「\(name)」" }

    /// 重命名成功（原型 `renameFolder` 逐字）。
    public static func renamed(to name: String) -> String { "已重命名为「\(name)」" }

    /// 删除成功（原型 `deleteFolder` 逐字）。
    ///
    /// ⚠️ `{moved}` 那半句是本条文案的**全部要害**：它把"收藏没丢"这件事说清楚了。
    /// 少了它，用户看到的是"我删了一个夹，那 12 个项目去哪了？"——
    /// 而屏幕上什么都不会再提（回落是静默发生的）。
    public static func deleted(name: String, moved: Int) -> String {
        "已删除收藏夹「\(name)」· \(moved) 项已回落到「\(FolderDefaults.name)」"
    }

    // MARK: - §5.5 选择收藏列表弹层

    public static let listSheetTitle = "选择收藏列表"

    /// 弹层里最后那行说明（原型 `openFavSheet` 逐字）。
    ///
    /// 「一个仓库只在一个列表里」这半句是在解释**为什么点别处是移动而不是再加一份**，
    /// 不能省（`TECH_SPEC §9.12`：一个仓库同时只属于一个收藏夹）。
    public static let listSheetHint = "选择列表收藏 · 再点已选列表取消收藏 · 一个仓库只在一个列表里"

    /// 列表底部那一行（原型逐字，末尾带一个 `›`）。
    public static let newFolderRowTitle = "新建收藏夹…"

    // MARK: - §5.6 新建收藏夹弹层

    public static let newSheetTitle = "新建收藏夹"

    /// 输入框占位符（原型逐字）。
    public static let nameFieldPlaceholder = "收藏夹名称"

    /// 仓库详情入口的按钮（原型逐字）。
    public static let createAndFavoriteAction = "创建并收藏"

    /// 管理页入口的按钮（原型逐字）。
    public static let createAction = "创建"

    // MARK: - §5.12 收藏夹操作菜单

    /// 菜单标题：`{夹名} · {N} 项`（原型 `openFolderSheet` 逐字）。
    public static func folderSheetTitle(name: String, count: Int) -> String {
        "\(name) · \(itemCount(count))"
    }

    public static let renameAction = "重命名"
    public static let deleteAction = "删除收藏夹"

    /// 菜单底部那句（原型逐字）。
    public static let folderSheetHint = "删除收藏夹后，其中的收藏记录会回落到「默认收藏夹」，不影响仓库本身"

    // MARK: - §5.13 重命名收藏夹

    public static let renameSheetTitle = "重命名收藏夹"
    public static let saveAction = "保存"
    public static let cancelAction = "取消"

    // MARK: - §5.14 删除收藏夹确认

    /// 标题：`删除「{夹名}」？`（原型 `deleteFolderConfirm` 逐字）。
    public static func deleteConfirmTitle(name: String) -> String { "删除「\(name)」？" }

    /// 说明段（原型逐字）。
    ///
    /// ⚠️ 它**回显 `{N}` 两次**（一次在"多少项"，一次在"默认夹 +N"）——
    /// 这不是啰嗦：用户要能在按下红色按钮**之前**核对那个数，
    /// 而删除一旦发生就没有"撤销"（`TECH_SPEC §9.12` 没有 undo）。
    public static func deleteConfirmHint(name: String, count: Int) -> String {
        "其中的 \(count) 项收藏记录会回落到「\(FolderDefaults.name)」"
            + "（默认收藏夹计数相应 +\(count)），收藏并未丢失。"
            + "这不会取消 Star，也不会影响仓库本身。"
    }
}
