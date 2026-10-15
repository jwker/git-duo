import SwiftUI

/// 菜单组 —— 「我的」页那两组、设置页各分区（含末尾那张**无标题**的）
/// （PRD §4.17 第 4/5 条、§4.20）。
///
/// ```css
/// /* 2026-10-15 方案 D 起（走查第 73 条）—— 组不再画卡，行直接铺在页面上 */
/// .menu-card{background:none;border:none;border-radius:0;margin:0 0 10px}
/// ```
///
/// ## ⚠️ 方案 D：它退化成了"一组行的编组名"
///
/// 白底 + 边框 + 圆角全没了 —— 行与行之间是**内嵌 hairline**（由 `MenuRow` 画），
/// 组与组之间靠 `SectionHeader` 的 22pt 上边距分开。保留这个类型是因为
/// "这几行是一组"这件事仍要一个名字（同 `CardBox` 去形后留名的理由）。
///
/// ## ⚠️ 它与 `CardBox` 的关系
///
/// 本件仍是 `CardBox(vertical: 0, horizontal: 0)` —— 去形后的 `CardBox` 也什么都不画，
/// 两者在"容器"这层已经没有差别；保留一层包装是为了语义（"一组菜单行"）。
///
/// ## 行之间的内嵌 hairline 由**行**画
///
/// 卡片不知道自己在装几行 ⇒ 由行的 `showsSeparator` 决定，**最后一行传 `false`**。
/// 沿 `LinkRow` 的同一条处置（那里也是调用方传）。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct MenuCard<Content: View>: View {

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        // `CardBox` 内部已经是一个 `spacing: 0` 的 `VStack(alignment: .leading)`，
        // 所以多行会紧贴在一起 —— 那正是 `.menu-item` 之间不要间隙的意思。
        CardBox(vertical: 0, horizontal: 0) {
            content
        }
    }
}

/// 菜单组里的一行 —— **40pt 图标色块** + 标题 +（可选）右侧值 +（可选）尖角
/// （原型 `styles/04-screens.css` 的 `.menu-item`，2026-10-15 方案 D 重穿）。
///
/// ```css
/// .menu-item{display:flex;align-items:center;gap:12px;padding:12px 2px;
///            font-size:15px;font-weight:600;position:relative}
/// .menu-item+.menu-item::before{content:"";position:absolute;top:0;left:54px;right:0;
///                               height:1px;background:var(--border-soft)}
/// .menu-item>svg{width:40px;height:40px;padding:10px;border-radius:12px;
///                background:var(--ic,var(--slate));color:#fff;stroke:#fff}
/// ```
///
/// ## ⚠️ 方案 D：图标从「19pt 灰线稿」升级为「40pt 实底色块 + 白字形」
///
/// 卡片去形后，行上唯一有分量的元素就是这块色 —— 它同时是"这一行是什么类别"的
/// 颜色编码（`IconTone`）。字形的白由 `foregroundStyle` 给（SF Symbol 整体白色）。
///
/// ## ⚠️ 分隔线**内嵌缩进 54**，由行画在**顶上**
///
/// `54 = 色块 40 + gap 12 + 行缩进 2`（ hairline 从文字起点起，不再通栏）。
/// ⚠️ 原型的选择器是 `.menu-item+.menu-item::before{left:54px}` —— **固定 54**，
/// 没有图标的行（设置页那些）也一样缩进 54（文字从 2 起）—— 这是原型的写法，
/// 照做；哪天要改成"无图标行缩到文字"，改原型与这里两处。
/// 最后一行不画（调用方传 `showsSeparator: false`）。
///
/// ## ⚠️ 它与 `LinkRow` **不是同一件**
///
/// | | `LinkRow`（`.file-row`） | 本件（`.menu-item`） |
/// |---|---|---|
/// | 图标 | 17pt 线稿（随 `iconTint`） | **40pt 实底色块 + 白字形** |
/// | 副标题 | 有（`.fmsg`） | **没有** |
/// | 右侧 | 恒为一个尖角 | 值 / 标签 / 尖角 / 什么都没有 |
/// | 可点性 | 恒是按钮 | **可以不可点**（设置页有三行是纯展示） |
///
/// ## ⚠️ `action` 可以为 `nil`（= 这一行不可点）
///
/// 设置页的「GitHub App · 账号 / 版本」两行在原型里**没有 `onclick`**：
/// 它们显示的是事实而不是入口。`nil` 时本件**根本不画成 `Button`**
/// —— 不是 `.disabled`（那会把它变灰、看起来像"暂时不可用"，同决策 **#51**），
/// 也不加读屏的按钮角色。
///
/// ⚠️ 「主题」行**曾是**这个名单里的第三个（"本期仅浅色"），2026-10-15 起它是
/// 三档切换器（走查第 **69** 条）—— 调用方用 `Menu` 包着本件，`action` 仍传 `nil`
/// （点击由 `Menu` 接管，本件只负责"长什么样"）。
///
/// ⚠️ 另有一种"**眼下不给**"：设置页最底下的「退出登录」在**登出在途**时也传 `nil`
/// （决策 **#78**）—— 那时它右侧说的是 `正在退出…`，而把它变灰会看起来像"登出坏了"，
/// 其实它正在做。
///
/// ## ⚠️ `systemImage` 也可以为 `nil`（= 这一行没有图标）
///
/// **设置页那几个 `.menu-item` 在原型里一个图标都没有**（`12-me.js:65/69/70/74/75`），
/// 而「我的」页与仓库首页四行入口**都有**。给了才画色块，也没了那个色块槽
/// ⇒ 没有图标时标题从行首开始。
///
/// ## ⚠️ 尖角取的是 `--text2`，**不是** `.chev` 写的 `--text3`
///
/// 原型的 `.menu-item .chev{color:var(--text3)}` 看着像是要给尖角一个更浅的灰，
/// 但 `.menu-item svg{stroke:var(--text2)}` 的选择器更具体 ⇒ 尖角实际是 `--text2`。
/// **实测确认**（2026-10-09 Chrome 读 `getComputedStyle().stroke`）。
/// 方案 D 后 `stroke:#fff` 只作用于**色块内的字形**，尖角在色块外、仍是 `--text2`。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct MenuRow: View {

    /// 图标色块的色档（方案 D 新增，见类型说明）。
    ///
    /// ⚠️ 判据 **#43**：纯视觉枚举，不认识任何领域模型。
    /// 色值全部落在 `Theme.Palette` 的既有/新增令牌上（见 `tileColor`）。
    public enum IconTone: Sendable, Hashable {

        /// 中性灰（原型 `--slate`）—— 代码 / 设置这类"没有专属色"的行，也是**缺省档**。
        case slate

        /// 金（原型 `--gold`）—— Star。
        case gold

        /// 绿（原型 `--green` = `accentStrong`）—— Issues。
        case green

        /// 链接蓝（原型 `--link` = `accent`）—— Pull Requests / 收藏。
        case blue

        /// 紫（原型 `--merge` = `stateMerged`）—— Commits。
        case purple

        /// 色档 → 色块底色。⚠️ 非 `private`：单测要能钉住"哪一档取的是哪个令牌"。
        public var tileColor: Color {
            switch self {
            case .slate: Theme.Palette.iconTileSlate
            case .gold: Theme.Palette.iconTileGold
            case .green: Theme.Palette.accentStrong
            case .blue: Theme.Palette.accent
            case .purple: Theme.Palette.stateMerged
            }
        }
    }

    /// 标题的颜色档。
    ///
    /// ⚠️ 判据 **#43**：这是纯视觉枚举，不认识任何领域模型 ——
    /// 它**不叫** `.signOut`（与 `SheetRow.TitleTone` 同一条判据）。
    public enum TitleTone: Sendable, Hashable {

        /// 普通行（`textPrimary`）。
        case normal

        /// 破坏性动作（`Palette.destructive`）—— 设置页的「退出登录」。
        case destructive
    }

    /// 标题右侧那个附件。
    ///
    /// 原型里 `.menu-item` 的尾部**只有这两种**（值那一样是独立的 `value` 参数，
    /// 因为它常与尖角同时出现）。
    public enum Accessory: Sendable, Hashable {

        /// 什么都不画（设置页那些只显示值的行）。
        case none

        /// 一个尖角（`›`）—— "这一行能进去"的唯一视觉信号。
        case chevron
    }

    /// SF Symbol 名；`nil` = 这一行没有图标（设置页那几行就是这样）。
    public let systemImage: String?

    /// 图标色块的色档（见 `IconTone`）。没有图标的行不消费它。
    public let iconTone: IconTone

    public let title: String

    /// 标题与附件之间的灰字（`浅色` / `已授权` / `12.4 MB` / `3 项`）；`nil` = 不渲染。
    public let value: String?

    public let accessory: Accessory

    public let titleTone: TitleTone

    /// 顶部内嵌 hairline。**最后一行传 `false`**（原型 `.menu-item+.menu-item`）。
    public let showsSeparator: Bool

    private let action: (() -> Void)?

    /// 这一行能不能点。⚠️ 非 `private`：单测要能钉住"设置页那三行不是按钮"。
    public var isTappable: Bool { action != nil }

    /// 标题色。⚠️ 非 `private`：单测要能钉住"哪一档取的是哪个令牌"。
    var titleColor: Color {
        switch titleTone {
        case .normal: Theme.Palette.textPrimary
        case .destructive: Theme.Palette.destructive
        }
    }

    public init(
        systemImage: String? = nil,
        iconTone: IconTone = .slate,
        title: String,
        value: String? = nil,
        accessory: Accessory = .none,
        titleTone: TitleTone = .normal,
        showsSeparator: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.iconTone = iconTone
        self.title = title
        self.value = value
        self.accessory = accessory
        self.titleTone = titleTone
        self.showsSeparator = showsSeparator
        self.action = action
    }

    public var body: some View {
        Group {
            if let action {
                Button(action: action) { row }
                    .buttonStyle(.plain)
            } else {
                // 不可点的那一行：结构逐字相同，只是外面没有 Button。
                row
            }
        }
        .overlay(alignment: .topLeading) {
            if showsSeparator {
                Rectangle()
                    .fill(Theme.Palette.borderSoft)
                    .frame(height: 1)
                    // 原型 `left:54px`（色块 40 + gap 12 + 缩进 2）—— 固定值，
                    // 没有图标的行也一样（见类型说明）。
                    .padding(.leading, 54)
            }
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    // 色块内的字形 20pt（原型 40 块垫 10 内边距）。
                    .font(.system(size: 20))
                    // 白字形（原型 `color:#fff;stroke:#fff`）。
                    .foregroundStyle(.white)
                    // 40pt 实底圆角块（原型 `border-radius:12px` = `container`）。
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                            .fill(iconTone.tileColor)
                    )
            }

            // 原型 15px/600 ⇒ `rowTitle`（15pt）+ semibold（方案 D 从 14.5/550 提上来）。
            Text(title)
                .font(Theme.Font.rowTitle.weight(.semibold))
                .foregroundStyle(titleColor)
                .lineLimit(1)

            Spacer(minLength: Theme.Spacing.m)

            if let value {
                // 原型 `.t3{font-size:11.5px;color:var(--text3)}` ⇒ `caption` + `textTertiary`。
                Text(value)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }

            switch accessory {
            case .none:
                EmptyView()
            case .chevron:
                chevron
            }
        }
        // 原型 `padding:12px 2px`（方案 D 从 13/14 改 —— 行直接坐在页面上）。
        .padding(.vertical, 12)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 整行可点（否则只有色块与文字那两小块响应点击）。
        .contentShape(Rectangle())
    }

    private var chevron: some View {
        // ⚠️ 颜色见类型说明：与旧线稿图标同源（`--text2`），不是 `.chev` 里写的 `--text3`。
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.Palette.textSecondary)
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            // ① 「我的」页第一组：三行都有色块与尖角，最后一行的分隔线要关掉
            //（PR 与 Issue 两行取 `StateIcon` 那两个常量，见 `GitHubIcon` 尾巴上的说明）
            SectionHeader(title: "菜单组一")
            MenuCard {
                // 原型逐字「Star 管理」；2026-10-15 起改「我的 Star」（走查第 71 条，
                // 设计包拿不到 `ProfileCopy`，预览写字面量 —— 改文案记得这里跟着改）。
                MenuRow(systemImage: GitHubIcon.star, iconTone: .gold,
                        title: "我的 Star", accessory: .chevron, action: {})
                MenuRow(systemImage: StateIcon.pullRequestOpen, iconTone: .blue,
                        title: "我的 Pull Request", accessory: .chevron, action: {})
                MenuRow(systemImage: StateIcon.issueOpen, iconTone: .green,
                        title: "我的 Issue", showsSeparator: false, action: {})
            }

            // ② 设置页「外观 / 账户 / 关于」+ 末尾一张**无标题**组：六行一个图标都没有
            //   （原型那五行就是这样，另两处见偏差第 40 / 46 条）。
            //   分隔线仍固定缩进 54（原型 CSS 如此，见类型说明）。
            SectionHeader(title: "外观")
            MenuCard {
                Menu {
                    Picker("主题", selection: .constant("system")) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                } label: {
                    MenuRow(title: "主题", value: "浅色", accessory: .chevron,
                            showsSeparator: false)
                }
            }
            SectionHeader(title: "账户")
            MenuCard {
                MenuRow(title: "GitHub App · jiangjiang", value: "已授权")
                MenuRow(title: "前往 GitHub 手动撤销授权", showsSeparator: false, action: {})
            }
            SectionHeader(title: "关于")
            MenuCard {
                MenuRow(title: "清除缓存", value: "12.4 MB", action: {})
                MenuRow(title: "版本", value: "2.0 (1)", showsSeparator: false)
            }
            // 末尾那张**无标题**组：分区标题那 22pt 上边距它没有 ⇒ 自己补，否则会
            // 贴着「关于」那张、看着像多出来的一行（偏差第 46 条）。
            // 登出在途时右侧的值会变成 `正在退出…`。
            MenuCard {
                MenuRow(title: "退出登录", titleTone: .destructive, showsSeparator: false, action: {})
            }
            .padding(.top, Theme.Spacing.l)
        }
        .padding(Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
