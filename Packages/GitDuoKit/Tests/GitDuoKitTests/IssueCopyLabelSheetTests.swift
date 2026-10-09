import Testing

@testable import GitDuoKit

/// §5.2 标签选择 / 新建弹层的**文案契约**（PRD §5.2 / §7、原型 `scripts/07-issues.js`）。
///
/// ## 为什么单独一个文件
///
/// 这一族的字符串在切片 7.1 就写进了 `IssueCopy`，但**落到屏幕上是 7.4 的事**
/// （`LabelPickerSheet` + `RepoDetailView` 的弹层分支）——
/// 在那之前它们只是"领域层里躺着的一段文字"，谁改都不会有后果。
/// 现在它们真的被印出来了，于是必须被钉住：这些句子是**用户能看到的承诺**
/// （`labelSheetHint` 那句"新标签会保存到仓库标签列表"尤其 —— 它成立的前提是
/// 新建真的走 `POST /labels`，而不是只塞进本地集合）。
///
/// ⚠️ 断言里写的是**逐字**的期望值，不是 `IssueCopy.x == IssueCopy.x` 那种同义反复。
/// 抄错一个标点（原型那句是 `标签名称，如 performance`，不是全角逗号）在这里就会红。
@Suite("§5.2 标签弹层文案（切片 7.4 开始上屏）")
struct IssueCopyLabelSheetTests {

    @Test("上段标题：`选择标签 · N 个`（计数是句子的一部分，不是另拼的）")
    func labelSheetTitle() {
        #expect(IssueCopy.labelSheetTitle(count: 5) == "选择标签 · 5 个")
        // ⚠️ 0 也要能写出来 —— 这一句**可以**说 0（标签库确实取回来了、确实是空的），
        //    而"还没取回来"用的是下面那一句，两者不可互换（§8.5 末条）。
        #expect(IssueCopy.labelSheetTitle(count: 0) == "选择标签 · 0 个")
    }

    @Test("⚠️ 标签库还没取回来时的标题**不带计数** —— `· 0 个` 是一句假话")
    func labelSheetTitlePendingHasNoCount() {
        // 规格未给（自拟），理由写在 `IssueCopy.labelSheetTitlePending` 的文档里。
        // 这一条断言的作用是挡住"顺手把它改成 `选择标签 · 0 个`"这种"统一格式"的清理。
        #expect(IssueCopy.labelSheetTitlePending == "选择标签")
        #expect(!IssueCopy.labelSheetTitlePending.contains("个"))
        #expect(!IssueCopy.labelSheetTitlePending.contains("·"))
    }

    @Test("下段三件：段落标题 / 输入框占位 / 主按钮")
    func newLabelSectionCopy() {
        #expect(IssueCopy.newLabelSectionTitle == "新建标签")
        // ⚠️ 原型里那个逗号是**半角**（`07-issues.js:44`），不是全角。
        #expect(IssueCopy.newLabelPlaceholder == "标签名称，如 performance")
        #expect(IssueCopy.createLabelAction == "创建并选中")
    }

    @Test("⚠️ 底部那句是一句**承诺** —— 它成立的前提是新建真的写到仓库上")
    func labelSheetHintIsAPromise() {
        #expect(
            IssueCopy.labelSheetHint == "新标签会保存到仓库标签列表，之后所有 Issue 都可直接选用"
        )
        // 承诺的两个关键词都在：**保存到仓库**（不是本地）与**之后都能用**（不是只在这一条 Issue 上）。
        #expect(IssueCopy.labelSheetHint.contains("仓库标签列表"))
        #expect(IssueCopy.labelSheetHint.contains("所有 Issue"))
    }

    @Test("§7 的两句校验提示逐字（都不发请求）")
    func labelSheetValidationCopy() {
        // ⚠️ 这两句的**载体不同**（决策 #77）：空名那句**画在弹层内**
        //（`emptyLabelNameHint` —— 弹层留着让用户接着打字，而提示条会被弹层盖住），
        // 重名那句**走提示条**（`duplicateLabelToast` —— 那一档会关掉弹层，看得见）。
        // 常量名里的 `Hint` / `Toast` 正是这条差别的记号，两个名字都不要"统一"。
        #expect(IssueCopy.emptyLabelNameHint == "请先填写标签名称")
        #expect(IssueCopy.duplicateLabelToast == "标签已存在，已为你选中")
    }

    @Test("新建成功的提示带**全角引号**包住名字（原型逐字）")
    func labelCreatedToast() {
        #expect(IssueCopy.labelCreatedToast(name: "performance") == "已创建标签 “performance”")
    }

    @Test("⚠️ 两句校验话与「已存在 / 空名」两条路径一一对应，且互不串用")
    func validationCopyIsNotSwapped() {
        // 两句都很短、都出现在同一个弹层那一段里，串用之后没有任何东西能提示你错了
        // （空名那句会显示在弹层内、重名那句则随着弹层关闭一起被带走）。
        #expect(IssueCopy.emptyLabelNameHint != IssueCopy.duplicateLabelToast)
        #expect(IssueCopy.emptyLabelNameHint.contains("填写"))
        #expect(IssueCopy.duplicateLabelToast.contains("已存在"))
    }
}
