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
    public static let file = "doc.text"

    /// 列表行右侧的指示符 —— 原型 `I.chev`。
    public static let chevron = "chevron.right"

    /// 面包屑右侧的「＋ 添加」（原型用 `I.plus` 配全角 `＋` 文案，两者都在）。
    public static let plus = "plus"

    // MARK: - Fork（§4.4 / §4.13 的统计按钮）

    /// Fork —— 原型 `I.fork`（`05-repo.js` 的 `stat-btn` 与 `10-explore-repo.js` 各一处）。
    ///
    /// ⚠️ 与 `branch` 用的是**同一个**符号：原型这两处都画 `I.fork`。
    /// 复用而不是另找一个 —— 找不到同形的，"语义接近"的另一个符号
    /// 只会让这两处看起来是两件事。
    ///
    /// 原先两个头部卡里各自写了一串字面 `"arrow.triangle.branch"`，
    /// 2026-10-07（6.4）收拢到本常量 —— 与 `RepoCopy.watchLabel` 收拢那三句文案同一处置。
    public static let fork = "arrow.triangle.branch"

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
}
