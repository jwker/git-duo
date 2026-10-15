import SwiftUI
import Testing

@testable import GitDuoDesign

/// 切片 6.3 四个新件（`CodeSurface` / `DiffRow` / `BreadcrumbBar` / `BranchRow`）
/// 里"纯函数那一半"的断言。
///
/// 为什么只测这一半：视图的长相没法用断言描述（要靠截图与逐屏对照），
/// 但"哪一档配哪个颜色""哪几档有行号列""四个档位是不是真的有四种颜色"
/// 都是**可以**被钉住的规则 —— 而它们恰好是最容易出错、错了还不报错的地方。
/// 沿 `Slice4ComponentTests` / `Slice5ComponentTests` 的同一条纪律。
@MainActor
@Suite("切片 6 组件 · 纯函数部分")
struct Slice6ComponentTests {

    // MARK: - 语法高亮的四色 + 五档

    @Test("⚠️ `CodeTone` **只有五档** —— 领域层七档里 `number` / `type` 没有颜色，落到 `.plain`")
    func codeToneHasFiveCases() {
        // 原型只给了四色，五档 = 四色 + 不着色。多一档就意味着有人替原型
        // 补了一个它没写过的颜色（见 `CodeTone` 的类型说明）。
        #expect(CodeTone.allCases.count == 5)
    }

    @Test(
        "四色**逐个冻结**在原型 `styles/04-screens.css` 第 27 行的取值上",
        arguments: [
            (0xCF222E, "syntaxKeyword"),
            (0x8250DF, "syntaxFunction"),
            (0x0A3069, "syntaxString"),
            (0x6E7781, "syntaxComment"),
        ]
    )
    func syntaxColorsAreFrozen(_ hex: UInt32, _ name: String) {
        // 取错一个（例如把 `syntaxString` 写成 `syntaxComment` 的灰）不会报错，
        // 只会让代码看起来"颜色怪怪的" ⇒ 把四个值钉死，改了必须过这一关。
        // ⚠️ 动态色时代 `Color ==` 比实例身份 ⇒ 改比 resolve 分量。
        // 冻结的是**浅色**列（= 原型值）；深色列的出处见 `Theme.swift` 行尾。
        let expected = Color(hex: hex)
        switch name {
        case "syntaxKeyword": #expect(ColorResolve.same(Theme.Palette.syntaxKeyword, expected, .light))
        case "syntaxFunction": #expect(ColorResolve.same(Theme.Palette.syntaxFunction, expected, .light))
        case "syntaxString": #expect(ColorResolve.same(Theme.Palette.syntaxString, expected, .light))
        default: #expect(ColorResolve.same(Theme.Palette.syntaxComment, expected, .light))
        }
    }

    @Test("⚠️ 四色两两不同、且都不等于正文色 —— 同色会让「哪一档取错了」永远看不出来")
    func syntaxColorsAreDistinct() {
        let colors = [
            Theme.Palette.syntaxKeyword,
            Theme.Palette.syntaxFunction,
            Theme.Palette.syntaxString,
            Theme.Palette.syntaxComment,
        ]
        // ⚠️ 动态色时代 `!=` 比实例身份 ⇒ 改比 resolve 分量，**两档各钉一次**
        //（深色四色 `#ff7b72 / #d2a8ff / #a5d6ff / #8b949e` 同样两两互异）。
        for scheme in [ColorScheme.light, .dark] {
            // 逐对比而不是塞进 `Set`：失败时能直接指出是哪一对撞了。
            for (index, lhs) in colors.enumerated() {
                for rhs in colors[(index + 1)...] {
                    #expect(ColorResolve.distinct(lhs, rhs, scheme))
                }
                // 任何一档都不许退化成"不着色"（那就等于这一档没有实现）。
                #expect(ColorResolve.distinct(lhs, Theme.Palette.textPrimary, scheme))
                #expect(ColorResolve.distinct(lhs, .clear, scheme))
            }
        }
    }

    @Test("五档 → 颜色的映射：四档各归各的色，`.plain` 归正文色")
    func codeToneColors() {
        #expect(CodeSurface.color(.plain) == Theme.Palette.textPrimary)
        #expect(CodeSurface.color(.keyword) == Theme.Palette.syntaxKeyword)
        #expect(CodeSurface.color(.string) == Theme.Palette.syntaxString)
        #expect(CodeSurface.color(.comment) == Theme.Palette.syntaxComment)
        #expect(CodeSurface.color(.function) == Theme.Palette.syntaxFunction)
    }

    @Test("⚠️ `accentSubtle`（hunk 头的底）与 `accentSurface`（筛选 chip 选中态）：浅色两个值，深色**有意同值**（已登记）")
    func accentSubtleIsNotAccentSurface() {
        // 浅色两档是两个值（`#DDF4FF` 偏青 / `#F0F6FF` 偏灰）：混用会让 diff 的
        // hunk 头与"已选 chip"看起来像同一族控件。
        // ⚠️ 2026-10-15 深色列两档**有意合并**（都是 `#388BFD@0.10`，Primer 深色
        // 本就只有一档"强调浅底"）—— 已在 `Theme.swift` 登记，所以深色档反过来
        // 钉"就是同值"，哪天有人想拆开必须先看见这条。
        // （动态色时代 `==` / `!=` 比实例身份 ⇒ 全部改比 resolve 分量。）
        #expect(ColorResolve.distinct(Theme.Palette.accentSubtle, Theme.Palette.accentSurface, .light))
        #expect(ColorResolve.same(Theme.Palette.accentSubtle, Theme.Palette.accentSurface, .dark))
        // 行内代码的底是**半透明**的（要能透出下面的卡片白），不能换成不透明色。
        for scheme in [ColorScheme.light, .dark] {
            #expect(ColorResolve.distinct(Theme.Palette.codeInlineSurface, Theme.Palette.surface, scheme))
            #expect(ColorResolve.distinct(Theme.Palette.codeInlineSurface, Theme.Palette.surfaceSunken, scheme))
        }
    }

    // MARK: - DiffRow 六档

    @Test("⚠️ `DiffRow.Tone` 有**六**档 —— 其中两档原型没有，用来兜住「少一行」的风险")
    func diffRowToneHasSixCases() {
        // `.note` = `\ No newline at end of file`；`.content` = 认不出来的非标准行。
        // 它们**必须有地方落**：丢掉会让用户看到的 diff 比真实改动少几行，而没有任何迹象。
        #expect(DiffRow.Tone.allCases.count == 6)
    }

    @Test("行底色：增 / 删各有底色，hunk 头用强调浅底，其余三档**不画底**（用容器的底）")
    func diffRowSurfaces() {
        #expect(DiffRow.surface(.added) == Theme.Palette.diffAddedSurface)
        #expect(DiffRow.surface(.removed) == Theme.Palette.diffDeletedSurface)
        #expect(DiffRow.surface(.hunk) == Theme.Palette.accentSubtle)

        // 上下文行在原型里没有 `background`（继承卡片的白）。
        // 三档"没有底色"的必须是**同一个值** —— 各画各的会多出三种看不见的偏差。
        #expect(DiffRow.surface(.context) == DiffRow.surface(.note))
        #expect(DiffRow.surface(.note) == DiffRow.surface(.content))
        // ⚠️ 动态色时代 `!=` 比实例身份 ⇒ 与"有底"两档的互异改比 resolve 分量（两档都钉）。
        for scheme in [ColorScheme.light, .dark] {
            #expect(ColorResolve.distinct(DiffRow.surface(.context), DiffRow.surface(.added), scheme))
            #expect(ColorResolve.distinct(DiffRow.surface(.context), DiffRow.surface(.hunk), scheme))
        }
    }

    @Test("行文字色：增删各有色，hunk 头走强调色，注解比正文轻一档、未知行与正文同重")
    func diffRowTextColors() {
        #expect(DiffRow.textColor(.context) == Theme.Palette.textPrimary)
        #expect(DiffRow.textColor(.added) == Theme.Palette.diffAddedText)
        #expect(DiffRow.textColor(.removed) == Theme.Palette.diffDeletedText)
        #expect(DiffRow.textColor(.hunk) == Theme.Palette.accent)
        #expect(DiffRow.textColor(.note) == Theme.Palette.textTertiary)
        #expect(DiffRow.textColor(.content) == Theme.Palette.textPrimary)

        // ⚠️ **两档中性色不许串味**：`.note` 是注解（轻）、`.content` 是原文（重）。
        // 两者都取 `textPrimary` 的话，`\ No newline` 会看起来像一行代码。
        // （动态色时代 `!=` 比实例身份 ⇒ 改比 resolve 分量，两档各钉一次。）
        #expect(ColorResolve.distinct(DiffRow.textColor(.note), DiffRow.textColor(.content), .light))
        #expect(ColorResolve.distinct(DiffRow.textColor(.note), DiffRow.textColor(.content), .dark))
    }

    @Test("读屏前缀只补增 / 删两个记号 —— 它们是 diff 格式自身的符号，不是产品文案")
    func diffRowAccessibilityPrefix() {
        #expect(DiffRow.accessibilityPrefix(.added) == "+ ")
        #expect(DiffRow.accessibilityPrefix(.removed) == "− ")
        // ⚠️ 减号必须是 U+2212（原型与 GitHub 用的那个），不是 ASCII 连字符。
        #expect(DiffRow.accessibilityPrefix(.removed) != "- ")

        for tone in [DiffRow.Tone.context, .hunk, .note, .content] {
            #expect(DiffRow.accessibilityPrefix(tone).isEmpty)
        }
    }

    @Test("⚠️ 只有三档有行号列 —— hunk 头 / 注解 / 未知行都没有（它们不是文件里的一行）")
    func diffRowNumberColumn() {
        #expect(DiffRow.showsNumberColumn(.context))
        #expect(DiffRow.showsNumberColumn(.added))
        #expect(DiffRow.showsNumberColumn(.removed))

        #expect(!DiffRow.showsNumberColumn(.hunk))
        #expect(!DiffRow.showsNumberColumn(.note))
        #expect(!DiffRow.showsNumberColumn(.content))
    }

    // MARK: - 切片 6 新增的圆角与字号

    @Test("圆角三档：`control`(9) / `branchChip`(7) 与既有的 `chip`(6) / `segment`(8) / `card`(10) **都不同**")
    func slice6RadiiAreDistinct() {
        // 原型里 `.btn` / `.crumb` / `.markdown pre` 三处同为 9 ⇒ 合成 `control`，
        // `.branch-chip` 是 7 ⇒ 单独一档。这两档都不能合并进既有的任何一档：
        // 合并了就等于替原型改了一个它明写的值（差 1pt 在圆角上是看得出来的）。
        #expect(Theme.Radius.control == 9)
        #expect(Theme.Radius.branchChip == 7)

        #expect(Theme.Radius.control != Theme.Radius.segment)
        #expect(Theme.Radius.control != Theme.Radius.card)
        #expect(Theme.Radius.control != Theme.Radius.container)
        #expect(Theme.Radius.branchChip != Theme.Radius.chip)
        #expect(Theme.Radius.branchChip != Theme.Radius.segment)
    }

    @Test("⚠️ `Theme.Font.breadcrumb` 是系统 `.caption`(12pt)，**不是** `Theme.Font.caption`（那是 `.caption2`，11pt）")
    func breadcrumbFontIsNotTheCaptionToken() {
        // 这是本文件里最容易读错的一处：令牌名 `caption` 与系统层级 `.caption`
        // 指的不是同一档。原型 `.crumb{font-size:12.5px}` ⇒ 12pt。
        #expect(Theme.Font.breadcrumb == SwiftUI.Font.caption)
        #expect(Theme.Font.breadcrumb != Theme.Font.caption)
    }

    @Test("代码块字号与两个既有等宽档**都不同**（12pt 落在中间那一档）")
    func monospacedCodeSitsBetweenTheOtherTwo() {
        #expect(Theme.Font.monospacedCode == SwiftUI.Font.system(.caption, design: .monospaced))
        // 预览行 11pt（`.caption2`）比它小、正文等宽 13pt（`.footnote`）比它大。
        #expect(Theme.Font.monospacedCode != Theme.Font.monospacedPreview)
        #expect(Theme.Font.monospacedCode != Theme.Font.monospaced)
    }

    @Test("Markdown 三档字号：h1(22 bold) / h2(17 bold) / 正文(15)")
    func markdownFonts() {
        #expect(Theme.Font.markdownH1 == SwiftUI.Font.title2.weight(.bold))
        #expect(Theme.Font.markdownH2 == SwiftUI.Font.body.weight(.bold))
        #expect(Theme.Font.markdownBody == SwiftUI.Font.subheadline)

        #expect(Theme.Font.markdownH1 != Theme.Font.markdownH2)
        #expect(Theme.Font.markdownH1 != Theme.Font.markdownBody)
        #expect(Theme.Font.markdownH2 != Theme.Font.markdownBody)
        // ⚠️ h2 与 `bodyStrong` **只差一档字重**（bold 700 vs semibold 600），不能合并：
        // 原型里这是两处独立取值，而 h2 掉一档字重就与"加粗的正文"分不开了。
        #expect(Theme.Font.markdownH2 != Theme.Font.bodyStrong)
    }

    @Test("⚠️ 两处**同值不同名**是刻意的：`markdownBody` 与 `rowTitle` 同为 `.subheadline`")
    func markdownBodySharesSizeWithRowTitle() {
        // 原型 `.markdown{font-size:14px}` 与 `.file-row .fname{font-size:14.5px}` 是两处独立取值，
        // 只是都落到了系统最近的那一档。它们今天相等、将来未必：
        // 这条断言的作用是**让"改了一处"必须经过一次有意识的决定**，
        // 而不是某天被顺手合并成同一个令牌（沿 `codeSurface` 与 `background` 那条先例）。
        #expect(Theme.Font.markdownBody == Theme.Font.rowTitle)
    }
}
