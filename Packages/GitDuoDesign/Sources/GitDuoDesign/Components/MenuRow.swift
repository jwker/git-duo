import SwiftUI

/// 菜单组里的一行 —— **40pt 图标色块** + 标题 +（可选）右侧值 +（可选）尖角
/// （原型 `styles/04-screens.css` 的 `.menu-item`，2026-10-15 方案 D 重穿）。
///
/// ```css
/// .menu-item{display:flex;align-items:center;gap:12px;padding:14px;
///            font-size:15px;font-weight:600;position:relative}
/// .menu-item>svg{width:40px;height:40px;padding:10px;border-radius:12px;
///                background:var(--ic,var(--slate));color:#fff;stroke:#fff}
/// ```
///
/// ## ⚠️ 2026-10-16 起**只画内容** —— 但仅限坐在 `List` 行里时
///
/// 坐在 `List` 的行里：`List` 已经给了内边距、分隔线、卡面、圆角，
/// 本件**不**再自己画 ⇒ 调用方**必须显式传 `showsSeparator: false`**
/// （缺省是 `true`，不传就会与本行的系统分隔线叠成**双线**）。
///
/// 坐在 `CardBox` 这类自绘容器里：容器只给白面圆角与内边距，**不**知道里面有几行、
/// 谁是首行 ⇒ 分隔线仍由本件自己画，调用方要传 `showsSeparator: index > 0`
/// 或 `index < count - 1`（取决于线画在哪一头；本件的画法见下面）。
///
/// | 从前自己画 | 现在谁给 |
/// |---|---|
/// | `.padding(14)` | `List` 行内边距（`contentPadding` 传 0）；**卡内场景传 `contentPadding: 14`** |
/// | 内嵌 hairline（`showsSeparator`） | `List` 分隔线 **或** 本件自画（非 List 时） |
/// | 白面 + 圆角 18 | `.listRowBackground` **或** `CardBox` |
///
/// ⚠️ 因此 `showsSeparator` **又加回来了**：非 List 场景（目前只剩仓库首页四行入口）
/// 需要它，同时那一处要传 `contentPadding: 14`。坐在 `List` 里的调用方两者都用默认值即可。
///
/// ⚠️ `accessory: .chevron` **保留**：这一族行是**导航 / 开菜单**的行，尖角是
/// "这一行能进去"的信号（形状即信号，走查第 66 条）。它不是 `NavigationLink` 那枚
/// 系统箭头（那一枚随"能不能推入"变化，本件画的是自己的）。
///
/// ## ⚠️ 方案 D：图标是「40pt 实底色块 + 白字形」
///
/// 行上唯一有分量的元素就是这块色。字形的白由 `foregroundStyle` 给（SF Symbol 整体白色）。
///
/// ⚠️ **2026-10-17 新口径：色块一律中性灰**，不再按类别着色（原"颜色编码"那套与
/// 统一成橙的主色打架）。`IconTone` 的档位保留在 API 上是为了让调用点继续表达
/// "这一行是什么类别"，但今天五档画出的是同一个灰 —— 见 `tileColor`。
///
/// ## ⚠️ 它与 `LinkRow` **不是同一件**
///
/// | | `LinkRow`（`.file-row`） | 本件（`.menu-item`） |
/// |---|---|---|
/// | 图标 | 17pt 线稿（随 `iconTint`） | **40pt 实底色块 + 白字形** |
/// | 副标题 | 有（`.fmsg`） | **没有** |
/// | 右侧 | 恒为一个尖角 | 值 / 尖角 / 什么都没有 |
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
    ///
    /// ⚠️ **2026-10-17 新口径：五档今天画的是同一个中性灰。**
    /// 主色统一为橙后，"每个入口一个颜色"那套彩虹编码与主色打架，故取消。
    /// 档位**不删**：调用点仍按类别传（`.green` = Issues、`.blue` = PR …），
    /// 这一层信息留着 —— 将来要恢复"按类别着色"时是现成的接线，
    /// 而**恢复的第一步就是给 `tileColor` 的对应档换回令牌**。
    public enum IconTone: Sendable, Hashable {

        /// 中性灰 —— 代码 / 设置这类"没有专属色"的行，也是**缺省档**，且是今天**唯一的实际取值**。
        case slate

        /// 金（原 Star 那一档）。
        case gold

        /// 绿（原 Issues 那一档）。
        case green

        /// 链接蓝（原 Pull Requests / 收藏那一档）。
        case blue

        /// 紫（原 Commits 那一档）。
        case purple

        /// 色档 → 色块底色。⚠️ 非 `private`：单测要能钉住"哪一档取的是哪个令牌"。
        ///
        /// ⚠️ 五档今天同值（见类型说明）—— 这里写成五路同归而不是把参数删掉，
        /// 是为了让"档位还在、颜色没了"这件事**在唯一一处显形**。
        public var tileColor: Color {
            switch self {
            case .slate, .gold, .green, .blue, .purple: Theme.Palette.iconTileSlate
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

    /// 画不画分隔线。默认 `true`。
    ///
    /// - 在 `List` 行里：**传 `false`**，分隔线由系统给。
    /// - 在 `CardBox` 这类自绘容器里：**按"首行不画"的口径传 `index > 0`**，
    ///   本件在**顶部**画一条 hairline（对齐标题文字，右缘贴卡边；容器 clip 到圆角内）。
    public let showsSeparator: Bool

    /// 行内容四向内边距。
    ///
    /// - 坐在 `List` 行里：**默认 `0`** —— 内边距由系统行给（吃系统的 18pt 档）。
    /// - 坐在 `CardBox(vertical: 0, horizontal: 0)` 这类"行容器"里：**传 `14`**
    ///   （原型 `.menu-item{padding:14px}`），留白由行自己出。
    public let contentPadding: CGFloat

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
        contentPadding: CGFloat = 0,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.iconTone = iconTone
        self.title = title
        self.value = value
        self.accessory = accessory
        self.titleTone = titleTone
        self.showsSeparator = showsSeparator
        self.contentPadding = contentPadding
        self.action = action
    }

    public var body: some View {
        Group {
            if let action {
                // ⚠️ `.plain`：本件的 label **就是这一行的全部内容** ——
                //    套系统按钮样式会得到一个"里面装着内容的按钮"（P2 那条判据）。
                Button(action: action) { row }
                    .buttonStyle(.plain)
            } else {
                // 不可点的那一行：结构逐字相同，只是外面没有 Button。
                row
            }
        }
        // 分隔线挂在**最外层**（含 contentPadding）：卡内场景右缘贴卡边，
        // 左缘对齐标题文字（内边距 + 40pt 色块 + 12 gap；无图标的行也按此缩进）。
        // List 场景调用方传 `showsSeparator: false`，这里什么都不画。
        .overlay(alignment: .topLeading) {
            if showsSeparator {
                Rectangle()
                    .fill(Theme.Palette.borderSoft)
                    .frame(height: 1)
                    .padding(.leading, contentPadding + 52)
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
        // 卡内场景由本件自己给 14 内边距；List 场景传 0（系统行给）。
        .padding(contentPadding)
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
    // ⚠️ 每一行都显式 `showsSeparator: false` —— 它们在 `List` 里，分隔线由系统画；
    //    本件再画一条就是双线（见类型说明：List 场景必须显式传 false）。
    List {
        // ① 「我的」页第一组：三行都有色块与尖角（PR 与 Issue 两行取 `StateIcon`
        //    那两个常量，见 `GitHubIcon` 尾巴上的说明）
        Section {
            // 原型逐字「Star 管理」；2026-10-15 起改「我的 Star」（走查第 71 条，
            // 设计包拿不到 `ProfileCopy`，预览写字面量 —— 改文案记得这里跟着改）。
            MenuRow(systemImage: GitHubIcon.star, iconTone: .gold,
                    title: "我的 Star", accessory: .chevron, showsSeparator: false, action: {})
            MenuRow(systemImage: StateIcon.pullRequestOpen, iconTone: .blue,
                    title: "我的 Pull Request", accessory: .chevron, showsSeparator: false, action: {})
            MenuRow(systemImage: StateIcon.issueOpen, iconTone: .green,
                    title: "我的 Issue", accessory: .chevron, showsSeparator: false, action: {})
        }

        // ② 设置页「外观 / 账户 / 关于」+ 末尾一张**无标题**组：六行一个图标都没有
        //   （原型那五行就是这样，另两处见偏差第 40 / 46 条）。
        Section("外观") {
            Menu {
                Picker("主题", selection: .constant("system")) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
            } label: {
                MenuRow(title: "主题", value: "浅色", accessory: .chevron, showsSeparator: false)
            }
        }
        Section("账户") {
            MenuRow(title: "GitHub App · jiangjiang", value: "已授权", showsSeparator: false)
            MenuRow(title: "前往 GitHub 手动撤销授权", showsSeparator: false, action: {})
        }
        Section("关于") {
            MenuRow(title: "清除缓存", value: "12.4 MB", showsSeparator: false, action: {})
            MenuRow(title: "版本", value: "2.0 (1)", showsSeparator: false)
        }
        // 末尾那张**无标题**组：登出在途时右侧的值会变成 `正在退出…`。
        Section {
            MenuRow(title: "退出登录", titleTone: .destructive, showsSeparator: false, action: {})
        }
    }
    // ⚠️ **不写 `.listStyle(.insetGrouped)`** —— 它是 iOS-only，而 `swift test`
    //    编译的是本包的 **macOS 变体**（那一次编译不认这个符号，整个包都编不过）。
    //    预览只是为了看行内容，用默认样式即可。
    .scrollContentBackground(.hidden)
    .background(Theme.Palette.background)
}
