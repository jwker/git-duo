import SwiftUI

/// 设计令牌 —— 颜色 / 字号 / 间距 / 圆角的**唯一定义处**。
///
/// 依据：TECH_SPEC §10.7。
/// 铁律：
/// 1. 业务代码**禁止写魔法值**（颜色、字号、间距、圆角一律引用本文件的令牌）。
/// 2. 令牌按**用途**命名，不按色相命名（禁 `gray600` / `blue500` 这类）。
/// 3. 色值**只在 `light` 一处定义**：本期只交付浅色；将来补深色时只需增加一份映射，不必逐页返工。
/// 4. ⚠️ Liquid Glass 深浅色的 tint 混合比例不同（浅 ≈30% / 深 ≈50%，§10.4 #4），
///    因此**玻璃着色值也必须走令牌**（`glassTint`），不得内联色值。
public enum Theme {

    // MARK: - 颜色（浅色为唯一实现，取值与原型 `redesign/prototype/styles/01-base.css` 的 `:root` 一致）

    public enum Palette {
        public static let background      = Color(hex: 0xF6F8FA)
        public static let surface         = Color(hex: 0xFFFFFF)
        public static let surfaceRaised   = Color(hex: 0xFFFFFF)
        public static let surfaceSunken   = Color(hex: 0xEFF2F5)
        public static let border          = Color(hex: 0xD0D7DE)
        public static let borderSoft      = Color(hex: 0xE8ECEF)

        public static let textPrimary     = Color(hex: 0x1F2328)
        public static let textSecondary   = Color(hex: 0x656D76)
        public static let textTertiary    = Color(hex: 0x8B949E)

        public static let accent          = Color(hex: 0x0969DA)   // 链接 / 强调
        public static let accentStrong    = Color(hex: 0x1F883D)   // 主按钮（GitHub 绿）
        public static let destructive     = Color(hex: 0xCF222E)   // 危险操作（删除 / 退出登录）

        /// 状态色沿用 GitHub 语义（PRD §1 / §10.7 一致口径）：
        /// 开放 = 绿 · 已合并 = 紫 · 已关闭 = 红 · 已发布 = 紫
        /// ⚠️ 已合并与已发布**有意同色**——它们同属"完成 / 发布"紫族，
        /// 靠**文案与图标**区分而非颜色（GitHub 网页端同样如此）。改色前先读 ThemeTests 的不变式。
        public static let stateOpen       = Color(hex: 0x1A7F37)   // 开放 = 绿
        public static let stateMerged     = Color(hex: 0x8250DF)   // 已合并 = 紫
        public static let stateReleased   = Color(hex: 0x8250DF)   // 已发布 = 紫（与 merged 同色，见上）
        public static let stateClosed     = Color(hex: 0xCF222E)   // 已关闭 / 未合并 = 红

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
        public static let stateOpenSurface   = Color(hex: 0xF0FFF4)   // `.pill.open` 底
        public static let stateOpenBorder    = Color(hex: 0xA4D8B0)   // `.pill.open` 边
        public static let stateMergedSurface = Color(hex: 0xFAF5FF)   // `.pill.merged` / `.pill.closed-i` 底
        public static let stateMergedBorder  = Color(hex: 0xD1BCF5)   // 同上，边
        public static let stateClosedSurface = Color(hex: 0xFFF1F2)   // `.pill.closed-p` 底
        public static let stateClosedBorder  = Color(hex: 0xF1B8BF)   // `.pill.closed-p` 边

        /// diff 行底色 / 文字色
        public static let diffAddedSurface   = Color(hex: 0xDAFBE1)
        public static let diffAddedText      = Color(hex: 0x116329)
        public static let diffDeletedSurface = Color(hex: 0xFFEBE9)
        public static let diffDeletedText    = Color(hex: 0xCF222E)

        /// **代码面**底色 —— 搜索结果「代码」范围的等宽预览行（原型
        /// `styles/01-base.css` 的 `--code-bg:#f6f8fa`，用于 `.sr-code`）。
        ///
        /// ⚠️ 它的值与 `background`（`#F6F8FA`）**今天完全相同**，但**不是同一个令牌**：
        /// 原型里本来就是两个独立变量（`--bg` 与 `--code-bg`），用途也不同 ——
        /// 一个是页面底，一个是"嵌在白色卡片里的一小块代码面"。将来补深色时两者未必同步变化
        /// （代码面通常要比页面底再深一档才分得出来），届时合并会逼着一起改。
        /// 沿 `repoAvatarSurface` 那条"接近但不是同一个值 ⇒ 两处独立取色"的先例。
        public static let codeSurface    = Color(hex: 0xF6F8FA)

        // MARK: 状态**图标**的配色（与上面那组"状态胶囊"的配色**不是**同一套值）

        /// 开放状态的**图标**绿 —— 原型 `styles/03-components.css` 的
        /// `.ic-open` / `.ic-pr{fill:#3fb950}`。
        ///
        /// ⚠️ 它与 `stateOpen`（`#1A7F37`，状态**胶囊**的绿；原型 `--open`）**不是同一个值**。
        /// 原型里这两套颜色是分开的，对应 GitHub 自家的做法：octicon 的图标色比标签色亮一档。
        /// 混用的后果不是"报错"，而是"图标与旁边那颗状态点颜色微妙地不一致"——
        /// 看起来像渲染坏了，而排查时很难想到是取错了 token。
        public static let stateOpenIcon     = Color(hex: 0x3FB950)

        /// 「完成」紫的**图标**色 —— 原型 `.ic-closed-i` / `.ic-merge{fill:#a371f7}`。
        ///
        /// 一个值覆盖三种状态（**已合并的 PR · 已发布的版本 · 已关闭的 Issue**）：
        /// 原型里这三处的图标色本来就相同，GitHub 也把它们归在同一族（"已完成"）。
        /// 所以它按**族**命名，不按单个状态命名 —— 按状态命名会让下一次"另一张卡也要用它"
        /// 时冒出一个同值不同名的新 token。
        /// ⚠️ 同样与状态胶囊的紫 `stateMerged`（`#8250DF`）不是同一个值。
        public static let stateCompletedIcon = Color(hex: 0xA371F7)

        // MARK: 切片 4 新增（出处与理由见 TECH_SPEC §10.7）

        /// **已 Star** 态的金色 —— 原型 `styles/04-screens.css` 的 `.stat-btn.starred svg{fill:#eac54f}`。
        ///
        /// ⚠️ 只用于**星形图标的填充 / 描边**，绝不用作文字色或背景色：
        /// 金色在白底上的对比度不足 2:1，承载正文必然读不清。
        /// 它与 `stateOpen`（开放 = 绿）毫无语义关系，别因为"都是好看的颜色"而合并。
        public static let starActive     = Color(hex: 0xEAC54F)

        /// 语言构成占比条里**「其他」段**的中性填充（原型 `scripts/10-explore-repo.js` 的 `#d1d5da`）。
        ///
        /// 它只表示"这里是若干语言的合计"，**不表示任何状态** ——
        /// 所以既不复用状态色，也不走 `LanguageColor`（那个表的每一项都对应一个真实语言）。
        public static let shareNeutral   = Color(hex: 0xD1D5DA)

        /// 筛选 chip 的**已选**底色（原型 `styles/03-components.css` 的 `.fchip.on{background:#f0f6ff}`）。
        ///
        /// 原型这处写的是一个内联色值而非变量，所以它此前没有名字。
        /// 它是"强调色的极浅底"——与 `accent`（`#0969DA`）成对使用：
        /// chip 选中时**底 + 边框 + 文字**三处都是强调色的不同浓淡。
        /// ⚠️ 不要拿 `surfaceSunken` 顶替：那是中性灰，会让"已选"看起来像"禁用"。
        public static let accentSurface  = Color(hex: 0xF0F6FF)

        // MARK: 轻提示（Toast）—— 原型 `styles/05-overlays.css` 的 `.toast`

        /// Toast 的深色底（原型 `rgba(28,32,36,.92)`）。
        ///
        /// ⚠️ 它**不是** `repoAvatarSurface`（`#24292F`）——两个值很接近但来源不同：
        /// 那个是图标块的实色底，这个是**带 8% 透明**的浮层底（要能透出一点下面的内容，
        /// 才不至于像一块贴上去的不透明补丁）。混用会让 Toast 显得比原型"实"。
        public static let toastSurface   = Color(hex: 0x1C2024).opacity(0.92)

        /// Toast 上的文字色。**一个不透明纯白** —— 它压在 `toastSurface` 上，
        /// 对比度约 15:1，远超 AA；但也正因如此它**只能**用在深底上（放白底上读不出来）。
        public static let toastText      = Color(hex: 0xFFFFFF)

        /// 仓库图标块的底色（原型 `.repo-avatar{background:#24292f}`，白色字形压在上面）。
        ///
        /// ⚠️ 它与 `textPrimary`（`#1F2328`）**接近但不是同一个值**，是两处独立取色：
        /// 一个是"正文最深的字"，一个是"图标块的底"。混用会在将来补深色时
        /// 把两者一起改掉，而它们并不该同步变化。
        public static let repoAvatarSurface = Color(hex: 0x24292F)

        /// 头像图片**取不到时**的兜底配色（原型 `scripts/10-explore-repo.js` 的 8 色）。
        ///
        /// 取色下标由登录名的稳定哈希决定 —— **不要用 `hashValue`**（Swift 的哈希每个进程随机化，
        /// 同一账号会在每次启动后换色，甚至在一次会话里因列表重绘而换色）。
        public static let avatarFallback: [Color] = [
            Color(hex: 0x1F883D), Color(hex: 0x8250DF), Color(hex: 0xD73A4A), Color(hex: 0xE16F24),
            Color(hex: 0x0075CA), Color(hex: 0xDB61A2), Color(hex: 0x5B3A8E), Color(hex: 0x0E8A16),
        ]

        /// 玻璃着色值（浅色约 30% 混合 —— §10.4 #4）
        public static let glassTint       = Color(hex: 0xFFFFFF).opacity(0.30)
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
