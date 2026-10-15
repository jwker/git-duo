import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 设计令牌 —— 颜色 / 字号 / 间距 / 圆角的**唯一定义处**。
///
/// 依据：TECH_SPEC §10.7。
/// 铁律：
/// 1. 业务代码**禁止写魔法值**（颜色、字号、间距、圆角一律引用本文件的令牌）。
/// 2. 令牌按**用途**命名，不按色相命名（禁 `gray600` / `blue500` 这类）。
/// 3. 每个色令牌**浅深两列都在本文件**（`Color(light:dark:)`），深色列统一取自
///    Primer primitives v8.2.0 dark —— 2026-10-15 接通（走查第 69 条）；
///    此前的口径"只定义浅色、深色只补一列映射"就是照这条路预留的，兑现时没有动任何视图。
/// 4. ⚠️ Liquid Glass 深浅色的 tint 混合比例不同（浅 ≈30% / 深 ≈50%，§10.4 #4），
///    因此**玻璃着色值也必须走令牌**（`glassTint`），不得内联色值。
public enum Theme {

    // MARK: - 颜色（浅深双列；浅色取值与原型 `redesign/prototype/styles/01-base.css` 的 `:root` 一致，
    //        深色列统一取自 Primer primitives v8.2.0 dark —— 出处标在各令牌行尾）

    public enum Palette {
        // 深色列统一取自 Primer primitives v8.2.0 dark（出处标在各令牌下；见 Color.init(light:dark:) 的说明）。

        public static let background      = Color(light: 0xF6F8FA, dark: 0x0D1117)  // 深 = bgColor-default
        public static let surface         = Color(light: 0xFFFFFF, dark: 0x161B22)  // 深 = bgColor-muted
        public static let surfaceRaised   = Color(light: 0xFFFFFF, dark: 0x161B22)  // 深 = bgColor-muted（同 surface）
        public static let surfaceSunken   = Color(light: 0xEFF2F5, dark: 0x0D1117)  // 深 = 页面底一档（bgColor-default）：深色下"内凹"= 比卡面暗
        public static let border          = Color(light: 0xD0D7DE, dark: 0x30363D)  // 深 = borderColor-default
        public static let borderSoft      = Color(light: 0xE8ECEF, lightAlpha: 1, dark: 0x30363D, darkAlpha: 0.7)  // 深 = borderColor-muted (#30363db3)

        public static let textPrimary     = Color(light: 0x1F2328, dark: 0xE6EDF3)  // 深 = fgColor-default
        public static let textSecondary   = Color(light: 0x656D76, dark: 0x8D96A0)  // 深 = fgColor-muted
        public static let textTertiary    = Color(light: 0x8B949E, dark: 0x6E7681)  // 深 = fg.subtle（v8 已无该 token；#6E7681 同其 bgColor-neutral-emphasis 真值）

        public static let accent          = Color(light: 0x0969DA, dark: 0x4493F8)  // 深 = fgColor-accent // 链接 / 强调
        public static let accentStrong    = Color(light: 0x1F883D, dark: 0x238636)  // 深 = button-primary-bgColor-rest // 主按钮（GitHub 绿）
        public static let destructive     = Color(light: 0xCF222E, dark: 0xF85149)  // 深 = fgColor-danger // 危险操作（删除 / 退出登录）

        /// 状态色沿用 GitHub 语义（PRD §1 / §10.7 一致口径）：
        /// 开放 = 绿 · 已合并 = 紫 · 已关闭 = 红 · 已发布 = 紫
        /// ⚠️ 已合并与已发布**有意同色**——它们同属"完成 / 发布"紫族，
        /// 靠**文案与图标**区分而非颜色（GitHub 网页端同样如此）。改色前先读 ThemeTests 的不变式。
        public static let stateOpen       = Color(light: 0x1A7F37, dark: 0x3FB950)  // 深 = fgColor-open // 开放 = 绿
        public static let stateMerged     = Color(light: 0x8250DF, dark: 0xAB7DF8)  // 深 = fgColor-done // 已合并 = 紫
        public static let stateReleased   = Color(light: 0x8250DF, dark: 0xAB7DF8)  // 深 = fgColor-done（与 merged 同色，见上）// 已发布 = 紫
        public static let stateClosed     = Color(light: 0xCF222E, dark: 0xF85149)  // 深 = fgColor-closed // 已关闭 / 未合并 = 红

        // MARK: 状态**胶囊**的底与边（切片 5 新增）

        /// 上面那三个 `state*` 是胶囊的**前景**色，这一组是配套的**底 / 边**。
        ///
        /// 出处：原型 `styles/03-components.css` 的 `.pill.open` / `.pill.merged` /
        /// `.pill.closed-p` —— 那里的底与边都是**内联色值**（`#f0fff4` / `#a4d8b0` …），
        /// 不是变量，所以此前没有名字；不给名字就只能在各处写内联色值，而那正是"魔法值"。
        ///
        /// ⚠️ **只有三族**：原型里 `.pill.closed-i`（已关闭的 Issue）与 `.pill.merged`
        /// 的底与边**完全相同**（紫族），故不另立一组同值异名的 token
        /// （沿 `stateCompletedIcon` 那条"按族命名、不按单个状态命名"的先例）。
        // ⚠️ 深色档的"浅底"不再是浅色 —— Primer dark 把 subtle 底定义成**同色相低透明**
        //（`#2ea0431a` 这类）压在深卡面上。透明度照抄 Primer 的十六进制 alpha 位。
        public static let stateOpenSurface   = Color(light: 0xF0FFF4, lightAlpha: 1, dark: 0x2EA043, darkAlpha: 0.10)  // `.pill.open` 底（深 = bgColor-open-muted #2ea0431a）
        public static let stateOpenBorder    = Color(light: 0xA4D8B0, lightAlpha: 1, dark: 0x2EA043, darkAlpha: 0.40)  // `.pill.open` 边（深 = borderColor-open-muted #2ea04366）
        public static let stateMergedSurface = Color(light: 0xFAF5FF, lightAlpha: 1, dark: 0xAB7DF8, darkAlpha: 0.15)  // `.pill.merged` / `.pill.closed-i` 底（深 = bgColor-done-muted #ab7df826）
        public static let stateMergedBorder  = Color(light: 0xD1BCF5, lightAlpha: 1, dark: 0xAB7DF8, darkAlpha: 0.40)  // 同上，边（深 = borderColor-done-muted #ab7df866）
        public static let stateClosedSurface = Color(light: 0xFFF1F2, lightAlpha: 1, dark: 0xF85149, darkAlpha: 0.10)  // `.pill.closed-p` 底（深 = bgColor-closed-muted #f8514926）
        public static let stateClosedBorder  = Color(light: 0xF1B8BF, lightAlpha: 1, dark: 0xF85149, darkAlpha: 0.40)  // 同上，边（深 = borderColor-closed-muted #f8514966）

        /// diff 行底色 / 文字色（深色底同样走"同色相低透明"，深色文字取对应 fg 亮档）
        public static let diffAddedSurface   = Color(light: 0xDAFBE1, lightAlpha: 1, dark: 0x2EA043, darkAlpha: 0.15)  // 深 = bgColor-success-muted #2ea04326
        public static let diffAddedText      = Color(light: 0x116329, dark: 0x3FB950)  // 深 = fgColor-success
        public static let diffDeletedSurface = Color(light: 0xFFEBE9, lightAlpha: 1, dark: 0xF85149, darkAlpha: 0.10)  // 深 = bgColor-danger-muted #f851491a
        public static let diffDeletedText    = Color(light: 0xCF222E, dark: 0xF85149)  // 深 = fgColor-danger

        /// 代码面底色 —— 搜索结果「代码」范围的等宽预览行（原型
        /// `styles/01-base.css` 的 `--code-bg:#f6f8fa`，用于 `.sr-code`）。
        ///
        /// ⚠️ 它的值与 `background`（`#F6F8FA`）**今天完全相同**，但**不是同一个令牌**：
        /// 原型里本来就是两个独立变量（`--bg` 与 `--code-bg`），用途也不同 ——
        /// 一个是页面底，一个是"嵌在白色卡片里的一小块代码面"。将来补深色时两者未必同步变化
        /// （代码面通常要比页面底再深一档才分得出来），届时合并会逼着一起改。
        /// 沿 `repoAvatarSurface` 那条"接近但不是同一个值 ⇒ 两处独立取色"的先例。
        ///
        /// 深色档兑现了上面的预告：代码面比卡面（`#161b22`）**再深一档**，取页面底
        /// `#0d1117`（bgColor-default）—— 与浅色的"比卡面浅一档"方向相反，
        /// 但意图一致：**代码面要和嵌着它的卡面分得开**。
        public static let codeSurface    = Color(light: 0xF6F8FA, dark: 0x0D1117)

        // MARK: 切片 6 新增 —— 语法高亮四色 + 两处浅底（出处见 TECH_SPEC §10.7）

        /// **语法着色**的四档前景色 —— 原型 `styles/04-screens.css` 第 27 行的
        /// `.kw{color:#cf222e}.fn{color:#8250df}.st{color:#0a3069}.cm{color:#6e7781}`
        /// （`.markdown pre code` 里那四个类）。
        ///
        /// ⚠️ **只有四档**，而领域层的 `SyntaxTokenKind` 有七档
        /// （`plain` / `keyword` / `string` / `comment` / `number` / `function` / `type`）。
        /// 原型只演示了一段含关键字·函数名·字符串·注释的 Swift 代码，
        /// **没有给数字与类型名任何颜色** ⇒ 那两档**不着色**（落到 `textPrimary`），
        /// 已登记为「规格未给，待评审」。**不要**为了"看起来更丰富"从这四色里挑一个塞给它们 ——
        /// 那是自造视觉，而原型是唯一可点验收依据。
        ///
        /// ⚠️ 四色**互不相同、且都不等于 `textPrimary`**：
        /// 取错一个（例如把 `syntaxString` 写成 `syntaxComment` 的灰）不会报错，
        /// 只会让代码看起来"颜色怪怪的"。`Slice6ComponentTests` 把这两条都钉住了。
        public static let syntaxKeyword  = Color(light: 0xCF222E, dark: 0xFF7B72)  // 深 = prettylights.syntax.keyword
        public static let syntaxFunction = Color(light: 0x8250DF, dark: 0xD2A8FF)  // 深 = prettylights.syntax.entity
        public static let syntaxString   = Color(light: 0x0A3069, dark: 0xA5D6FF)  // 深 = prettylights.syntax.string
        public static let syntaxComment  = Color(light: 0x6E7781, dark: 0x8B949E)  // 深 = prettylights.syntax.comment

        /// **强调色的浅底** —— 原型 `styles/04-screens.css` 的
        /// `.hunk{background:#ddf4ff}` **与** `.sha{background:#ddf4ff}`。
        ///
        /// ⚠️ 两处**同值**，故合成一档、不立同值异名（沿 `stateMerged` 同时管
        /// `.pill.merged` 与 `.pill.closed-i` 的先例）。它管的两件事其实是同一件：
        /// "**把一段信息标成参考性 / 元信息**"—— diff 的 hunk 头与提交的短 SHA 都是这类。
        /// 文字色一律配 `accent`（原型的 `.hunk{color:#0969da}` 与 `.sha{color:var(--link)}` 同值）。
        ///
        /// ⚠️ 它与 `accentSurface`（`#F0F6FF`，筛选 chip 选中态）**不是**同一个值：
        /// 这个偏青一档、那个偏灰一档。混用会让 hunk 头与"已选 chip"看起来像同一族控件。
        ///
        /// ⚠️ **深色档两处同值**（都取 `bgColor-accent-muted` 的 `#388bfd1a`）—— 有意的合并：
        /// Primer dark 只给了这一档"强调淡底"，浅色下那 0.06 的色相差在深底上不可辨。
        /// 两个令牌**仍然分开定义**（沿"同值不是同一个令牌"的判例），将来要拆随时能拆。
        public static let accentSubtle   = Color(light: 0xDDF4FF, lightAlpha: 1, dark: 0x388BFD, darkAlpha: 0.10)

        /// **行内代码**的底 —— 原型 `styles/04-screens.css` 的
        /// `.markdown code{background:rgba(175,184,193,.35)}`。
        ///
        /// ⚠️ 它是**半透明**的：行内代码嵌在正文段落里，底必须能透出下面的卡片白
        /// （照 `toastSurface` 那条"带透明度是刻意的"先例）。换成不透明色会让这一小段
        /// 看起来像贴上去的贴纸。
        ///
        /// 深色取 `bgColor-neutral-muted`（`#6e768166`，alpha 0.4）—— 透出的是**深卡面**，
        /// 透明度照抄 Primer 的 `66` 位。
        public static let codeInlineSurface = Color(light: 0xAFB8C1, lightAlpha: 0.35, dark: 0x6E7681, darkAlpha: 0.4)

        // MARK: 状态**图标**的配色（与上面那组"状态胶囊"的配色**不是**同一套值）

        /// 开放状态的**图标**绿 —— 原型 `styles/03-components.css` 的
        /// `.ic-open` / `.ic-pr{fill:#3fb950}`。
        ///
        /// ⚠️ 它与 `stateOpen`（`#1A7F37`，状态**胶囊**的绿；原型 `--open`）**不是同一个值**。
        /// 原型里这两套颜色是分开的，对应 GitHub 自家的做法：octicon 的图标色比标签色亮一档。
        /// 混用的后果不是"报错"，而是"图标与旁边那颗状态点颜色微妙地不一致"——
        /// 看起来像渲染坏了，而排查时很难想到是取错了 token。
        ///
        /// ⚠️ **深浅同值**（`#3fb950`）：GitHub 深色下 octicon 的开放绿就是它
        /// —— 浅色档本来就是从深色那档借来的亮绿，两档恰好归一。
        public static let stateOpenIcon     = Color(hex: 0x3FB950)

        /// 「完成」紫的**图标**色 —— 原型 `.ic-closed-i` / `.ic-merge{fill:#a371f7}`。
        ///
        /// 一个值覆盖三种状态（**已合并的 PR · 已发布的版本 · 已关闭的 Issue**）：
        /// 原型里这三处的图标色本来就相同，GitHub 也把它们归在同一族（"已完成"）。
        /// 所以它按**族**命名，不按单个状态命名 —— 按状态命名会让下一次"另一张卡也要用它"
        /// 时冒出一个同值不同名的新 token。
        /// ⚠️ 同样与状态胶囊的紫 `stateMerged`（`#8250DF`）不是同一个值。
        /// 深色取 `fgColor-done`（`#ab7df8`）—— 深色下它反而与 `stateMerged` 同值了
        /// （Primer dark 把 fg 与 icon 两档合并），图标与标签的一致性由 GitHub 自己背书。
        public static let stateCompletedIcon = Color(light: 0xA371F7, dark: 0xAB7DF8)

        // MARK: 切片 4 新增（出处与理由见 TECH_SPEC §10.7）

        /// **已 Star** 态的金色 —— 原型 `styles/04-screens.css` 的 `.stat-btn.starred svg{fill:#eac54f}`。
        ///
        /// ⚠️ 只用于**星形图标的填充 / 描边**，绝不用作文字色或背景色：
        /// 金色在白底上的对比度不足 2:1，承载正文必然读不清。
        /// 它与 `stateOpen`（开放 = 绿）毫无语义关系，别因为"都是好看的颜色"而合并。
        ///
        /// 深色取 `#e3b341`（GitHub Dark 的 yellow，`primer/github-vscode-theme` 官方表）
        /// —— GitHub 深色下"已 Star"的星就是这一档，比浅色金再亮半档。
        public static let starActive     = Color(light: 0xEAC54F, dark: 0xE3B341)

        /// 语言构成占比条里**「其他」段**的中性填充（原型 `scripts/10-explore-repo.js` 的 `#d1d5da`）。
        ///
        /// 它只表示"这里是若干语言的合计"，**不表示任何状态** ——
        /// 所以既不复用状态色，也不走 `LanguageColor`（那个表的每一项都对应一个真实语言）。
        ///
        /// 深色取 `#6e7681`（v8.2.0 `bgColor-neutral-emphasis` 真值）：深色下"不抢眼"
        /// 的方向是**更暗**（浅色下是更浅），见 `ThemeTests` 的双档断言。
        public static let shareNeutral   = Color(light: 0xD1D5DA, dark: 0x6E7681)

        /// 筛选 chip 的**已选**底色（原型 `styles/03-components.css` 的 `.fchip.on{background:#f0f6ff}`）。
        ///
        /// 原型这处写的是一个内联色值而非变量，所以它此前没有名字。
        /// 它是"强调色的极浅底"——与 `accent`（`#0969DA`）成对使用：
        /// chip 选中时**底 + 边框 + 文字**三处都是强调色的不同浓淡。
        /// ⚠️ 不要拿 `surfaceSunken` 顶替：那是中性灰，会让"已选"看起来像"禁用"。
        ///
        /// ⚠️ **深色档与 `accentSubtle` 同值**（`#388bfd1a`）—— 有意合并，见那边的说明。
        public static let accentSurface  = Color(light: 0xF0F6FF, lightAlpha: 1, dark: 0x388BFD, darkAlpha: 0.10)

        // MARK: 轻提示（Toast）—— 原型 `styles/05-overlays.css` 的 `.toast`

        /// Toast 的深色底（原型 `rgba(28,32,36,.92)`）。
        ///
        /// ⚠️ 它**不是** `repoAvatarSurface`（`#24292F`）——两个值很接近但来源不同：
        /// 那个是图标块的实色底，这个是**带 8% 透明**的浮层底（要能透出一点下面的内容，
        /// 才不至于像一块贴上去的不透明补丁）。混用会让 Toast 显得比原型"实"。
        ///
        /// 深色取 `#292e36`（v8.2.0 `control-bgColor-hover`）压 0.92：深色页面上 Toast
        /// 要比页面底（`#0d1117`）**亮**才浮得起来，取"浮起控件"那一档的真值。
        public static let toastSurface   = Color(light: 0x1C2024, lightAlpha: 0.92, dark: 0x292E36, darkAlpha: 0.92)

        /// Toast 上的文字色。**一个不透明纯白** —— 它压在 `toastSurface` 上，
        /// 对比度约 15:1，远超 AA；但也正因如此它**只能**用在深底上（放白底上读不出来）。
        /// ⚠️ **深浅同值**：两档的 Toast 底都是深色（深色档取亮一档的 `#292e36`），白字两档都成立。
        public static let toastText      = Color(hex: 0xFFFFFF)

        /// 仓库图标块的底色（原型 `.repo-avatar{background:#24292f}`，白色字形压在上面）。
        ///
        /// ⚠️ 它与 `textPrimary`（`#1F2328`）**接近但不是同一个值**，是两处独立取色：
        /// 一个是"正文最深的字"，一个是"图标块的底"。混用会在将来补深色时
        /// 把两者一起改掉，而它们并不该同步变化。
        ///
        /// 深色取 `#21262d`（v8.2.0 `control-bgColor-rest`）：深卡面（`#161b22`）上
        /// 亮一档的灰块，白字形照旧压得读出（≥ 14:1）。
        public static let repoAvatarSurface = Color(light: 0x24292F, dark: 0x21262D)

        /// 头像图片**取不到时**的兜底配色（原型 `scripts/10-explore-repo.js` 的 8 色）。
        ///
        /// 取色下标由登录名的稳定哈希决定 —— **不要用 `hashValue`**（Swift 的哈希每个进程随机化，
        /// 同一账号会在每次启动后换色，甚至在一次会话里因列表重绘而换色）。
        ///
        /// ⚠️ **深浅同值**：这是**内容色**（GitHub 语言色系），GitHub 深色界面直接沿用
        /// 同一套 —— 不走主题映射。
        public static let avatarFallback: [Color] = [
            Color(hex: 0x1F883D), Color(hex: 0x8250DF), Color(hex: 0xD73A4A), Color(hex: 0xE16F24),
            Color(hex: 0x0075CA), Color(hex: 0xDB61A2), Color(hex: 0x5B3A8E), Color(hex: 0x0E8A16),
        ]

        /// 玻璃着色值（浅色约 30% 混合，**深色 50%** —— §10.4 #4：两种模式混合比例不同）
        public static let glassTint       = Color(light: 0xFFFFFF, lightAlpha: 0.30, dark: 0xFFFFFF, darkAlpha: 0.50)

        // MARK: 切片 7 新增（出处与理由见 TECH_SPEC §10.7）

        /// **评论气泡头部条**的底 —— 原型 `styles/04-screens.css` 第 34 行的
        /// `.comment .bhead{background:#f9fafb}`。
        ///
        /// 出处是**内联色值**（不是变量），所以此前没有名字。
        ///
        /// ⚠️ 它与 `background`（`#F6F8FA`）**很接近但不是同一个值**，
        /// 也不能拿 `surfaceSunken`（`#EFF2F5`）顶替：
        /// - `bubbleHeaderSurface` → 白气泡**内部**的一条浅灰头，比卡片白暗一点点就够；
        /// - `surfaceSunken` → 嵌在页面里的控件底（`.btn.ghost` / `.prtabs` 的槽），
        ///   它比这一条暗一档。
        ///
        /// 混用（例如拿 `background` 顶替）不会报错，只会让气泡的头看起来**和卡片外的页面底
        /// 一模一样**，于是"气泡从哪开始"这件事在白底上失去线索。
        /// 沿 `codeSurface` / `background` 那条"接近但不是同一个值 ⇒ 两处独立取色"的先例。
        ///
        /// 深色取 `#21262d`（v8.2.0 `control-bgColor-rest`）：深色下分层方向反转，
        /// 头条要比气泡体（卡面 `#161b22`）**亮**一档才分得出来。
        public static let bubbleHeaderSurface = Color(light: 0xF9FAFB, dark: 0x21262D)

        /// **色值读不出来时**的兜底填充（标签胶囊 / 色块）。
        ///
        /// ## ⚠️「规格未给，待评审」—— 原型一次都没渲染过这一档
        ///
        /// 实时数据里它只会在**服务端回了一个不是六位十六进制的色值**时出现
        /// （GitHub 正常路径永远回六位小写十六进制）。没有兜底的话，
        /// `LabelColor.color(forHex:)` 返回 `nil`，标签就只剩一行白字**压在空气上** ——
        /// 连"这个标签存在"都看不出来，比画错色更糟。
        ///
        /// ## 选它的唯一判据：白字压上去读得出来
        ///
        /// 值取 `#6A737D`（白字对比度 **4.82:1**）。它恰好与颜色色板里的"灰"同值，
        /// 但**那是巧合，不是同一个东西**：
        /// - 色板里的灰是**产品给用户选的一个颜色**，改它要同步改原型与 PRD；
        /// - 这一档是**读不出来时的兜底表象**，将来改成斜纹 / 边框 / 问号图标都不会碰色板。
        ///
        /// 沿 `codeSurface` / `background` 那条"同值不是同一个令牌、将来未必同步变化"的判例。
        /// ⚠️ 别拿 `textSecondary`（`#656D76`）顶替 —— 那是个**文字**令牌，
        /// 让"按用途命名"这条规矩当场失效（下次有人想改正文次级色就会动到标签的底）。
        ///
        /// ⚠️ **深浅同值**：它的判据是"**白字压上去读得出来**"（≥ 4.8:1），
        /// 这一条在深底上同样成立（`#6A737D` 压 `#161b22` 也分得开）⇒ 不需要深色变体。
        public static let labelFallbackSurface = Color(hex: 0x6A737D)

        // MARK: 切片 9 新增（出处与理由见 TECH_SPEC §9.14 / 决策 #74③）

        /// **贡献热力图**的 5 档配色 —— 原型 `styles/04-screens.css` 第 71–72 行的
        /// `.hm-cell` / `.hm-cell.l1…l4`。
        ///
        /// ```css
        /// .hm-cell{background:#ebedf0}
        /// .hm-cell.l1{background:#9be9a8}.hm-cell.l2{background:#40c463}
        /// .hm-cell.l3{background:#30a14e}.hm-cell.l4{background:#216e39}
        /// ```
        ///
        /// **下标 = 档位**（`0` = 无贡献，`4` = 最深），与 `ContributionLevel.scale` 同一顺序。
        ///
        /// ## ⚠️⚠️ 它**不是**从接口返回值里读来的
        ///
        /// GraphQL 的 `contributionCalendar.colors` 会返回 GitHub 自己那套色值
        /// （`contributionLevel` 就是拿去索引它的）。**不能用**，理由有二：
        ///
        /// 1. **万圣节期间那套色值会被整体换成南瓜色**（官方对 `isHalloween` 的注释
        ///    写着 *"if true, the colors will be forced to Halloween colors"*）——
        ///    照抄就会让这个 App 的界面在十月底跟着变，而**那是服务端的一个彩蛋，不是产品决定**；
        /// 2. 那套色值**只保证是一串能用的颜色**，不保证对比度 / 与浅色主题相配。
        ///
        /// 决策 **#74③** 明写「配色走设计令牌」。这也正好与"颜色一律走语义 token、
        /// 补深色时只改这一处"的既有口径一致（`TECH_SPEC §10.7`）。
        ///
        /// ## ⚠️ 档位数与服务端是**两处独立声明**，编译期连不起来
        ///
        /// `GitDuoKit` 有 `ContributionLevel.scaleCount = 5`，这里是 5 个元素 ——
        /// 而**设计包不依赖领域包**（依赖铁律），所以"两边都是 5"这件事
        /// **没有任何一行代码能断言**。哪天服务端多一档：
        /// 领域层那边 `translate` 会按"有没有贡献"兜底（不会崩），
        /// 这里 `ContributionHeatmap` 会把越界的档位夹到最后一个颜色（也不会崩）——
        /// 两处都不报错，只是图变得不准。**改档位数时请两边一起改**。
        ///
        /// 深色档取 GitHub 贡献日历官方深色五档
        ///（`#161b22 #0e4429 #006d32 #26a641 #39d353`，2026-10-15 多源核对）——
        /// 它不在 Primer functional tokens 里，是日历组件的专属配色。
        public static let heatmapLevels: [Color] = [
            Color(light: 0xEBEDF0, dark: 0x161B22),   // 无贡献（`.hm-cell` 的底色）
            Color(light: 0x9BE9A8, dark: 0x0E4429),   // `.l1`
            Color(light: 0x40C463, dark: 0x006D32),   // `.l2`
            Color(light: 0x30A14E, dark: 0x26A641),   // `.l3`
            Color(light: 0x216E39, dark: 0x39D353),   // `.l4`
        ]
    }

    // MARK: - 间距（4pt 基准）

    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat  = 4
        public static let s: CGFloat   = 8
        public static let m: CGFloat   = 12
        public static let l: CGFloat   = 16
        public static let xl: CGFloat  = 24
        public static let xxl: CGFloat = 32
        /// 页面左右安全边距
        public static let page: CGFloat = 16
    }

    // MARK: - 圆角

    public enum Radius {
        public static let chip: CGFloat  = 6
        /// 分段控件（`.seg`）那一档。原型 `styles/03-components.css` 的 `.seg{border-radius:8px}` ——
        /// 它与 `chip`(6) / `card`(10) 都不同值：原型里这三个数确实是三处独立取色（分段控件比
        /// 小标签更"方"一点、比卡片更紧凑）。不给它名字就只能写 `RoundedRectangle(cornerRadius: 8)`，
        /// 那正是"魔法值"。
        public static let segment: CGFloat = 8
        public static let card: CGFloat  = 10
        public static let sheet: CGFloat = 14
        /// **按钮 · 面包屑条 · 代码面 · 提示条**那一档（切片 6 新增）。
        ///
        /// 原型 `styles/03-components.css` 的 `.btn{border-radius:9px}`、
        /// `styles/04-screens.css` 的 `.crumb{border-radius:9px}` 与
        /// `.markdown pre{border-radius:9px}` —— **三处同为 9**。
        /// 三件东西都是"嵌在卡片里的矩形小块"，原型给了同一个值，
        /// 所以合成一档、不立同值异名（沿 `Radius.segment`(8) 的先例）。
        ///
        /// 第四处来源是切片 7 的 `NoticeBar`：原型 `scripts/06-files.js` 那个失败提示条
        /// 写的是**行内** `border-radius:9px`（不走 CSS 变量），同为 9 ⇒ 并入本档。
        public static let control: CGFloat = 9
        /// **面包屑里的分支胶囊**（原型 `styles/05-overlays.css` 的 `.branch-chip{border-radius:7px}`）。
        ///
        /// ⚠️ 与 `chip`(6) 只差 1pt，但**不能合并**：原型里是两处独立取值
        /// （`.sr-code` / `.ftag` 是 6，`.branch-chip` 是 7），而这一颗是**可点的控件**
        /// （点开切换分支弹层）—— 圆角比纯展示的小标签大一档是有道理的。
        /// 沿 `Radius.hero`(16) / `Radius.field`(11) 的先例：原型里确实存在的一档就必须有名字。
        public static let branchChip: CGFloat = 7
        /// **输入框 / 图标按钮**那一档（切片 5 新增）。
        ///
        /// 原型 `styles/03-components.css` 里 `.searchfield{border-radius:11px}` 与
        /// `.iconbtn{border-radius:11px}` —— 两处**同为 11**，是原型里确实存在的一档
        /// （比 `.card`(10) 方一点、比 `.container`(12) 收一点）。
        /// 不给它名字，搜索页的输入框就只能写 `cornerRadius: 11`，而那正是"魔法值"。
        /// 沿 `Radius.segment`(8) / `Radius.hero`(16) 的先例。
        public static let field: CGFloat = 11
        /// **仓库头部大卡**（原型 `styles/04-screens.css` 的 `.repo-hero{border-radius:16px}`）。
        ///
        /// 与 `sheet`(14) 只差 2pt，但**不能合并**：那是两处独立取色
        /// （`.card` 一族是 14，`.repo-hero` 是 16），而头部大卡是**整屏最大的一块圆角**——
        /// 差 2pt 在这里是看得出来的（它比卡片大一圈、圆角也该跟着大一点）。
        /// 沿 `Radius.segment`(8) 的先例：原型里确实存在的一档，就必须有名字，
        /// 否则只能写 `cornerRadius: 16`，而那正是"魔法值"。
        public static let hero: CGFloat = 16
        /// 与容器同心（Liquid Glass 推荐，§10.3）
        public static let container: CGFloat = 12
        /// **评论气泡**那一档（切片 7 新增）。
        ///
        /// 原型 `styles/04-screens.css` 第 33 行的 `.comment .bubble{border-radius:12px}`。
        ///
        /// ⚠️ 它与 `container`(12) **今天同值，但不是一个令牌**：
        /// `container` 是**设计指南**推出来的（"与父容器同心"，§10.3），只在玻璃那套语境里说话；
        /// 而这一颗是**原型写死的**一档。将来补深色 / 调玻璃时 `container` 可能要动，
        /// 而气泡的圆角不该跟着动 —— 那是"看起来会变形的气泡"。
        /// 沿 `codeSurface` / `background` 那条"同值不是同一个令牌"的判例
        /// （反面是 `Radius.control`：三处**同源于原型**的 9 才合成一档）。
        public static let bubble: CGFloat = 12
        /// **标签小色块**那一档（切片 7 新增）。
        ///
        /// 原型 `styles/03-components.css` 第 59 行的 `.lbl-dot{border-radius:4px}`。
        ///
        /// 4 是圆角阶里**最小的一档**（`chip` 是 6），只服务 12×12 的小方块：
        /// 用 6 会让它看起来像个圆点（12 的方块配 6 的圆角已接近胶囊），
        /// 而原型画的是**方一点的小色块** —— 与旁边 30×30 的 `ColorSwatch` 同族。
        public static let labelDot: CGFloat = 4
    }

    // MARK: - 字号（沿用系统 Dynamic Type 语义层级，不自造点数）

    public enum Font {
        public static let caption     = SwiftUI.Font.caption2
        /// 控件标签（分段控件 / 筛选 chip / 统计按钮 /**Toast**）。
        ///
        /// 为什么需要它：系统 12pt 的语义层是 `.caption`，而 `caption` 这个令牌名在本文件里
        /// 已经用给了 `.caption2`（11pt，原型 `t3` 那一档）。原型里 12px 的控件标签
        /// （`.stat-btn` / `.fchip` / `.linkbtn`）此前没有对应令牌 ——
        /// 不给它一个名字，各处就只能写 `.system(size: 12)`，而那正是"魔法值"。
        public static let label       = SwiftUI.Font.caption.weight(.semibold)
        /// **分区标题**（原型 `.section-label{font-size:12px;font-weight:700}`）。
        ///
        /// ⚠️ 它与 `label` 只差一档字重（`bold` 700 vs `semibold` 600），但**不能合并**：
        /// 原型里这确实是两处独立取字重，而分区标题是**全屏最安静的一级文字**
        /// （12pt 灰字 + 字距），字重掉一档就会显得"和旁边的按钮一样重"。
        /// 所以 `.section-label` 从 `label` 的消费方名单里移到了这里。
        public static let sectionLabel = SwiftUI.Font.caption.weight(.bold)
        /// **标签胶囊**（原型 `.pill{font-size:11px;font-weight:600}`，切片 5 新增）。
        ///
        /// ⚠️ 它与 `caption`（`.caption2`，11pt **regular**）**只差一个字重**，但不能合并：
        /// 胶囊是"一颗带边框的小标签"，字重掉到 regular 会让它比同一行的正文还轻，
        /// 看起来像"这行没写完"。也不能用 `label`（12pt semibold）—— 那比胶囊大一档，
        /// 会让胶囊在结果行里抢走标题的主次。
        public static let tag = SwiftUI.Font.caption2.weight(.semibold)
        /// 行标题（原型 14.5px 那一档：`.file-row .fname` / `.sheet-row`）。
        ///
        /// 14.5px 落在系统 `.subheadline`(15) 与 `.callout`(16) 之间，取前者。
        /// 与 `Font.label` 同一取向：**沿用语义层级、不自造点数**，
        /// 这样它才随 Dynamic Type 一起放大。
        public static let rowTitle    = SwiftUI.Font.subheadline
        public static let footnote    = SwiftUI.Font.footnote
        public static let body        = SwiftUI.Font.body
        public static let bodyStrong  = SwiftUI.Font.body.weight(.semibold)
        public static let headline    = SwiftUI.Font.headline
        public static let title       = SwiftUI.Font.title3.weight(.semibold)
        public static let largeTitle  = SwiftUI.Font.largeTitle.weight(.bold)
        /// 代码 / diff / 提交哈希
        public static let monospaced  = SwiftUI.Font.system(.footnote, design: .monospaced)
        /// **代码预览行**（搜索结果里那一行小字，原型 `.sr-code{font-size:11.5px}`，切片 5 新增）。
        ///
        /// ⚠️ 它比 `monospaced`（`.footnote`，13pt）**小一号**，不能合并：
        /// 预览行嵌在结果行内部，与同行的标题（14.5pt 那一档）之间必须有可辨的主次；
        /// 用 13pt 会与标题撞在一起，"这是代码片段"这件事就看不出来了。
        /// 11.5px 落到 `.caption2`（11pt）—— 与 `t3`（原型同为 11.5px）走的是同一档。
        public static let monospacedPreview = SwiftUI.Font.system(.caption2, design: .monospaced)

        // MARK: 切片 6 新增 —— 代码块 / Markdown 三档（出处见 TECH_SPEC §10.7）

        /// **代码块**的字号（原型 `styles/04-screens.css` 的
        /// `.markdown pre code{font-size:12px}`）。
        ///
        /// ⚠️ 与 `monospaced`（`.footnote`，13pt）与 `monospacedPreview`（`.caption2`，11pt）
        /// 都不同值：12px 正好落在中间那一档 `.caption`。代码块是**要读懂的内容**
        /// （不像预览行那样只是"瞄一眼"），所以比预览行大一档；
        /// 但它嵌在 README 正文里，又不能与相邻的正文（15pt）抢主次。
        public static let monospacedCode = SwiftUI.Font.system(.caption, design: .monospaced)

        /// Markdown **一级标题**（原型 `.markdown h1{font-size:22px;font-weight:750}`）
        /// ⇒ `.title2`(22pt) + bold。
        public static let markdownH1 = SwiftUI.Font.title2.weight(.bold)

        /// Markdown **二级标题**（原型 `.markdown h2{font-size:17px;font-weight:700}`）
        /// ⇒ `.body`(17pt) + bold。
        ///
        /// ⚠️ 与 `bodyStrong`（`.body.weight(.semibold)`）**只差一档字重**，但不能合并：
        /// 原型里 h2 是 700（bold），而 `bodyStrong` 是别处的 semibold。
        /// 沿 `label`(12 semibold) 与 `sectionLabel`(12 bold) 那条"同值不同字重不合并"的先例。
        public static let markdownH2 = SwiftUI.Font.body.weight(.bold)

        /// Markdown **正文**（原型 `.markdown{font-size:14px}`）⇒ `.subheadline`(15pt)。
        ///
        /// ⚠️ 与 `rowTitle` **同落在 `.subheadline`**，但不合并：原型里
        /// `.markdown{font-size:14px}` 与 `.file-row .fname{font-size:14.5px}` 是两处独立取值
        /// （沿 `codeSurface` 与 `background` 那条"同值不是同一个令牌"的判据）。
        /// 而名字也要说真话：`rowTitle` 是"行标题"，这里是"正文"，将来补深色 / 调字号时须能分别动。
        public static let markdownBody = SwiftUI.Font.subheadline

        /// **面包屑条**的文字（原型 `.crumb{font-size:12.5px}`）⇒ 系统 `.caption`(12pt)。
        ///
        /// ⚠️ 注意本文件里 `caption` 这个**令牌名**指的是 `.caption2`(11pt，原型 `t3` 那一档)，
        /// 所以这里不能复用 `Font.caption` —— 12.5px 落到的是系统 `.caption`(12pt)。
        /// 当前层那一段用 `.fontWeight(.semibold)` 叠在这上面（原型 `.crumb b{font-weight:600}`）。
        public static let breadcrumb = SwiftUI.Font.caption

        // MARK: 切片 7 新增（出处与理由见 TECH_SPEC §10.7）

        /// **对话头部标题**（原型 `styles/04-screens.css` 第 31 行的
        /// `.conv-head h2{font-size:17.5px;font-weight:720}`）⇒ `.body`(17pt) + bold。
        ///
        /// ⚠️ 与 `markdownH2`（`.body.weight(.bold)`）**今天同值，但不是一个令牌**：
        /// 原型里那两处是**两处独立取值**（`.markdown h2` 是 `17px/700`，
        /// 这里是 `17.5px/720`），恰好都落到系统 17pt + bold 而已。
        /// 名字也要说真话 —— 调 Markdown 的标题字号时，不该顺手改掉对话页的标题。
        /// 沿 `markdownBody` / `rowTitle`（`14px` 与 `14.5px` 同落 `.subheadline`）的先例。
        public static let conversationTitle = SwiftUI.Font.body.weight(.bold)

        /// **评论气泡的头部行**（原型 `.comment .bhead{font-size:12px}`）⇒ 系统 `.caption`(12pt)。
        ///
        /// ⚠️ 与 `breadcrumb` 同值（都落系统 `.caption`），但**不是一个令牌**：
        /// 原型里是两处独立取值（`.crumb` 是 `12.5px`、`.bhead` 是 `12px`），
        /// 沿 `markdownBody` / `rowTitle` 同一条先例。
        ///
        /// 这一个令牌管**整条头部行**：作者名在它之上叠 `.fontWeight(.bold)`
        /// （原型 `.bhead .author{font-weight:700}`），时间戳改用 `Font.caption`(11pt)
        /// （原型 `.t3{font-size:11.5px}`，与页面里所有次级时间同一档）。
        /// ⚠️ 别拿 `label`（12pt **semibold**）顶替：那会让整条头部行都变粗，
        /// 于是作者名的"更粗"就看不出来了 —— 而作者名是这一行里唯一要抢眼的。
        public static let commentMeta = SwiftUI.Font.caption
    }
}

/// 十六进制色值 → `Color`，**仅供 `GitDuoDesign` 内部的令牌定义使用**
/// （`Theme` 与 `LanguageColor` 都要用它，故不再是 `private`）。
///
/// ⚠️ 它**不是 `public`**：业务代码拿不到它，也就写不出内联色值 ——
///    这正是"颜色必须走语义令牌"（§10.7）在类型系统上的那道防线。
extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// **双列动态色**（TECH_SPEC §10.7 预留的那条路，2026-10-15 接通）：
/// 每个语义令牌给浅 / 深两列十六进制，运行时按系统的 trait collection 求值。
///
/// ## 为什么走 `UIColor`/`NSColor` 的 dynamic provider，而不是资产目录
///
/// - 两列色值**都留在本文件里**：review 时一眼看到一对值，`ThemeTests` 也能
///   直接读分量做对比度断言（资产目录方案要把 56 个色值搬进 `Contents.json`，
///   色值离开代码，断言就只能去读 JSON）。
/// - 视图层**零改动**：令牌名一个不变，`Theme.Palette.x` 依旧是一个 `Color`，
///   只是它不再是一个常量 —— SwiftUI 会在每次取色时按当前 scheme 求。
///
/// ## ⚠️ 深色列的唯一来源
///
/// 全部取自 **Primer primitives v8.2.0 `dist/docs/functional/themes/dark.json`**
/// （2026-10-15 实抓；这一版与浅色令牌的出处同期、成套自洽）。**不要凭记忆改深色值**
/// —— 语法四色与热力图五档是 GitHub 代码页 / 贡献日历的专属配色（不在 functional
/// tokens 里），出处见各自注释。深浅两列都写死在这份表里 ⇒ 调整必须成对出现。
extension Color {
    /// 不带透明度的双列色。
    init(light: UInt32, dark: UInt32) {
        self.init(light: light, lightAlpha: 1, dark: dark, darkAlpha: 1)
    }

    /// 带透明度的双列色（`toastSurface` / `codeInlineSurface` / `glassTint` 那三档）。
    ///
    /// ⚠️ 透明度也必须**进表**：深浅两档的底色与"透出多少"要一起调
    /// （例：玻璃 tint 浅 30% / 深 50%，§10.4 #4）—— 所以四个参数一次给全。
    init(light: UInt32, lightAlpha: Double, dark: UInt32, darkAlpha: Double) {
        #if canImport(UIKit)
        self.init(uiColor: dynamicUIColor(light: light, lightAlpha: lightAlpha,
                                          dark: dark, darkAlpha: darkAlpha))
        #elseif canImport(AppKit)
        self.init(nsColor: dynamicNSColor(light: light, lightAlpha: lightAlpha,
                                          dark: dark, darkAlpha: darkAlpha))
        #else
        // 兜底（当前 platforms 只有 iOS / macOS，理论上走不到）：退化为浅色静态值。
        self.init(
            .sRGB,
            red: Double((light >> 16) & 0xFF) / 255,
            green: Double((light >> 8) & 0xFF) / 255,
            blue: Double(light & 0xFF) / 255,
            opacity: lightAlpha
        )
        #endif
    }
}

#if canImport(UIKit)
/// 十六进制 → `UIColor`（供 dynamic provider 闭包用 —— 闭包必须返回 `UIColor`，
/// 不能直接构造 SwiftUI 的 `Color`，否则运行时拿到的是"已解析死"的静态色）。
private func uiColor(hex: UInt32, alpha: Double) -> UIColor {
    UIColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: CGFloat(alpha)
    )
}

/// 深浅双列 → 按 trait collection 现场求值的 `UIColor`。
private func dynamicUIColor(light: UInt32, lightAlpha: Double,
                            dark: UInt32, darkAlpha: Double) -> UIColor {
    UIColor { trait in
        let isDark = trait.userInterfaceStyle == .dark
        let hex = isDark ? dark : light
        let alpha = isDark ? darkAlpha : lightAlpha
        return uiColor(hex: hex, alpha: alpha)
    }
}
#endif

#if canImport(AppKit) && !canImport(UIKit)
private func nsColor(hex: UInt32, alpha: Double) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: CGFloat(alpha)
    )
}

private func dynamicNSColor(light: UInt32, lightAlpha: Double,
                            dark: UInt32, darkAlpha: Double) -> NSColor {
    // ⚠️ 实测（2026-10-15 探针，.workbuddy/probe-dynamic-color.swift）：这条 provider
    //    的 resolve 在**非主线程会死锁**（后台线程"resolving…"后不再返回；主线程毫秒级完成）。
    //    本 App 的 target 是 iOS（走 UIColor 那条，不受影响）；macOS 只是包级声明
    //    （swift test 跑 macOS 变体，测试已在 `ThemeTests` 标 `@MainActor` 绕开）。
    //    若哪天真的构建 macOS App：所有取色必须发生在主线程，否则渲染线程一碰就挂。
    NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return nsColor(hex: isDark ? dark : light,
                       alpha: isDark ? darkAlpha : lightAlpha)
    }
}
#endif
