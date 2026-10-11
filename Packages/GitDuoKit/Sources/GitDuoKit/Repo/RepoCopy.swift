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
    /// ⚠️ **全角 `＋` 是这个按钮上唯一的加号**（2026-10-11）：此前文案旁边还并排着一颗
    /// `GitHubIcon.plus` 图标（原型 `I.plus` 也在），用户报回「有两个加号」后删掉了图标。
    /// 留下的这一个与「添加」二字**同字体、同字号**（`footnote`），严格同大 —— 这也是它
    /// 被选中的理由。见 `REVIEW-CHECKLIST` 第 52 条。
    ///
    /// ⚠️ **切片 8.4 起可点**（打开 §5.8 的添加文件弹层，三个出口全部接通）。
    /// 它此前那套"画出但不可点"的形态（`allowsHitTesting(false)` + 读屏 hint）
    /// 连同 `addFileUnavailableHint` 一起删掉了 —— 留着那句 hint，
    /// "这三个出口还不能用"在代码里就仍然看起来成立。
    public static let addFileAction = "＋ 添加"

    // MARK: - §5.8 添加文件弹层
    //
    // ⚠️ 这一节**当初整节都是「规格未给，待评审」**：PRD §5.8 只写"三个出口"，
    //    原型 `openAddSheet` 给了标题与三行文案，而三行各自的去向**两边都没写全**。
    //    那批按原型逐字拟，并在 `REVIEW-CHECKLIST` 登记。
    //    ⚠️ **2026-10-08 起不再是"规格未给"**：切片 8 把三行去向与两个上传出口的落点
    //    都补进了 `PRD §5.8`（决策 #70）⇒ 剩下与原型不同的地方按**有意偏差**登记（第 7 条）。

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
    ///
    /// ⚠️ **2026-10-09 后半句改了两次**：先由 **决策 #71** 补上"超过 1MB 的图片会自动压缩"
    ///（原先写的是"更大的文件本期不支持"，而 >1MB 的**图片**从此不再"不支持"），
    /// 再由 **决策 #72** 补上"HEIC 等格式会自动转换"（网页端显示不出来的格式一律转，
    /// **且 ≤1MB 也转**）。
    /// 这两截必须跟着改：它们是**唯一**在选图之前就告诉用户"东西会被动过"的地方
    ///（另一处是提交弹层里那句 caption，见 `CommitSheetCopy.adjustmentNotice`）。
    /// 不改的后果是用户在**不知情**的情况下被 App 换掉了他要传的字节、甚至改了文件名。
    ///
    /// ⚠️ 它与 `PRD §5.8` 的"底部提示"那一行**逐字相同**（2026-10-09 对齐）——
    /// 以前两处各写一版、只差几个字，而"文案是契约"要求正本只有一份。
    public static let addFileSheetHint = "单个文件 ≤1MB 可直接提交 · 超过 1MB 的图片会自动压缩 · HEIC 等格式会自动转换 · 更大的其他文件请到 GitHub 网页端处理"

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
