import Foundation

/// 仓库详情页——**自己的仓库**（§4.4）——的可见文案。
///
/// 与 `SearchCopy` 同源：可见契约放领域层，才能被单测钉住。
///
/// ⚠️ **只收本页新增的句子**。头部那一排统计按钮（`Star · {n}` / `Watch · {n}` /
/// `Fork · {n}`）是切片 4 就有的（`StatButton` 收文案、`RepositoryDetail` 供数），
/// 本页复用，**不在这里再定义一遍** —— 两处定义同一个句子，迟早只改一处。
public enum RepoCopy {

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
