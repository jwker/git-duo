import Foundation
import GitDuoCore

/// 仓库详情页——**自己的仓库**（§4.4）——的可见文案。
///
/// 与 `SearchCopy` 同源：可见契约放领域层，才能被单测钉住。
///
/// ⚠️ **头部那一排统计按钮的三句文案在下面「头部统计按钮」一节**。
/// 它们原先散在 `RepoHeroCard` 里（§4.13 那一页落地时写的），而 §4.4 的头部
/// 是**同一个控件、同一个数、同一句话** ⇒ 6.4 收拢到这里一处定义。
/// 两份定义同一个句子的坏处不是多几行，而是它们会分叉：某一页改了千分位口径、
/// 另一页没改，于是同一个仓库在两页上显示成两个数（而两页单看都对）。
public enum RepoCopy {

    // MARK: - 头部统计按钮（§4.4 与 §4.13 共用）

    /// `Watch · {n}`。
    ///
    /// ⚠️ 计数读 `RepositoryDetail.watcherCount`（来源 `subscribers_count`），
    /// **不是** `watchers_count` —— 后者是 `stargazers_count` 的历史别名，
    /// 读错不会报错，只会让 Watch 与 Star 显示成同一个数。
    public static func watchLabel(count: Int) -> String {
        "Watch · \(GroupedNumber.string(from: count))"
    }

    /// `Fork · {n}`。
    public static func forkLabel(count: Int) -> String {
        "Fork · \(GroupedNumber.string(from: count))"
    }

    /// Watch 按钮的读屏提示。它**纯展示、不可点**（PRD §4.4 / §4.13 都这么定）。
    ///
    /// ⚠️ 这句**不是 PRD 原文**（§4.4 只写"展示 Watch 数"）：一个点不动的按钮
    /// 若不解释，读屏用户只会反复点它。两页共用同一句。
    public static let watchUnavailableHint = "仅展示订阅计数，订阅动态依赖通知能力，本版本不做"

    /// Fork 按钮的读屏提示。理由同上。
    public static let forkUnavailableHint = "Fork 功能待细化，本版本不可用"

    // MARK: - 代码分区

    /// 空目录提示（原型 `repoSeg` 的 code 分支逐字）。
    public static let emptyDirectory = "空目录"

    /// 根目录里 README 区块的小节标题（原型 `.section-label` 逐字）。
    ///
    /// ⚠️ 它就是字面的 `README.md` —— 不是拼接出来的文件名。
    /// GitHub 的 `readme` 端点会**自动找** README（可能是 `README.rst`、
    /// `.github/README.md`），所以真实文件名可能与这三个字不同；
    /// 但原型与 PRD §4.4 都写这一句，且它是**小节标题**（"这里是 README 的内容"），
    /// 不是"这个文件的准确名字"。刻意保持逐字。
    public static let readmeSectionTitle = "README.md"

    /// 面包屑条右侧的「＋ 添加」按钮（原型逐字，含全角 `＋`）。
    ///
    /// ⚠️ 属切片 8（§5.8 的三个出口全通到编辑器或提交弹层）⇒ 本片**画出但不可点**
    /// （决策 #51，照决策 #46 先例：`allowsHitTesting(false)` + 读屏 hint，
    /// **不用** `.disabled` —— 后者会变灰、看起来像"暂时不可用"）。
    public static let addFileAction = "＋ 添加"

    /// 「＋ 添加」不可点时的读屏提示（决策 #51 要求的 hint）。
    ///
    /// 说清"为什么点不了"，而不是只说"不可用"：读屏用户听到理由才不至于
    /// 反复尝试同一个按钮。
    public static let addFileUnavailableHint = "添加文件在切片 8 落地，当前版本暂不可用"

    // MARK: - §5.8 添加文件弹层
    //
    // ⚠️ 这一节**整节都是「规格未给，待评审」**：PRD §5.8 只写"三个出口"，
    //    原型 `openAddSheet` 给了标题与三行文案，而三行各自的去向**两边都没写全**。
    //    本片按原型逐字拟，并在 `REVIEW-CHECKLIST` 登记。

    /// 弹层标题：`添加文件 · {当前分支}`（原型逐字）。
    public static func addFileSheetTitle(branch: String) -> String {
        "添加文件 · \(branch)"
    }

    /// 三个出口（原型逐字）。
    public static let newFileAction = "新建文件"
    public static let uploadFileAction = "上传文件 · 文件 App"
    public static let uploadImageAction = "上传图片 · 相册"

    /// 弹层底部说明。
    ///
    /// ⚠️ **据实改正了原型的那一句**（与决策 #47 / #53 同性质）。
    /// 原型写的是 `≤1MB 走 Contents API · 大文件走 Git Data API（blob → tree → commit → ref，上限 100MB）`，
    /// 而 `TECH_SPEC §9.6`【已定】**明确不引入 Git Data API**：
    /// > 单文件、≤1MB、无并发冲突 ⇒ Contents API；>1MB 或二进制大文件 ⇒ **本期不支持** → 提示并引导网页端。
    ///
    /// 照原型印那一句，就是**文案承诺了一件实现做不到的事** ——
    /// 而这条正是本项目明令禁止的（`AGENTS.md §3`："文案 / 权限 / 产品承诺要提为可测领域数据"，
    /// 起因就是曾出过"文案承诺撤销授权、实现却做不到"）。
    /// 这里取 §9.6 的事实，并把偏差登记待评审。
    public static let addFileSheetHint = "≤1MB 走 Contents API · 更大的文件本期不支持，请到 GitHub 网页端处理"

    // MARK: - 目录里进不去的条目（`symlink` / `submodule`）

    /// 点一个 `symlink` / `submodule` 时的提示。
    ///
    /// ⚠️ **规格未给，待评审**（PRD §3.2 只写 `dir` / `file` 两类，
    /// 原型也没有这两档 —— 它的演示数据里只有目录与文件）。
    ///
    /// 为什么必须说一句：那一行的形态与普通文件**完全一样**（`TreeEntry.Kind`
    /// 的说明：行照常显示）。所以点下去若直接跳浏览器而没有解释，
    /// 用户会以为"这个文件每次点都要跳出去"，而真实原因是 App 打不开这类条目 ——
    /// `symlink` 的内容是链接目标那串文本、`submodule` 的 `sha` 是另一个仓库的提交。
    public static let unsupportedEntryToast = "子模块与符号链接需在 GitHub 网页端查看"

    /// 面包屑里分支胶囊的读屏提示（无障碍，PRD §4.4 + TECH_SPEC §10.5）。
    ///
    /// ⚠️ 胶囊上写的是**分支名本身**（如 `main`），一个光秃秃的 `main`
    /// 在读屏里既不像按钮、也看不出按下去会发生什么。
    public static func branchChipAccessibilityLabel(branch: String) -> String {
        "当前分支 \(branch)，双击切换分支"
    }

    /// 面包屑里「当前层」的读屏提示 —— 它**加粗但不可点**（PRD §4.4）。
    ///
    /// 说一句"当前位置"是因为：面包屑里的前几级都是链接，
    /// 到了最后一级突然不能按，读屏用户会以为是坏了。
    public static func breadcrumbCurrentAccessibilityLabel(name: String) -> String {
        "当前位置 \(name)"
    }
}
