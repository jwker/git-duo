import SwiftUI

/// 菜单卡片 —— 「我的」页那两张卡片、设置页各分区的卡片（含末尾那张**无标题**的）、
/// 我的收藏页的收藏夹卡片（PRD §4.17 第 4/5 条、§4.19、§4.20）。
///
/// ```css
/// .menu-card{background:var(--card);border:1px solid var(--border-soft);
///            border-radius:14px;overflow:hidden;margin-bottom:12px}
/// ```
///
/// ## ⚠️ 它与 `CardBox` 是**同一个容器、两种内边距**
///
/// 两者都是「白底 + 1pt 浅边 + 14pt 圆角」——`.menu-card` 的 `border-radius:14px` 正是
/// `Theme.Radius.sheet`，`--card` / `--border-soft` 也分别是 `surface` / `borderSoft`。
/// **唯一的差别是 `.menu-card` 没有 `padding`**：它的留白由每一行自己出
/// （`.menu-item{padding:13px 14px}`）—— 否则每行之间会多出两份卡片内边距。
///
/// 所以本件就是 `CardBox(vertical: 0, horizontal: 0)`
/// —— **不是**另一个容器，是一个说清了"这一族卡片不带内边距"的名字。
/// 直接写 `CardBox(vertical: 0, horizontal: 0)` 也能出同样的画面，
/// 但那样下一次有人想调卡片内边距时，就会在 `CardBox` 的默认值上改到一个不该动的地方。
///
/// ## ⚠️ 行之间的分隔线由**行**画，不由卡片画
///
/// `.menu-item:last-child{border-bottom:none}` 是原型的规则（"除最后一个之外都画"）。
/// 卡片不知道自己在装几行（`@ViewBuilder` 收到的是一棵已经拼好的视图树），
/// 而调用方知道 ⇒ 由行的 `showsSeparator` 决定，**最后一行传 `false`**。
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

/// 菜单卡片里的一行 —— 图标 + 标题 +（可选）右侧值 +（可选）尖角 / 标签
/// （原型 `styles/04-screens.css` 的 `.menu-item`）。
///
/// ```css
/// .menu-item{display:flex;align-items:center;gap:12px;padding:13px 14px;
///            border-bottom:1px solid var(--border-soft);cursor:pointer;
///            font-size:14.5px;font-weight:550}
/// .menu-item:last-child{border-bottom:none}
/// .menu-item svg{width:19px;height:19px;stroke:var(--text2);fill:none;stroke-width:1.8}
/// .menu-item .chev{margin-left:auto;color:var(--text3)}
/// .ftag{font-size:10.5px;font-weight:700;color:var(--text3);background:var(--chip);
///       border-radius:6px;padding:2px 7px;letter-spacing:.3px}
/// ```
///
/// ## ⚠️ 它与 `LinkRow` **不是同一件**
///
/// | | `LinkRow`（`.file-row`） | 本件（`.menu-item`） |
/// |---|---|---|
/// | 内边距 | `11px 4px`（左右只留 4 —— 它长在已经带内边距的卡片里） | **`13px 14px`** |
/// | 图标 | 17pt / `--text3` | **19pt / `--text2`** |
/// | 副标题 | 有（`.fmsg`） | **没有** |
/// | 右侧 | 恒为一个尖角 | 值 / 标签 / 尖角 / 什么都没有 |
/// | 可点性 | 恒是按钮 | **可以不可点**（设置页有三行是纯展示） |
///
/// 四处都不同 ⇒ 不能合并。合并的代价不是"少一个文件"，而是**其中一处会悄悄偏离原型**
/// ——而偏离处看起来仍然像一行正常的菜单（同 `SheetRow` 与 `LinkRow` 的判例）。
///
/// ## ⚠️ `action` 可以为 `nil`（= 这一行不可点）
///
/// 设置页的「主题 / GitHub App · 账号 / 版本」三行在原型里**没有 `onclick`**：
/// 它们显示的是事实而不是入口。`nil` 时本件**根本不画成 `Button`**
/// —— 不是 `.disabled`（那会把它变灰、看起来像"暂时不可用"，同决策 **#51**），
/// 也不加读屏的按钮角色。
///
/// ⚠️ 另有一种"**眼下不给**"：设置页最底下的「退出登录」在**登出在途**时也传 `nil`
/// （决策 **#78**）—— 那时它右侧说的是 `正在退出…`，而把它变灰会看起来像"登出坏了"，
/// 其实它正在做。
///
/// ## ⚠️ `systemImage` 也可以为 `nil`（= 这一行没有图标）
///
/// **设置页那五个 `.menu-item` 在原型里一个图标都没有**
/// （`12-me.js:65/69/70/74/75`：`<div class="menu-item">主题<span…>浅色</span></div>`
/// —— 里面没有任何 `svg(...)`）。而「我的」页与收藏夹页那几行**都有**。
///
/// ⚠️ 本 App 的设置页现在是**六行**（原型那五行一条不多、一条不少，另加：
/// 「前往 GitHub 手动撤销授权」—— 偏差第 **40** 条；「退出登录」搬到末尾一张独立卡片 ——
/// 偏差第 **46** 条），**六行同样一个图标都不给**。
///
/// 所以图标是 Optional：给了才画，也没了那个固定宽度的图标槽
/// ⇒ 没有图标时标题从行首开始。若把它做成必填、设置页随便填一个图标，
/// 那五行的样子就与原型**不同了**，而"多了一个小图标"很难被认成缺陷。
///
/// ## ⚠️ 尖角取的是 `--text2`，**不是** `.chev` 写的 `--text3`
///
/// 原型的 `.menu-item .chev{color:var(--text3)}` 看着像是要给尖角一个更浅的灰，
/// 但 `.menu-item svg{stroke:var(--text2)}` 的选择器更具体（`.menu-item svg` =
/// 0-1-1，`.chev` = 0-1-0）⇒ 它设在 `<svg>` 元素上的 `stroke` 直接给了子路径，
/// `color` 那条根本用不上。**实测确认**：2026-10-09 用 Chrome 读 `.chev svg` 的
/// `getComputedStyle().stroke` 得到 `rgb(101,109,118)`（就是 `--text2`）。
/// 所以这里的前导图标与尖角**同色**。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct MenuRow: View {

    /// 标题的颜色档。
    ///
    /// ⚠️ 判据 **#43**：这是纯视觉枚举，不认识任何领域模型 ——
    /// 它**不叫** `.signOut` / `.deleteFolder`（与 `SheetRow.TitleTone` 同一条判据）。
    public enum TitleTone: Sendable, Hashable {

        /// 普通行（`textPrimary`）。
        case normal

        /// 破坏性动作（`Palette.destructive`）—— 设置页的「退出登录」。
        case destructive
    }

    /// 标题右侧那个附件。
    ///
    /// 原型里 `.menu-item` 的尾部**只有这三种**（值那一样是独立的 `value` 参数，
    /// 因为它常与后两者同时出现：收藏夹行是「3 项 + ›」、默认夹行是「45 项 + 默认」）。
    public enum Accessory: Sendable, Hashable {

        /// 什么都不画（设置页那些只显示值的行）。
        case none

        /// 一个尖角（`›`）—— "这一行能进去"的唯一视觉信号。
        case chevron

        /// 一枚小标签（`.ftag`）—— 只有内置「默认收藏夹」那一行用（PRD §4.19）。
        case tag(String)
    }

    /// SF Symbol 名；`nil` = 这一行没有图标（设置页那五行就是这样）。
    public let systemImage: String?

    public let title: String

    /// 标题与附件之间的灰字（`浅色` / `已授权` / `12.4 MB` / `3 项`）；`nil` = 不渲染。
    public let value: String?

    public let accessory: Accessory

    public let titleTone: TitleTone

    /// 底部分隔线。**最后一行传 `false`**（原型 `.menu-item:last-child{border-bottom:none}`）。
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
        title: String,
        value: String? = nil,
        accessory: Accessory = .none,
        titleTone: TitleTone = .normal,
        showsSeparator: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
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
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(Theme.Palette.borderSoft)
                    .frame(height: 1)
            }
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    // 原型 `.menu-item svg{width:19px;height:19px}`。
                    .font(.system(size: 19))
                    // …同一行的 `stroke:var(--text2)`。
                    .foregroundStyle(Theme.Palette.textSecondary)
                    // 固定宽度：原型的图标都是 19px 的方框，所以标题天然对齐；
                    // SF Symbols 的字形宽度各不相同（`star` 比 `bookmark` 窄），
                    // 不固定的话每一行的标题会各差一两个点 —— 单看一行完全看不出来。
                    .frame(width: 22)
            }

            // 原型 14.5px/550 ⇒ 最近的一档是 `rowTitle`（`.subheadline` 15）；
            // 与 `SheetRow` 把 14.5px 映到 `rowTitle` 同一条判据。
            Text(title)
                .font(Theme.Font.rowTitle)
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
            case let .tag(text):
                TagLabel(text: text)
            }
        }
        // 原型 `padding:13px 14px`（13 不在 4pt 阶里 ⇒ 写原值；14 同 `CardBox` 的横向内边距）。
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 整行可点（否则只有图标与文字那两小块响应点击）。
        .contentShape(Rectangle())
    }

    private var chevron: some View {
        // ⚠️ 颜色见类型说明：与图标**同色**（`--text2`），不是 `.chev` 里写的 `--text3`。
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.Palette.textSecondary)
    }
}

// MARK: - 默认收藏夹那一枚小标签

/// 原型 `.ftag`（只有「我的收藏」页的默认夹那一行用）。
///
/// ⚠️ **字号与字重各差一点点**：原型是 `10.5px/700`，本仓最近的一档是
/// `Theme.Font.tag`（`.caption2` 11 + semibold 600）。差 0.5pt 与一档字重，
/// 换来的是一条既有令牌而不是一个新的魔法字号 —— 与 `SectionHeader` 那条
/// "6 不在 4pt 阶里就写原值"不同：那是**间距**（没有语义档位），
/// 而这里**有**一档现成的"小标签"令牌，再造一个只会多一个将来要同步的东西。
private struct TagLabel: View {

    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Font.tag)
            .foregroundStyle(Theme.Palette.textTertiary)
            // 原型 `letter-spacing:.3px`。
            .tracking(0.3)
            // 原型 `padding:2px 7px`（2 是 `Spacing.xxs`；7 不在阶里 ⇒ 写原值）。
            .padding(.vertical, Theme.Spacing.xxs)
            .padding(.horizontal, 7)
            // 原型 `background:var(--chip)` = `#eff2f5` = `surfaceSunken`。
            .background(Theme.Palette.surfaceSunken)
            // 原型 `border-radius:6px` = `Radius.chip`。
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            // ① 「我的」页第一张卡：四行都有图标与尖角，最后一行的分隔线要关掉
            //（PR 与 Issue 两行取 `StateIcon` 那两个常量，见 `GitHubIcon` 尾巴上的说明）
            SectionHeader(title: "菜单卡片一")
            MenuCard {
                MenuRow(systemImage: GitHubIcon.star, title: "Star 管理", accessory: .chevron, action: {})
                MenuRow(systemImage: GitHubIcon.bookmark, title: "我的收藏", accessory: .chevron, action: {})
                MenuRow(systemImage: StateIcon.pullRequestOpen, title: "我的 Pull Request",
                        accessory: .chevron, action: {})
                MenuRow(systemImage: StateIcon.issueOpen, title: "我的 Issue",
                        accessory: .chevron, showsSeparator: false, action: {})
            }

            // ② 设置页「外观 / 账户 / 关于」+ 末尾一张**无标题卡片**：六行一个图标都没有
            //   （原型那五行就是这样，另两处见偏差第 40 / 46 条），
            //   三行只显示值、两行可点、一行不可点
            SectionHeader(title: "外观")
            MenuCard {
                MenuRow(title: "主题", value: "浅色")
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
            // 末尾那张**无标题**卡片：分区标题那 16pt 上边距它没有 ⇒ 自己补，否则会
            // 贴着「关于」那张、看着像多出来的一行（偏差第 46 条）。
            // 登出在途时右侧的值会变成 `正在退出…`。
            MenuCard {
                MenuRow(title: "退出登录", titleTone: .destructive, showsSeparator: false, action: {})
            }
            .padding(.top, Theme.Spacing.l)

            // ③ 我的收藏页：自建夹「值 + 尖角」，默认夹「值 + 标签」且**不可点**
            SectionHeader(title: "我的收藏")
            MenuCard {
                MenuRow(systemImage: GitHubIcon.bookmark, title: "默认收藏夹", value: "45 项",
                        accessory: .tag("默认"))
                MenuRow(systemImage: GitHubIcon.bookmark, title: "前端好项目", value: "2 项",
                        accessory: .chevron, action: {})
                MenuRow(systemImage: GitHubIcon.bookmark, title: "Swift 学习", value: "5 项",
                        accessory: .chevron, showsSeparator: false, action: {})
            }
        }
        .padding(Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
