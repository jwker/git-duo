import SwiftUI
import Testing

@testable import GitDuoDesign

/// 切片 8.3（设计系统）三处补口的断言 —— 全是"**默认值没变**"与"**哪一档取哪一对令牌**"。
///
/// 为什么不测长相：视图的长相要靠截图与逐屏对照（`REVIEW-CHECKLIST §6` 的 18–21），
/// 但"新参数有没有把既有调用点带偏"和"两档色调到底取的是不是那一对颜色"
/// 都是**可以**被钉住的规则 —— 而这恰恰是本片最容易出错、错了还不报错的地方
/// （色对混用不会报错，只会让"新分支 + PR"那条提示看起来像一条报错）。
/// 沿 `Slice4` / `Slice5` / `Slice6` / `Slice7ComponentTests` 的同一条纪律。
///
/// ⚠️ 施工图 8.3 那一行写的是「✅ **预计零新增**」。实查结论：
/// **确实零新增组件**，但三件既有组件各缺一个参数（本文件钉住的就是这三个）。
/// 逐条核实记录见 `AGENTS.md` 切片 8 表的 8.3 行。
@MainActor
@Suite("切片 8 组件 · 三处补口的默认值与色调")
struct Slice8ComponentTests {

    // MARK: - `NoticeBar` 的两档色调（PRD §5.9 那条提示条）

    @Test("⚠️ `tone` 默认是 `.danger` —— 既有两处调用点（Issue / PR 详情的发送失败）一个字都不用改")
    func noticeBarToneDefaultsToDanger() {
        // 默认值一旦漂成 `.add`，那两条"发送失败"会变成**绿底**——
        // 看起来像一句成功提示，而它说的是"没发出去"。
        let notice = NoticeBar(text: "⚠ 发送失败：网络不可用。草稿已保留，可重试。")
        #expect(notice.tone == .danger)
        // 省略与显式传 `.danger` 必须是**同一个值**（沿 `Segment.isAction` 那条先例）。
        #expect(notice.tone == NoticeBar(text: "x", tone: .danger).tone)
    }

    @Test("两档各自取的是**那两对**令牌（原型 `01-base.css` 第 8 行并列声明的那四色）")
    func noticeBarTonesMapToTheRightPairs() {
        // `.danger` = 原型 `--del-bg` / `--del-tx`。
        let danger = NoticeBar(text: "x", tone: .danger)
        #expect(danger.foreground == Theme.Palette.diffDeletedText)
        #expect(danger.surface == Theme.Palette.diffDeletedSurface)

        // `.add` = 原型 `--add-bg` / `--add-tx`。
        let add = NoticeBar(text: "x", tone: .add)
        #expect(add.foreground == Theme.Palette.diffAddedText)
        #expect(add.surface == Theme.Palette.diffAddedSurface)

        // ⚠️ 两档**必须真的不同** —— 混用不会报错，只会让 §5.9 那条提示
        //（"将创建新分支…改动不直接进 main"）看起来像一条报错。
        // （动态色时代 `!=` 比实例身份 ⇒ 改比 resolve 分量，两档各钉一次。）
        #expect(ColorResolve.distinct(add.foreground, danger.foreground, .light))
        #expect(ColorResolve.distinct(add.foreground, danger.foreground, .dark))
        #expect(ColorResolve.distinct(add.surface, danger.surface, .light))
        #expect(ColorResolve.distinct(add.surface, danger.surface, .dark))
    }

    @Test("⚠️ 四色与原型 `01-base.css` 的值**逐字相同**（值冻结在这里，改动必须过这一关）")
    func noticeBarToneColoursAreFrozen() {
        // 原型：`--add-bg:#dafbe1; --add-tx:#116329; --del-bg:#ffebe9; --del-tx:#cf222e;`
        // ⚠️ 动态色时代 `Color ==` 比实例身份 ⇒ 比浅色列的 resolve 分量
        //（冻结的是**浅色**列 = 原型值；深色列出处见 `Theme.swift` 行尾）。
        #expect(ColorResolve.same(Theme.Palette.diffAddedSurface, Color(hex: 0xDAFBE1), .light))
        #expect(ColorResolve.same(Theme.Palette.diffAddedText, Color(hex: 0x116329), .light))
        #expect(ColorResolve.same(Theme.Palette.diffDeletedSurface, Color(hex: 0xFFEBE9), .light))
        #expect(ColorResolve.same(Theme.Palette.diffDeletedText, Color(hex: 0xCF222E), .light))

        // ⚠️ "借 diff 那两对"这件事本身是**已登记待评审**的（见 `NoticeBar` 抬头）——
        // 这一条只是把"借的是哪两对"钉住，不改变那个待评审状态。
    }

    // MARK: - `SheetRow` 的危险色标题（PRD §5.15 / §5.12）

    @Test("⚠️ `titleTone` 默认 `.normal` —— 既有七处调用点一个字都不用改")
    func sheetRowTitleToneDefaultsToNormal() {
        let row = SheetRow(systemImage: "folder", title: "管理分支…", action: {})
        #expect(row.titleTone == .normal)
        #expect(row.titleColor == Theme.Palette.textPrimary)
    }

    @Test("§5.15 那一行：`删除文件` 的标题是**危险色**，而它**不是**任何一档普通文字色")
    func sheetRowDestructiveTitleUsesDestructiveToken() {
        // 原型 `11-favorites.js:94` 的 `<div class="sheet-row" style="color:var(--closed-p)">`
        // —— `--closed-p` 正是本仓的 `Palette.destructive`（`0xCF222E`）。
        let row = SheetRow(title: "删除文件", titleTone: .destructive, action: {})
        #expect(row.titleColor == Theme.Palette.destructive)
        // （动态色时代 `Color ==` 比实例身份 ⇒ 冻结值改比浅色列的 resolve 分量。）
        #expect(ColorResolve.same(row.titleColor, Color(hex: 0xCF222E), .light))

        // 写成 `textPrimary` / `textSecondary` 不会报错，只会让"这是破坏性操作"
        // 这条信息在画面上**完全消失**（点进去才知道）。
        // （动态色时代 `!=` 比实例身份 ⇒ 改比 resolve 分量，两档各钉一次。）
        #expect(ColorResolve.distinct(row.titleColor, Theme.Palette.textPrimary, .light))
        #expect(ColorResolve.distinct(row.titleColor, Theme.Palette.textPrimary, .dark))
        #expect(ColorResolve.distinct(row.titleColor, Theme.Palette.textSecondary, .light))
        #expect(ColorResolve.distinct(row.titleColor, Theme.Palette.textSecondary, .dark))
        // 也别被标签兜底色串了（那是"白字压上去的底"，这里是"深色压在白底上的字"）。
        #expect(ColorResolve.distinct(row.titleColor, Theme.Palette.labelFallbackSurface, .light))
        #expect(ColorResolve.distinct(row.titleColor, Theme.Palette.labelFallbackSurface, .dark))
    }

    @Test("⚠️ 危险色只改**标题** —— 图标仍是次级色（原型 `.sheet-row svg{stroke:var(--text2)}` 写死）")
    func sheetRowDestructiveToneDoesNotLeakToTheIcon() {
        // 原型那一行的内联 `style="color:…"` 改的是 div 的 `color`，
        // 而 svg 的 `stroke` 在 CSS 里被写死成 `var(--text2)` ⇒ **图标不变红**。
        // 这里没有"图标色"这个参数，所以这条断言只能表达成"传了两个 leading 都还在"——
        // 它的作用是：哪天有人给 `titleTone` 顺手加上"图标也跟着变红"，
        // 至少得先看见这一条注释（原型查过了，不是这个行为）。
        let withIcon = SheetRow(systemImage: GitHubIcon.trash, title: "删除文件", titleTone: .destructive, action: {})
        #expect(withIcon.systemImage == GitHubIcon.trash)
        #expect(withIcon.titleTone == .destructive)
    }

    // MARK: - `SheetField` 的多行（PRD §5.9 的提交信息框）

    @Test("⚠️ `minLines` 默认 1 —— 既有五处调用点行为**逐字不变**（走的还是那一行单行 `TextField`）")
    func sheetFieldMinLinesDefaultsToSingleLine() {
        let field = SheetField("分支名", text: .constant(""))
        #expect(field.minLines == 1)
    }

    @Test("§5.9 那一档：提交信息框保底 **2** 行（原型 `<textarea class=\"sheet-input\" id=\"cmsg\" rows=\"2\">`）")
    func sheetFieldAcceptsMultiLineForCommitMessage() {
        // ⚠️ 2 这个数是**原型写死的**（`15-sheets.js:43` 的 `rows="2"`），
        // 不是选出来的。它也不是"1 与 13 之间随便取一个"——
        // 编辑器那一档（13 行）走的是 `CodeTextArea`，另一个类（等宽 + `--card` 底）。
        let field = SheetField("提交信息（commit message）", text: .constant(""), minLines: 2)
        #expect(field.minLines == 2)

        // 多行与"两个文本行为"是**正交**的：提交信息是一句话，不该被吃掉首字母大写。
        // ⚠️ 这一条只钉"两个参数能并存"，不改变 `.never` 这个默认（分支名那一档）。
        let sentenceCase = SheetField(
            "提交信息",
            text: .constant(""),
            disablesAutocorrection: false,
            capitalization: .sentences,
            minLines: 2
        )
        #expect(sentenceCase.minLines == 2)
    }

    // MARK: - `GitHubIcon` 两个新常量

    @Test("⚠️ `pencil` / `trash` 是**查过原型才加的** —— 两个名字都要能在 SF Symbols 里找到")
    func destructiveActionIconsExist() {
        // 原型 `11-favorites.js:93/94` 那两行 `.sheet-row` 里写着 `svg(I.pencil)` / `svg(I.trash)`，
        // 而本表原先没有这两个名字（切片 6.4 只补过 `history` / `more` / `openInBrowser` 三个，
        // 后来发现用不上又删了）。§5.15 明写"形态照 §5.12" ⇒ 切片 8 的
        // 文件操作菜单 / 重命名 / 删除确认三处都要用。
        //
        // ⚠️ 名字写错**不会**在任何环节报错（SwiftPM 测试跑在 macOS 上，拿不到
        // `UIImage(systemName:)`）—— 界面上表现为图标凭空消失。
        // 这一条只能钉住"值是这两个字符串"，真正的验证是模拟器/真机看一眼
        //（与 `GitHubIcon` 抬头的告诫同源）。
        #expect(GitHubIcon.pencil == "pencil")
        #expect(GitHubIcon.trash == "trash")
        #expect(GitHubIcon.pencil != GitHubIcon.trash)

        // 别与既有两个"文件树"图标串了（`file` 是 `doc.text`、`folder` 是 `folder`）。
        #expect(GitHubIcon.trash != GitHubIcon.file)
        #expect(GitHubIcon.pencil != GitHubIcon.file)
    }
}
