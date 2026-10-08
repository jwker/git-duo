import Foundation

/// 编辑器页（§4.6）的全部可见文案。
///
/// ## 逐字来源
///
/// 除标了「**规格未给**」的几条外，全部来自原型 `scripts/06-files.js` 的
/// `SCR.editor`；两处 2026-10-08 补入的规格（路径框预填值、编辑区初值）见 PRD §4.6。
public enum EditorCopy {

    // MARK: - 说明行（原型逐字，`· 分支 {当前分支}` 是固定的第二段）

    /// 新建模式的前半句（原型逐字）。
    public static let createInstruction = "新建文件 · 输入路径（自动创建目录）"

    /// 编辑模式的前半句（原型逐字）。
    ///
    /// ⚠️ 这里说的是"语法高亮轻量编辑器" —— 原型确实高亮（它用 `span.kw` 手写了几行）。
    /// App 侧由 `CodeTextArea` 承担，本期是**纯等宽文本**（不高亮）：
    /// 这句话因此与实现对不上，已登记为有意偏差（见 `REVIEW-CHECKLIST`）。
    /// 保留逐字是为了"改动一眼可辨"，而不是让文案替实现打圆场。
    public static let editInstruction = "编辑 · 语法高亮轻量编辑器"

    /// 说明行整句：`{前半句} · 分支 {当前分支}`（原型逐字，两段用 ` · ` 连接）。
    public static func instructions(mode: EditorMode, branch: String) -> String {
        let head = mode == .create ? createInstruction : editInstruction
        return "\(head) · 分支 \(branch)"
    }

    // MARK: - 新建模式的路径输入框（PRD §4.6，2026-10-08 补）

    /// 路径框的**预填值**：`NewFile.swift`。
    ///
    /// ⚠️ **原型这一屏给过两个不一致的默认路径**：
    /// `openAddSheet` 里 push 的是 `{f:'NewFile.swift'}`，而编辑器输入框预填的是
    /// `GitDuo/Features/NewFile.swift`。取**前者** —— 它是被回归断言钉住的那个
    /// （`assert(topTitle()==='NewFile.swift')`），而"预填一个演示用的多级路径"
    /// 会让用户不假思索地提交出一个仓库根目录之外、谁都没打算建的文件。
    /// 已登记为有意偏差（`REVIEW-CHECKLIST` 第 28 条）。
    /// ⚠️ 它**不是占位符**：框里预填的是真值，用户可以直接提交（§4.6）。
    /// 导航标题（新建模式）用的也是同一个常量 —— 见 `navigationTitle(mode:fileName:)`。
    public static let defaultNewFilePath = "NewFile.swift"

    // MARK: - 动作与页脚（原型逐字）

    /// 提交按钮（原型逐字，含省略号）。
    public static let submitAction = "提交更改…"

    /// 页脚（原型逐字）。
    public static let footer = "保存即一次提交 · 单个文件超过 1MB 请到 GitHub 网页端处理"

    // MARK: - 导航标题（PRD §4.6）

    /// 导航标题：编辑模式 = 文件名；新建模式 = 路径框那个预填值。
    ///
    /// ⚠️ 新建模式用**预填值**而不是"新建文件"：用户可能已经把路径框改成了
    /// `docs/guide.md`，而标题还写着"新建文件"就与框里的内容对不上了。
    /// 原型 `inline:p=>p.f` 也是这么做的（它取的就是那个 `f`）。
    public static func navigationTitle(mode: EditorMode, fileName: String) -> String {
        mode == .create ? defaultNewFilePath : fileName
    }

    // MARK: - 「编辑」不可点的那一档

    /// 文件超过 1MB ⇒「编辑」按钮**不可点**（决策 #54 的边界、`REVIEW-CHECKLIST` 偏差 32）。
    ///
    /// ⚠️ **规格未给**（自拟）。加它的理由同 `FileCopy` 其余 hint：
    /// 一颗点不动的按钮不解释原因，读屏用户只会反复点它 —— 而这条路上没有任何反馈。
    ///
    /// ⚠️ 它与 `FileCopy.unsupportedBinaryHint` 那类"看都不给看"**不是一回事**：
    /// 大文件**能看**（走 raw），不能的只是"在 App 里改它"。
    /// 合成一句会让用户以为连预览都被禁了。
    public static let editTooLargeHint = "这个文件超过 1MB，App 内无法编辑，请到 GitHub 网页端处理"
}
