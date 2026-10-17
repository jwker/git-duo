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
