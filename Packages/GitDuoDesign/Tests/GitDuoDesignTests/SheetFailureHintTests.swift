import SwiftUI
import Testing

@testable import GitDuoDesign

/// `SheetFailureHint` —— 决策 **#77**（用户走查缺陷修复批 · 第 4 条）新增的那一个件。
///
/// ⚠️ **先说清这一份测试证明不了什么**：本件存在的全部理由是
/// "**弹层开着时它看得见**"，而那是一件事**层级**上成立的事 —— 单测抓不到屏幕，
/// 所以"它真的可见"只有目视能证（走查单 #135 / #139）。
///
/// 能在这里钉住的是另外两件**错了不会报错**的事：
/// ① **取值出处**：它取的是哪一档字色 / 哪一档字号（改错了屏幕上只是"红得不一样"）；
/// ② **它没有与 `NoticeBar` 合并** —— 两件长得很像（都是一行提示文字），
/// 合并之后必有一处的配色被改掉，而那一处看起来仍然"像一条提示"。
///
/// 与其余 `Slice*ComponentTests` 同一条纪律：**不测长相**，只钉取值。
@MainActor
@Suite("弹层内那一行 · SheetFailureHint（决策 #77）")
struct SheetFailureHintTests {

    @Test("⚠️ 字色取的是**危险色**那一档")
    func colorComesFromTheDestructiveSlot() {
        // 原型里弹层内这一行是红字（`Scripts/15-sheets.js` 那类校验），
        // 而 App 侧的取值出处集中在 `Theme.Palette.destructive` 一处。
        #expect(SheetFailureHint("收藏夹已存在").color == Theme.Palette.destructive)
    }

    @Test("⚠️ 字号取的是 `caption` —— 与 `RenameFileSheet` 那份裸写**逐字同档**")
    func fontComesFromTheCaptionSlot() {
        // 这一条是"收拢副本"的守卫：`RenameFileSheet` 原本裸写的正是 `Theme.Font.caption`，
        // 若哪天有人把本件改成 `footnote`（"看起来更清楚"），
        // 那一张弹层的那一行会跟着变 —— 而它属于切片 8 已验收的界面。
        #expect(SheetFailureHint("收藏夹已存在").font == Theme.Font.caption)
    }

    @Test("⚠️ 它与 `NoticeBar` **不是同一件**：两处取的不是同一个令牌")
    func itDidNotMergeWithNoticeBar() {
        // 两件都是一行提示文字、都可能说"失败了"，所以"顺手合并"是一个很自然的想法 ——
        // 代价是：`NoticeBar` 服务**页面**（原型 `#sendErr`，圆角色底）、
        // 本件服务**弹层内部**（无底色），两个场景的可用宽度与周围留白都不同。
        // 这一条钉住"两个令牌不许被改成同一个"。
        let inline = SheetFailureHint("收藏夹已存在")
        let bar = NoticeBar(text: "⚠ 发送失败：网络不可用。草稿已保留，可重试。")

        #expect(inline.color == Theme.Palette.destructive)
        #expect(bar.foreground == Theme.Palette.diffDeletedText)
        // ⚠️ 这两个令牌**当前同值**（`NoticeBar` 的说明里登记过：它借的是 diff 那两对，
        //    "已登记待评审：若将来要让失败提示与 diff 删除能分开调色，就把这一对换掉"）。
        //    所以**不能**断言两者不相等 —— 能断言的是"它们各自取的是哪一个名字"：
        //    本件若被改成 `diffDeletedText`，那一次调色就会把弹层里的这一行一起带走。
    }
}
