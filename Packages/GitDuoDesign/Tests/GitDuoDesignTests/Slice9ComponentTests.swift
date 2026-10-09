import SwiftUI
import Testing

@testable import GitDuoDesign

/// 切片 9.3（设计系统）这一片新加的断言。
///
/// 本片真加的东西是**四个新件 + 一条新令牌 + 一处既有件的补口**：
/// `ContributionHeatmap` · `ProfileHeader` · `ProfileStatBar` · `MenuCard`/`MenuRow`
/// · `Theme.Palette.heatmapLevels` · `UserAvatar.initialFont`。
///
/// 与 `Slice4`–`Slice8ComponentTests` 同一条纪律：**不测长相**（那要靠逐屏对照），
/// 只钉两类"错了不会报错"的规则 ——
/// ① **纯函数的算法**（格子尺寸怎么算出来的、档位越界往哪夹）；
/// ② **默认值与取值出处**（新参数有没有把既有调用点带偏、哪一档取的是哪个令牌）。
///
/// ⚠️ 施工图 9.3 那一行写的是「**逐条核实"预计新增"估对没估对**」。
/// 逐条核实结论（细账见 `AGENTS.md` 切片 9 表的 9.3 / 9.3a 行）：
/// **不是零新增** —— 四个新件；而"设置页分区与条目行"里，
/// 分区标题**复用** `SectionHeader`、条目行就是新加的 `MenuRow`；
/// `UserAvatar` 只差一个参数（首字母字号），**不新增组件**。
@MainActor
@Suite("切片 9 组件 · 热力图算法与四个新件的默认值")
struct Slice9ComponentTests {

    // MARK: - 热力图那 5 档令牌

    @Test("⚠️ 5 档色板：正好 5 个，且第 0 档是**最浅**的那一个")
    func heatmapPaletteHasFiveLevels() {
        // 档位数与 `ContributionLevel.scaleCount` 是**两处独立声明**（设计包不依赖领域包），
        // 编译期连不起来 ⇒ 这里至少把本包这一半钉住。
        #expect(Theme.Palette.heatmapLevels.count == 5)
        #expect(ContributionHeatmap.color(for: 0) == Theme.Palette.heatmapLevels[0])

        // ⚠️ 第 0 档必须是**无贡献**那个最浅的灰。它与第 1 档若颠倒，
        // 整张图会变成"贡献越多越白"——而那种图看起来仍然像一张热力图。
        #expect(Theme.Palette.heatmapLevels[0] != Theme.Palette.heatmapLevels[1])
        #expect(Theme.Palette.heatmapLevels[4] != Theme.Palette.heatmapLevels[3])
    }

    @Test("⚠️ 五个色值与原型 `styles/04-screens.css` 第 71–72 行**逐字相同**（冻结在这里）")
    func heatmapPaletteIsFrozenToPrototype() {
        // 原型：`.hm-cell{background:#ebedf0}` / `.l1 #9be9a8` / `.l2 #40c463`
        //      / `.l3 #30a14e` / `.l4 #216e39`
        #expect(Theme.Palette.heatmapLevels[0] == Color(hex: 0xEBEDF0))
        #expect(Theme.Palette.heatmapLevels[1] == Color(hex: 0x9BE9A8))
        #expect(Theme.Palette.heatmapLevels[2] == Color(hex: 0x40C463))
        #expect(Theme.Palette.heatmapLevels[3] == Color(hex: 0x30A14E))
        #expect(Theme.Palette.heatmapLevels[4] == Color(hex: 0x216E39))

        // ⚠️ 这一条是**反万圣节**的那一条：这五个值**不是** GraphQL 的
        // `contributionCalendar.colors` 返回的那套（那套在十月底会被服务端换成南瓜色）。
        // 没法断言"没读接口"，但可以断言"色板是写死的常量" —— 改了就必须过这一关。
    }

    // MARK: - 格子尺寸（本片唯一一处几何算法）

    @Test("⚠️ 一列 7 格；比例以**一格边长**为单位，间距按 2.5/11 算")
    func heatmapUnitGeometry() {
        #expect(ContributionHeatmap.rowCount == 7)
        #expect(abs(ContributionHeatmap.unitRatio - 2.5 / 11) < 1e-9)

        // 53 列：53 格 + 52 个间距
        let wide = ContributionHeatmap.aspectRatio(columnCount: 53)
        #expect(abs(wide.width - (53 + 52 * (2.5 / 11))) < 1e-9)
        // 7 行：7 格 + 6 个间距
        #expect(abs(wide.height - (7 + 6 * (2.5 / 11))) < 1e-9)

        // 一列时没有间距（`n-1 == 0`）—— 写成 `n * (1 + ratio)` 会在这里多出一个间距。
        let single = ContributionHeatmap.aspectRatio(columnCount: 1)
        #expect(abs(single.width - 1) < 1e-9)
        #expect(abs(single.height - (7 + 6 * (2.5 / 11))) < 1e-9)
    }

    @Test("⚠️ 空矩阵回落成 1×1，不是 0 —— 别让它变成一次除零")
    func heatmapAspectRatioFallsBackOnEmpty() {
        let none = ContributionHeatmap.aspectRatio(columnCount: 0)
        #expect(none == CGSize(width: 1, height: 1))
        #expect(ContributionHeatmap.cellSize(forWidth: 342, columnCount: 0) == 0)
        // 负宽度（容器还没量出来时的 `-infinity` / 负数）也归零，不给负的边长。
        #expect(ContributionHeatmap.cellSize(forWidth: -10, columnCount: 53) == 0)
    }

    @Test("⚠️ 一格多大**只**由可用宽度算出来 —— 原型那个 `11px` 不许出现在结果里")
    func heatmapCellSizeIsDerivedFromWidth() {
        // 2026-10-09 实测的那一组：iPhone 17 Pro（402pt 宽）⇒ 卡片可用宽度 342pt。
        let cell = ContributionHeatmap.cellSize(forWidth: 342, columnCount: 53)
        #expect(abs(cell - 342 / (53 + 52 * (2.5 / 11))) < 1e-9)
        #expect(abs(cell - 5.2763) < 0.001)

        // 关键的一条：**它不等于原型那个 11**。照抄 11 会让 53 列要 715pt 才放得下，
        // 而屏幕只有 402pt ⇒ 卡片右边写着「过去一年」，图上却只有半年。
        #expect(cell < 11)

        // 宽度翻倍 ⇒ 格子翻倍（线性），不是"夹在一个固定值上"。
        let doubled = ContributionHeatmap.cellSize(forWidth: 684, columnCount: 53)
        #expect(abs(doubled - cell * 2) < 1e-9)

        // 列数越少格子越大 —— 同一宽度下。
        let few = ContributionHeatmap.cellSize(forWidth: 342, columnCount: 10)
        #expect(few > cell)
    }

    // MARK: - 档位 → 颜色

    @Test("⚠️ 档位越界是**夹取**，不是回落到无贡献")
    func heatmapLevelIsClampedNotFallenBack() {
        #expect(ContributionHeatmap.color(for: 0) == Theme.Palette.heatmapLevels[0])
        #expect(ContributionHeatmap.color(for: 2) == Theme.Palette.heatmapLevels[2])
        #expect(ContributionHeatmap.color(for: 4) == Theme.Palette.heatmapLevels[4])

        // 服务端哪天多一档（5）：夹到最深那一档 —— 那些天仍然看得出"有贡献"。
        // 若回落到第 0 档，那些天会变成空白，而"图少了一块"与"本来就没有"在屏幕上分不出来。
        #expect(ContributionHeatmap.color(for: 5) == Theme.Palette.heatmapLevels[4])
        #expect(ContributionHeatmap.color(for: 99) == Theme.Palette.heatmapLevels[4])
        // 负数（不该出现）夹到第 0 档，而不是崩在数组下标上。
        #expect(ContributionHeatmap.color(for: -1) == Theme.Palette.heatmapLevels[0])
    }

    // MARK: - `UserAvatar` 的第三档（唯一的既有件补口）

    @Test("⚠️ 三档直径：34 / 52 / 86；新加的 86 不与既有两档撞上")
    func avatarDiameters() {
        #expect(UserAvatar.rowDiameter == 34)
        #expect(UserAvatar.sheetDiameter == 52)
        #expect(UserAvatar.profileDiameter == 86)
        #expect(Set([UserAvatar.rowDiameter, UserAvatar.sheetDiameter, UserAvatar.profileDiameter]).count == 3)
    }

    @Test("⚠️ `initialFont` 默认是 `nil` —— 既有两档的首字母字号一个像素都不变")
    func avatarInitialFontDefaultsToNil() {
        // 这一条是本片唯一一处"**别把已验收的页面带偏**"的守卫：
        // 34 / 52 两档在切片 4 / 5 就已验收，当时的首字母是 `Theme.Font.label`（11pt）。
        // 若哪天有人把默认值改成"按直径推导"，那两档会一起变 —— 而屏幕上
        // 只是头像里的字母大了一点点，谁也说不清是哪一天变的。
        let plain = UserAvatar(login: "jiangjiang")
        #expect(plain.initialFont == nil)

        let profile = UserAvatar(
            login: "jiangjiang",
            diameter: UserAvatar.profileDiameter,
            initialFont: UserAvatar.profileInitialFont
        )
        #expect(profile.initialFont != nil)
        #expect(profile.diameter == 86)
    }

    // MARK: - `ProfileHeader`：空白串也算"没有"

    @Test("⚠️ 昵称 / 简介：`nil`、空串、全空白 —— 三种都**整行不渲染**")
    func profileHeaderTreatsBlankAsAbsent() {
        // PRD §4.17：「昵称与简介取不到时**整行不渲染** —— 不留空行、也不显示占位」。
        #expect(ProfileHeader.nonEmpty(nil) == nil)
        #expect(ProfileHeader.nonEmpty("") == nil)
        // ⚠️ 全空白这一档最容易被漏：直接画会占掉一个行高（= "留空行"）。
        #expect(ProfileHeader.nonEmpty("   ") == nil)
        #expect(ProfileHeader.nonEmpty("\n\t ") == nil)

        #expect(ProfileHeader.nonEmpty("Jiang Jiang") == "Jiang Jiang")
        // 前后空白要**去掉**，不是原样画（否则那行文字会离头像偏一点点）。
        #expect(ProfileHeader.nonEmpty("  Jiang Jiang  ") == "Jiang Jiang")

        // 简介的最大宽度是原型逐字（`.bio{max-width:280px}`）。
        #expect(ProfileHeader.bioMaxWidth == 280)
    }

    // MARK: - `ProfileStatBar`：可点 / 不可点

    @Test("⚠️ `action` 默认 `nil`（不可点）—— 原型三项里只有 Star 那一项挂了 onclick")
    func statItemActionDefaultsToNil() {
        let plain = ProfileStatBar.Item(valueText: "42", title: "仓库")
        #expect(plain.action == nil)

        let tappable = ProfileStatBar.Item(valueText: "318", title: "Star", action: {})
        #expect(tappable.action != nil)

        // 三项之间的间距是原型逐字 `gap:26px`（不在 4pt 阶里 ⇒ 写原值）。
        #expect(ProfileStatBar.spacing == 26)
        // ⚠️ 别把它改成"每项等分"：那会在只有两项时把它们推到屏幕两端。
        #expect(ProfileStatBar.topPadding == 14)
        #expect(ProfileStatBar.bottomPadding == 6)
    }

    // MARK: - `MenuRow` 的四组默认值

    @Test("⚠️ `systemImage` 默认 `nil` —— 设置页那五行在原型里**一个图标都没有**")
    func menuRowIconIsOptional() {
        // `12-me.js` 的五个 `.menu-item` 里没有任何 `svg(...)`；
        // 而「我的」页与收藏夹页那几行都有 ⇒ 图标只能是 Optional。
        // 若哪天有人给它一个默认图标，设置页五行会**多出一个原型没有的图标**。
        #expect(MenuRow(title: "主题", value: "浅色").systemImage == nil)
        #expect(MenuRow(systemImage: GitHubIcon.bookmark, title: "我的收藏").systemImage != nil)
    }

    @Test("⚠️ `action` 默认 `nil` —— 不可点的那几行**根本不是按钮**")
    func menuRowTappability() {
        // 设置页的「主题 / GitHub App · 账号 / 版本」三行在原型里没有 `onclick`。
        #expect(MenuRow(title: "版本", value: "2.0 (1)").isTappable == false)
        #expect(MenuRow(title: "清除缓存", value: "12.4 MB", action: {}).isTappable)

        // ⚠️ 不可点 ≠ `.disabled`（那会变灰、像"暂时不可用"，同决策 #51）——
        // 本件是**不画成 Button**，所以这里断言的是"有没有 action"，不是"灰没灰"。
        #expect(MenuRow(title: "退出登录", titleTone: .destructive).isTappable == false)
    }

    @Test("⚠️ 两档标题色各自取的是哪个令牌，且**两档真的不同**")
    func menuRowTitleTones() {
        // `--text`：普通行。
        #expect(MenuRow(title: "Star 管理").titleColor == Theme.Palette.textPrimary)
        // `--closed-p`：退出登录那一行是红字（原型 `12-me.js:70` 的内联 `color:var(--closed-p)`）。
        #expect(MenuRow(title: "退出登录", titleTone: .destructive).titleColor == Theme.Palette.destructive)

        // ⚠️ 两档混用不会报错，只会让「退出登录」看起来像一条普通菜单项 ——
        // 而它是**唯一**一个会把人踢回登录页的动作。
        #expect(MenuRow(title: "退出登录").titleColor != MenuRow(title: "退出登录", titleTone: .destructive).titleColor)

        // 默认档是 `.normal`：既有的调用点（省略它）一个字都不用改。
        #expect(MenuRow(title: "x").titleTone == .normal)
    }

    @Test("默认的附件是 `.none`、默认画分隔线 —— 与 `LinkRow` 同一条处置")
    func menuRowAccessoryAndSeparatorDefaults() {
        let row = MenuRow(title: "主题", value: "浅色")
        #expect(row.accessory == .none)
        // 分隔线由**行**决定（卡片不知道自己装了几行）⇒ 默认画，最后一行传 `false`。
        #expect(row.showsSeparator)

        // 三种附件是**穷尽**的：`value` 是独立的参数（收藏夹行是「3 项 + ›」两样一起）。
        #expect(MenuRow(title: "x", accessory: .chevron).accessory == .chevron)
        #expect(MenuRow(title: "x", accessory: .tag("默认")).accessory == .tag("默认"))
        #expect(MenuRow(title: "x", accessory: .chevron).accessory != .tag("默认"))
    }

    @Test("⚠️ 三个新图标名与原型 `I.*` 对得上（名字写错不会报错，只能靠这份表拦住笔误）")
    func menuIcons() {
        // 原型 `12-me.js:23` = `svg(I.star)`，`:24` = `svg(I.bm)`，`:29` = `svg(I.gear)`。
        #expect(GitHubIcon.star == "star")
        #expect(GitHubIcon.bookmark == "bookmark")
        #expect(GitHubIcon.settings == "gearshape")

        // ⚠️ 「我的 Pull Request / 我的 Issue」两行**不新造常量**：
        // 原型的 `I.pr` / `I.issueO` 正是 `StateIcon` 那两个常量的出处。
        #expect(StateIcon.pullRequestOpen == "arrow.triangle.pull")
        #expect(StateIcon.issueOpen == "smallcircle.filled.circle")
    }
}
