import Testing

@testable import GitDuoKit

/// **收藏夹的全部可见文案**（`FolderCopy`）的断言 —— PRD §4.19 / §5.5 / §5.6 / §5.12–§5.14。
///
/// ## 为什么单独一个文件
///
/// 与 `ConversationCopyTests` / `IssueCopyLabelSheetTests` 同一条纪律：
/// **文案是契约，逐字钉住**（`AGENTS.md §5`：一切可见文案提为可测领域数据）。
/// 切片 9.1 把这一族建起来时只测了**行为**（归属表逐行、计数派生、默认夹两重保护），
/// 文案本身**一条断言都没有** —— 而同一批的 `ProfileCopy` 也没有。
/// 一个"专门用来把文案收在一处"的类型自己不设防，那正是它会被慢慢掏空的方式
/// （改一句措辞没人拦，而屏幕上那句话正是用户读到的唯一契约）。
///
/// ⚠️ 逐字来源是**原型** `scripts/11-favorites.js`（事实优先级：原型 > TECH_SPEC > PRD）。
@Suite("收藏夹文案 · 逐字与两处有意不同（§4.19 / §5.5 / §5.6 / §5.12–§5.14）")
struct FolderCopyTests {

    @Test("管理页四句逐字（原型 `SCR.folders` 与它自己的页脚）")
    func managementPageIsVerbatim() {
        #expect(FolderCopy.pageTitle == "我的收藏")
        #expect(FolderCopy.pageSubtitle == "私人整理 · 仅你自己可见，不影响仓库的 Star 数")
        #expect(FolderCopy.pageFooterLine1 == "「默认收藏夹」是新收藏的默认去处，不可重命名或删除")
        #expect(FolderCopy.pageFooterLine2 == "删除其它收藏夹不会取消 Star，也不会影响仓库本身")
    }

    @Test("⚠️ 页脚那两行**必须同时含**「不可重命名或删除」—— 它是两道逻辑拦截的唯一对外说明")
    func footerKeepsTheContract() {
        // 逻辑层对默认夹有两道拦截（`rename` 的 `.protectedDefault` 与 `delete` 的 `.protectedDefault`），
        // 而界面上**不给那一行入口** ⇒ 用户唯一能得知"这个夹动不了"的地方就是这行页脚。
        // 删掉它，那两道拦截就成了"点了没反应"（更糟：连点都点不了，却不知道为什么）。
        #expect(FolderCopy.pageFooterLine1.contains("不可重命名或删除"))
    }

    @Test("计数与标记逐字（原型 `${favTotal(f.n)} 项` / `<span class=\"ftag\">默认</span>`）")
    func countAndTagAreVerbatim() {
        #expect(FolderCopy.defaultTag == "默认")
        #expect(FolderCopy.itemCount(0) == "0 项")
        #expect(FolderCopy.itemCount(12) == "12 项")
        // ⚠️ **不加千分位也不缩写**：这是"我自己整理了几条"，量级很小。
        // 写成 `1,024 项` 会让它和热力图那个数看起来像同一类的统计量。
        #expect(FolderCopy.itemCount(1024) == "1024 项")
    }

    // MARK: - 仓库详情 ② 分区那两颗按钮

    @Test("② 分区的四句逐字（原型 `10-explore-repo.js`）")
    func repositorySectionIsVerbatim() {
        #expect(FolderCopy.favoriteAction == "收藏到我的列表")
        #expect(FolderCopy.favoritedActionPrefix == "已收藏 · ")
        #expect(FolderCopy.favoriteHintIdle == "私人收藏夹，不影响仓库的 Star 数")
        #expect(FolderCopy.favoriteHintFavorited == "已加入收藏 · 再点可选择 / 更换收藏列表")
    }

    @Test("⚠️ 首次收藏那句**必须带**「再点可选择列表」—— 它是两段式交互的唯一告知")
    func firstFavoriteTeachesTheSecondStep() {
        // §9.12 的两段式交互：首次点 → 进默认夹；**再点** → 打开选择列表。
        // 而"再点一下会怎样"这件事，用户第一遍做的时候**不可能猜到** ——
        // 那半句就是唯一的告知处。删了它，选择列表那个弹层就基本没人会打开。
        #expect(FolderCopy.favoritedToDefault.contains("再点可选择列表"))
        #expect(FolderCopy.favoritedToDefault.contains("默认收藏夹"))
        // 换夹那句**不带**引导（用户已经会了），两句不能合并成一句。
        #expect(!FolderCopy.favorited(to: "前端好项目").contains("再点"))
        #expect(FolderCopy.favorited(to: "前端好项目") == "已收藏到「前端好项目」（私人收藏夹）")
        #expect(FolderCopy.removed == "已从收藏移除")
    }

    @Test("⚠️⚠️ 两个入口的重名处置**有意不同**，而它们只差半句话")
    func duplicateHandlingDiffersByDesign() {
        // | 入口 | 按钮 | 重名时 |
        // |---|---|---|
        // | 仓库详情（§5.6 前半） | 创建并收藏 | 提示**并自动选中**，照样把仓库放进去 |
        // | 管理页（§5.6 后半） | 创建 | 只提示，**不创建、不动任何仓库** |
        //
        // 这两句的差别（"已为你选中" vs 没有）是那条行为差别的**唯一可见证据**。
        // 谁把它们合并成一句，两个入口就会悄悄变成同一个 —— 而屏幕上只差半句话，
        // 评审时几乎看不出来。所以这一条**既断言相等、也断言不等**。
        #expect(FolderCopy.duplicateInRepository == "收藏夹已存在，已为你选中")
        #expect(FolderCopy.duplicateInManagement == "收藏夹已存在")
        #expect(FolderCopy.duplicateInRepository != FolderCopy.duplicateInManagement)
        #expect(FolderCopy.duplicateInRepository.contains("已为你选中"))
        #expect(!FolderCopy.duplicateInManagement.contains("已为你选中"))
        // 重命名那一处的主语是"名字"而不是"夹"（语境是"你正在改名字"）⇒ 第三句也不一样。
        #expect(FolderCopy.duplicateInRename == "已有同名收藏夹")
    }

    @Test("三句校验与默认夹那两句")
    func validationCopyIsVerbatim() {
        // 空名那一句**三个入口共用**（原型 `createFav` / `createFolder` / `renameFolder` 同一句）。
        #expect(FolderCopy.emptyName == "先输入收藏夹名称")
        #expect(FolderCopy.defaultNotDeletable == "「默认收藏夹」不可删除")
        // ⚠️ 这一句**原型没有**（它那一行不给入口、走不到）⇒ 属"规格未给"的自拟，
        //    按页脚那句「不可重命名或删除」依样造句。逻辑层有这道拦截就必须有一句话要说。
        #expect(FolderCopy.defaultNotRenamable == "「默认收藏夹」不可重命名")
    }

    // MARK: - 三句成功提示

    @Test("建 / 改名 / 删三句逐字（原型逐字）")
    func successToastsAreVerbatim() {
        #expect(FolderCopy.created("前端好项目") == "已创建收藏夹「前端好项目」")
        #expect(FolderCopy.renamed(to: "Swift 学习") == "已重命名为「Swift 学习」")
    }

    @Test("⚠️ 删除那句**必须说出「多少项去哪了」** —— 回落是静默发生的")
    func deletionToastExplainsWhereTheItemsWent() {
        // 删夹会把里面的收藏**回落到默认夹**（§9.12 归属表第 6 行），
        // 而这一步在屏幕上不留任何痕迹（收藏夹列表里只是少了一行）。
        // 少了 `{moved}` 那半句，用户看到的是"我删了一个夹，那 12 个项目去哪了？"
        // —— 而 App 再也不提这件事。
        let toast = FolderCopy.deleted(name: "以后再看", moved: 12)

        #expect(toast == "已删除收藏夹「以后再看」· 12 项已回落到「默认收藏夹」")
        #expect(toast.contains("12 项"))
        #expect(toast.contains(FolderDefaults.name))
    }

    // MARK: - 四张收藏夹弹层

    @Test("§5.5 选择收藏列表弹层逐字")
    func favoriteListSheetIsVerbatim() {
        #expect(FolderCopy.listSheetTitle == "选择收藏列表")
        #expect(FolderCopy.newFolderRowTitle == "新建收藏夹…")
        // ⚠️ 后半句「一个仓库只在一个列表里」是在解释**为什么点别处是移动而不是再加一份**
        //    （§9.12：一个仓库同时只属于一个收藏夹），不能省。
        #expect(FolderCopy.listSheetHint == "选择列表收藏 · 再点已选列表取消收藏 · 一个仓库只在一个列表里")
        #expect(FolderCopy.listSheetHint.contains("再点已选列表取消收藏"))
    }

    @Test("§5.6 新建收藏夹弹层：两个入口只差按钮那两个字")
    func newFolderSheetIsVerbatim() {
        #expect(FolderCopy.newSheetTitle == "新建收藏夹")
        #expect(FolderCopy.nameFieldPlaceholder == "收藏夹名称")
        #expect(FolderCopy.createAndFavoriteAction == "创建并收藏")
        #expect(FolderCopy.createAction == "创建")
        #expect(FolderCopy.createAndFavoriteAction != FolderCopy.createAction)
    }

    @Test("§5.12 / §5.13 / §5.14 三张弹层逐字")
    func operationSheetsAreVerbatim() {
        #expect(FolderCopy.folderSheetTitle(name: "以后再看", count: 12) == "以后再看 · 12 项")
        #expect(FolderCopy.renameAction == "重命名")
        #expect(FolderCopy.deleteAction == "删除收藏夹")
        #expect(FolderCopy.folderSheetHint == "删除收藏夹后，其中的收藏记录会回落到「默认收藏夹」，不影响仓库本身")
        #expect(FolderCopy.renameSheetTitle == "重命名收藏夹")
        #expect(FolderCopy.saveAction == "保存")
        #expect(FolderCopy.cancelAction == "取消")
        #expect(FolderCopy.deleteConfirmTitle(name: "以后再看") == "删除「以后再看」？")
    }

    @Test("⚠️ 删除确认那段**回显 `{N}` 两次**（按红按钮之前要能核对那个数）")
    func deleteConfirmationEchoesTheCountTwice() {
        // 删除没有撤销（§9.12 没有 undo）⇒ 那个数必须在**按下之前**看得见：
        // 一次是"其中的 {N} 项"，一次是"默认收藏夹计数相应 +{N}"。
        // 两处都留着是因为它们回答的是两个不同的问题（搬走多少 / 搬到哪之后它有几项）。
        let hint = FolderCopy.deleteConfirmHint(name: "以后再看", count: 12)

        #expect(hint.contains("其中的 12 项"))
        #expect(hint.contains("+12"))
        // 三句承诺：收藏没丢 · Star 没变 · 仓库没动。
        #expect(hint.contains("收藏并未丢失"))
        #expect(hint.contains("不会取消 Star"))
        #expect(hint.contains("不会影响仓库本身"))
    }
}
