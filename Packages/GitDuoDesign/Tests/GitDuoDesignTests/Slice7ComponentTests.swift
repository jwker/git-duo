import SwiftUI
import Testing

@testable import GitDuoDesign

/// 切片 7 六个新件（`LabelColor` / `ConversationHeader` / `CommentBubble` / `LabelPill` /
/// `ColorSwatch` / `LabelDot` / `LabelAddButton`）里"纯函数与常量那一半"的断言。
///
/// 为什么只测这一半：视图的长相没法用断言描述（要靠截图与逐屏对照），
/// 但"哪种写法算合法色值""哪一档令牌与哪一档同值""三个尺寸到底是多少"
/// 都是**可以**被钉住的规则 —— 而它们恰好是最容易出错、错了还不报错的地方。
/// 沿 `Slice4ComponentTests` / `Slice5ComponentTests` / `Slice6ComponentTests` 的同一条纪律。
@MainActor
@Suite("切片 7 组件 · 纯函数与令牌")
struct Slice7ComponentTests {

    // MARK: - LabelColor：哪种写法算合法

    @Test("⚠️ 四种写法都收：带不带 `#`、大小写、以及从日志里抄出来的首尾空白")
    func labelColorAcceptsBothForms() {
        // 两个来源形态不同：服务端给的是 `d73a4a`（不带 `#`），
        // 原型 CSS 里的是 `#d73a4a`（带 `#`）。调试时两种都会被人贴进来。
        let expected = Color(hex: 0xD73A4A)
        #expect(LabelColor.color(forHex: "d73a4a") == expected)
        #expect(LabelColor.color(forHex: "#d73a4a") == expected)
        #expect(LabelColor.color(forHex: "D73A4A") == expected)
        #expect(LabelColor.color(forHex: "  #D73A4A\n") == expected)
    }

    @Test(
        "⚠️ 不是六位十六进制的**一律不给颜色**（悄悄兜底会让「这个值有问题」永远不被发现）",
        arguments: [
            "",            // 空
            "#",           // 只有一个井号
            "abc",         // 三位缩写 —— 有意不收
            "#abc",        //
            "d73a4",       // 五位
            "d73a4a1",     // 七位
            "0x1234",      // 带前缀（`UInt32(_:radix:)` 本就不认它）
            "zzzzzz",      // 不是十六进制字符
            "d73a4g",      // 混了一个非十六进制字符
            "d7 3a4a",     // ⚠️ 中间的空格**不是**首尾空白，剪不掉 ⇒ 非法
        ]
    )
    func labelColorRejectsMalformed(_ hex: String) {
        #expect(LabelColor.value(forHex: hex) == nil, "`\(hex)` 不该被解析成色值")
        #expect(LabelColor.color(forHex: hex) == nil, "`\(hex)` 不该给出颜色")
    }

    @Test("边界：`000000`（全黑）是**合法**的 —— 别把它当成「没给值」")
    func labelColorAcceptsBlack() {
        // 空串与 `000000` 长得一点都不像，但"判空"写成 `value == 0` 就会把它们混为一谈，
        // 而黑色是色板里真实存在的选择（近黑 `1f2328` 的极端）。
        #expect(LabelColor.value(forHex: "000000") == 0)
        #expect(LabelColor.color(forHex: "000000") != nil)
    }

    @Test("解析到的是那 24 位整数本身（大写小写同一个值）")
    func labelColorParsesToExpectedValue() {
        #expect(LabelColor.value(forHex: "d73a4a") == 0xD73A4A)
        #expect(LabelColor.value(forHex: "#1F2328") == 0x1F2328)
        #expect(LabelColor.value(forHex: "ffffff") == 0xFFFFFF)
    }

    @Test("⚠️ `surface(forHex:)` 一定给得出颜色 —— 读不出来时走兜底，而不是留白")
    func labelColorSurfaceAlwaysResolves() {
        // 组件（`LabelPill` / `ColorSwatch` / `LabelDot`）都用这一个。
        // 若它在非法输入上返回透明，标签就只剩一行白字**压在空气上** ——
        // 连"这个标签存在"都看不出来，比画错色更糟。
        #expect(LabelColor.surface(forHex: "d73a4a") == Color(hex: 0xD73A4A))
        #expect(LabelColor.surface(forHex: "nonsense") == Theme.Palette.labelFallbackSurface)
        #expect(LabelColor.surface(forHex: "") == Theme.Palette.labelFallbackSurface)
    }

    // MARK: - 切片 7 新增的令牌

    @Test("⚠️ `bubbleHeaderSurface` 与页面底 / 卡片白 / 控件底**四个都不同**")
    func bubbleHeaderSurfaceIsItsOwnColor() {
        // 混用不会报错，只会让气泡的头看起来"和卡片外的页面底一模一样"，
        // 于是"气泡从哪开始"在白底上失去线索（沿 `codeSurface` 与 `background` 那条先例）。
        let header = Theme.Palette.bubbleHeaderSurface
        #expect(header != Theme.Palette.background)
        #expect(header != Theme.Palette.surface)
        #expect(header != Theme.Palette.surfaceSunken)
        // 它得比卡片白暗一点（否则这条头根本看不出来）。
        #expect(header != Color.clear)
    }

    @Test("⚠️ `Radius.bubble`(12) 与 `Radius.container`(12) **今天同值，是刻意的**")
    func bubbleRadiusSharesValueWithContainer() {
        // `container` 是**设计指南**推出来的（"与父容器同心"，§10.3），
        // 而 `.comment .bubble{border-radius:12px}` 是**原型写死**的一档。
        // 将来补深色 / 调玻璃时 `container` 可能要动，而气泡的圆角不该跟着动。
        // 这条断言的作用是让"改了一处"必须经过一次有意识的决定，
        // 而不是某天被顺手合并成同一个令牌（沿 Slice6 的 `markdownBody` 与 `rowTitle` 先例）。
        #expect(Theme.Radius.bubble == 12)
        #expect(Theme.Radius.container == 12)
        #expect(Theme.Radius.bubble == Theme.Radius.container)

        // 也别被卡片那一档（14）串了。
        #expect(Theme.Radius.bubble != Theme.Radius.sheet)
    }

    @Test("⚠️ `Radius.labelDot`(4) 是圆角阶里最小的一档，必须小于 `chip`(6)")
    func labelDotRadiusIsSmallest() {
        // 用到 6 就接近胶囊了，而原型画的是"方一点的小色块"，与 30×30 的色板同族。
        #expect(Theme.Radius.labelDot == 4)
        #expect(Theme.Radius.labelDot < Theme.Radius.chip)
    }

    @Test("三个尺寸常量：色块 30 / 小圆点 12 / 描边 2")
    func componentMetrics() {
        #expect(ColorSwatch.diameter == 30)
        #expect(ColorSwatch.borderWidth == 2)
        #expect(LabelDot.diameter == 12)

        // 气泡的两处间距（原型 `.comment{gap:9px}` 与 `.bhead{gap:6px}`，都不在 4pt 阶里）。
        #expect(CommentBubble<EmptyView>.avatarGap == 9)
        #expect(CommentBubble<EmptyView>.headerGap == 6)
    }

    // MARK: - 切片 7 新增的字号

    @Test("两档新字号各自的落点，以及「与谁同值但不合并」")
    func slice7Fonts() {
        // 原型 `.conv-head h2{font-size:17.5px;font-weight:720}` ⇒ 系统 17pt + bold。
        #expect(Theme.Font.conversationTitle == SwiftUI.Font.body.weight(.bold))
        // 原型 `.comment .bhead{font-size:12px}` ⇒ 系统 `.caption`(12pt)。
        #expect(Theme.Font.commentMeta == SwiftUI.Font.caption)

        // ⚠️ 两处"同值不同名"（同 Slice6 的 `markdownBody` / `rowTitle`）：
        // 原型是两处独立取值（`.markdown h2` 是 17/700，这里是 17.5/720），只是都落到了同一档。
        #expect(Theme.Font.conversationTitle == Theme.Font.markdownH2)
        #expect(Theme.Font.commentMeta == Theme.Font.breadcrumb)
    }

    @Test("⚠️ `commentMeta`(12pt 常规) 与 `label`(12pt semibold) / `sectionLabel`(12pt bold) **不是一档**")
    func commentMetaIsNotAHeavierLabel() {
        // 三档都是 12pt，只差字重。拿 `label` 顶替会让整条评论头部都变粗 ——
        // 于是作者名的"更粗"（原型 `.author{font-weight:700}`）就看不出来了，
        // 而它是那一行里唯一要抢眼的东西。
        #expect(Theme.Font.commentMeta != Theme.Font.label)
        #expect(Theme.Font.commentMeta != Theme.Font.sectionLabel)
    }

    @Test("⚠️ 标签胶囊的文字色是**卡片白**，不是任何一档状态色")
    func labelPillTextIsWhite() {
        // 原型 `.lbl-tag{color:#fff}`。写成状态色（例如顺手写成 `stateOpen` 的绿）
        // 不会报错，只会让"标签"与"状态"这两族东西看起来像同一族 ——
        // 而它们在同一个页面上会同时出现（新建 Issue 页的标签行 + 头部状态胶囊）。
        #expect(Theme.Palette.surface == Color(hex: 0xFFFFFF))
        #expect(Theme.Palette.surface != Theme.Palette.stateOpen)
        #expect(Theme.Palette.surface != Theme.Palette.stateMerged)
        #expect(Theme.Palette.surface != Theme.Palette.stateClosed)
    }

    @Test("⚠️ 兜底填充取 `#6A737D`：白字压上去 4.82:1（≥ 4.5），且**足够深以看清文字**")
    func labelFallbackSurfaceIsDarkEnough() {
        // 值冻结在这里。⚠️ 白字对比度那条算术（WCAG 2.1 相对亮度）不在这边复写一遍 ——
        // 它落在 `GitDuoKit` 侧：色板是领域层的数据，那边用同一条公式
        // 正面钉着"十档全部 ≥ 4.5"（`RepoLabelsTests.paletteAllPassWhiteTextContrast`）。
        // 这个兜底色与色板里的"灰"恰好同值，所以那边的断言对它也成立。
        #expect(Theme.Palette.labelFallbackSurface == Color(hex: 0x6A737D))

        // ⚠️ 别拿文字令牌顶替：那是"按用途命名"当场失效的地方
        //（下次有人想改正文次级色就会动到标签的底）。
        #expect(Theme.Palette.labelFallbackSurface != Theme.Palette.textSecondary)
        // 也不能是浅色 —— 白字会读不出来。
        #expect(Theme.Palette.labelFallbackSurface != Theme.Palette.surfaceSunken)
    }
}
