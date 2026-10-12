import Foundation

/// 通用图标的 SF Symbol 名（原型 `scripts/02-icons.js` 的 `I.*`）。
///
/// ## 为什么不各写各的
///
/// 同一个图标在页面上常出现两次（分支胶囊、分支行、面包屑里的分支…），
/// 名字各写一遍就会出现"同一件事两个图标"——例如一处 `arrow.triangle.branch`、
/// 另一处凭印象写成 `arrow.branch`（**这个符号不存在**）。
///
/// ## ⚠️ 与 `StateIcon` 同一条告诫：名字写错**不会**在任何环节报错
///
/// SF Symbols 里没有的名字，编译期与测试期都发现不了
/// （SwiftPM 测试跑在 macOS 上，拿不到 `UIImage(systemName:)`），
/// 界面上表现为**图标凭空消失** —— 那片空白没有任何提示。
/// **改这个文件里的任何一个名字，都要跑一次模拟器或真机看一眼。**
///
/// 状态图标（Issue / PR 的开放·已合并·已关闭）不在本表，见 `StateIcon`。
public enum GitHubIcon {

    /// **分支** —— 原型 `I.fork`（两个圆点在上、一个在下，中间连线）。
    ///
    /// ⚠️ **有意偏差（已登记）**：SF Symbols 里**没有**与原型同形的符号
    /// （原型画的是 GitHub 的 fork 形状；`arrow.triangle.branch` 是标准的 git-branch 形状）。
    /// 取语义最近的一个，而不是自绘一个 `Path` ——
    /// 自绘等于在代码里维护一份图标资源，而它没有设计稿可依。
    /// 与 `StateIcon.pullRequestOpen`（`arrow.triangle.pull`）**不是同一个符号**：
    /// 那是"提 PR"，这里是"分支"。
    public static let branch = "arrow.triangle.branch"

    // MARK: - 文件树（切片 6.4）

    /// 目录行 —— 原型 `I.dir`。
    public static let folder = "folder"

    /// 文件行 —— 原型 `I.file`。
    ///
    /// ⚠️ **2026-10-12 起它还被文件查看页那颗「⋯」菜单的第二项（`复制文件名`）复用**：
    /// 那里要的正是"这是一个文件"这个语义，而**新加一个没验过的字形**风险更大
    /// —— 本文件抬头那条"名字写错只会在界面上凭空消失"正为此而写。
    /// 复用的是**字形**，不是"文件树行"这个意思；两处颜色/尺寸各由调用方给。
    public static let file = "doc.text"

    /// 列表行右侧的指示符 —— 原型 `I.chev`。
    public static let chevron = "chevron.right"

    // ⚠️ **2026-10-11 删掉了 `plus`**（它原本是面包屑右侧那颗「＋ 添加」的图标）。
    //    原型用 `I.plus` 配全角 `＋` 文案 —— **两者都在**，照搬过来就是两个加号并排。
    //    用户报回「有两个加号」后，保留**文案里**那一个（与「添加」二字同字体、同字号），
    //    那颗独立图标连同本令牌一并删除 ⇒ 全仓再无引用。
    //    见 `REVIEW-CHECKLIST` 第 52 条。

    // ⚠️ **2026-10-11 删掉了 `fork`**（它原本是仓库头部 `StatButton` / 卡片 fork 计数的图标）。
    //    SF Symbols 里没有「两个上圆点 + 一个下圆点 + 实线」的 fork 字形：
    //    `point.3.connected.trianglepath.dotted` 的连线是虚点，与用户给的参考图相差太多。
    //    改由设计包自绘 `ForkIcon.swift` 统一处理这几处。
    //    见 `REVIEW-CHECKLIST` 第 54 条。

    // MARK: - 文件查看页的空态（切片 6.4）

    /// 「无法预览」空态。
    ///
    /// ⚠️ 原型没有这个状态（它没有服务端，也就没有二进制文件）。
    /// 取 `doc.questionmark`：一个"这份文档有问题"的语义，
    /// 比通用警告三角更贴（这既不是错误、也不是警告，只是**看不了**）。
    public static let unsupportedFile = "doc.questionmark"

    // MARK: - 弹层动作行图标（切片 8.3）

    /// 「重命名」动作行 —— 原型 `I.pencil`（`11-favorites.js:93` 收藏夹操作菜单）。
    ///
    /// 切片 8 的 §5.16 重命名文件弹层也用它（同一件事：改一个路径）。
    public static let pencil = "pencil"

    /// 「删除」动作行 —— 原型 `I.trash`（`11-favorites.js:94` 收藏夹操作菜单）。
    ///
    /// 切片 8 的 §5.15 `删除文件`（PRD 明写**危险色**）与 §5.17 删除确认共用它。
    public static let trash = "trash"

    // MARK: - 复制路径 / 溢出菜单（2026-10-12 新增）

    /// **复制路径** —— 仓库页面包屑那颗「⋯」菜单的第一项，以及文件查看页
    /// `crumb` 行那颗「⋯」菜单的第一项。
    ///
    /// ⚠️ **原型里没有这个控件**（`REVIEW-CHECKLIST` 第 56 条：按用户要求新增，
    /// 不是实现走样）⇒ 这个字形也**不是**从 `scripts/02-icons.js` 的 `I.*` 来的，
    /// 取 SF Symbols 里语义最直白的一支（两个叠起来的文档）。
    ///
    /// ⚠️ 它与 `StateIcon` 无关，也不是"复制原文"那颗 `Raw` 按钮的图标 ——
    /// `Raw` 是**纯文字**（原型 `<button>` 里没有 `svg(...)`，见下面那条注释）。
    public static let copy = "doc.on.doc"

    /// **溢出菜单**（「⋯」）—— 两处 `crumb` 行右端的那个动作位（§4.4 代码分区、
    /// §4.5 文件查看）。**同一个形状、两张不同的菜单**（那边是 复制路径 / 添加文件，
    /// 这边是 复制路径 / 复制文件名）。
    ///
    /// ⚠️ 与 `copy` 同属"按用户要求新增"（原型 `05-repo.js` 的面包屑右侧
    /// 只有一颗「＋ 添加」文字按钮，没有菜单；`SCR.fileView` 的 `.crumb` 右端
    /// 连动作位都没有）。
    /// 取横排三点：这是 iOS 上"更多动作"的通用形，且它在一条**很矮**的
    /// 面包屑条里比竖排三点更平衡。
    public static let ellipsis = "ellipsis"

    // MARK: - markdown 图片（2026-10-12 新增，走查第 58 条）

    /// **图片** —— markdown 正文里那张图**正在取**时的占位图标。
    ///
    /// ⚠️ 与上面两个同属"原型里没有"：原型 `styles/04-screens.css` 的 `.markdown`
    /// 一族**连一条 `img` 规则都没有**（正文里一次都没画过图）⇒ 这个字形取自
    /// SF Symbols 里最直白的一支。
    ///
    /// ⚠️ 它只出现在**占位块**上 —— 真图不配任何图标。
    public static let image = "photo"

    /// **图片取不到** —— 占位块上那个警示图标。
    ///
    /// ⚠️ 与 `image` **有意分开**：加载中与加载失败是两件事，共用一个图标会让
    /// "等一下就好"和"这条路走不通了"长得一模一样。
    public static let imageFailure = "exclamationmark.triangle"

    // ⚠️ **有意没有** `history` / `more` / `openInBrowser` 三个常量。
    //    切片 6.4 起草时曾按"每个操作按钮配一个图标"补过它们，落地时发现
    //    `SCR.fileView` 的 `历史` / `更多` 与那两处"跳网页端"的出口**都是纯文字**
    //    （原型的 `<button>` 里没有任何 `svg(...)`）⇒ 补的三个名字一个都用不上。
    //    留着的名字不是"以后可能用得上"，而是下一个读这份表的人要先判断
    //    "它是不是还在用"（`GitHubIcon` 的类型说明点名的正是这件事）。
    //
    //    ⚠️ 反过来说，`pencil` / `trash` 两个是**查过原型的**才加的：
    //    `11-favorites.js` 那两行 `.sheet-row` 里明明白白写着 `svg(I.pencil)` / `svg(I.trash)`。
    //    "切片 8 的弹层会不会也用图标"这件事不靠猜 —— §5.15 明写形态照 §5.12。

    // MARK: - 「我的」页菜单与设置（切片 9）

    /// 「Star 管理」菜单行 —— 原型 `I.star`（`12-me.js:23`）。
    ///
    /// ⚠️ 与 `StatButton` 那颗**星形按钮**用的是同一个字形，但颜色完全不同：
    /// 那一颗在"已 Star"时取 `Theme.Palette.starActive`（金色），
    /// 而菜单行恒是 `--text2`（`MenuRow` 给前导图标的那个）。
    /// 两者共用的是**图标名**，不是颜色 —— 别因为"都是星"就把颜色也并过来
    /// （金色在白底上对比度不足 2:1，见 `starActive` 的抬头）。
    public static let star = "star"

    /// 「设置」菜单行 —— 原型 `I.gear`（`12-me.js:29`）。
    ///
    /// ⚠️ 取的是小写 `gearshape`（齿轮形状那一个），**不是** `Gear` / `gearshape.fill`
    /// —— 本文件抬头那条"名字写错不会报错、只会在界面上消失"在这里同样适用，
    /// 而这个字面量是本片唯一没法靠单测钉住的东西。改它请务必跑一次模拟器。
    public static let settings = "gearshape"

    // ⚠️ 「我的 Pull Request」与「我的 Issue」两个菜单行**不在这里**：
    //    它们取的是 `StateIcon.pullRequestOpen` / `StateIcon.issueOpen`
    //    —— 原型的 `I.pr` / `I.issueO` 正是 `StateIcon` 那两个常量的出处，
    //    再抄一份到这里就是"同一个字形两个名字"（本文件抬头点名的正是这件事）。
    //    仓库详情页那两行 `LinkRow` 也是这么取用的（`ExploreRepoDetailView`）。
}
