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

    /// 在**某一层目录**里新建文件时，路径框该预填什么。
    ///
    /// ## ⚠️ 2026-10-12：加了目录前缀（用户报回）
    ///
    /// 用户原话：「在添加或者上传文件的时候都是直接上传到了根目录，而不是上传到我打开的
    /// 对应目录下」。原先无论从哪一层点「＋ 添加 → 新建文件」，框里都只有 `NewFile.swift`
    /// ⇒ 不改就直接提交，文件落在**仓库根**，而不是用户当时正看着的那一层。
    ///
    /// - 根目录（或"没有目录"这一档）⇒ 就是 `defaultNewFilePath`，与过去**逐字相同**；
    /// - 子目录 ⇒ `{当前目录}/{defaultNewFilePath}`（如 `docs/NewFile.swift`）。
    ///
    /// ⚠️ **这不与第 28 条冲突**：那一条否决的是"预填一个**演示用的**多级路径"
    ///（原型的 `GitDuo/Features/NewFile.swift` —— 那个目录是凭空编的）。这里的前缀是
    /// **用户自己走进去的那一层**，不是编的。
    ///
    /// - Parameter directory: 当前打开的那一层目录；`nil` 与"根"同义。
    public static func defaultNewFilePath(in directory: RepoPath?) -> String {
        guard let directory, !directory.isRoot else { return defaultNewFilePath }
        return "\(directory.raw)/\(defaultNewFilePath)"
    }

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

    // MARK: - 路径框的校验（**规格未给**，切片 8.4 自拟）

    /// 路径为空（或全空白）。
    ///
    /// ⚠️ **规格未给**：PRD §4.6 只写了"预填 `NewFile.swift`、可改成任意相对路径"，
    /// 没有覆盖"用户把它清空之后点提交"。加这一句是因为服务端对这一档只回一个 **422**
    /// —— 而那句话（"服务器验证失败"）解释不了"我忘了填路径"。
    ///
    /// ⚠️ 它与 `FileCopy.renameEmptyHint` **是同一个词、两个落点**（这里不跨命名空间引用）：
    /// 一个是"新建文件时没填路径"、一个是"重命名时没填路径"，两句将来各有各的改法。
    public static let emptyPathHint = "先输入文件路径"

    /// 某一级路径不合法（`.` / `..` / 空段）。
    ///
    /// ⚠️ **规格未给**（与 `FileCopy.renameInvalidPathHint` 同一条判据、同一个理由）：
    /// 那一串在服务端是**另一条路径**，而界面上看起来只是想建一个文件。
    /// 提示里点名那一级 —— 用户需要知道改哪里。
    public static func invalidPathHint(component: String) -> String {
        "路径里的「\(component)」不是有效的一级，请去掉它"
    }

    /// 把 `NewFileDestinationIssue` 翻成一句话（**唯一落点**）。
    ///
    /// ⚠️ 收成一处而不是让编辑器页 `switch` 一次：那一句要显示在输入框下方，
    /// 而"哪一档说哪句话"是文案（领域层的事），不是布局。
    public static func pathHint(for issue: NewFileDestinationIssue) -> String {
        switch issue {
        case .empty: emptyPathHint
        case let .invalidComponent(component): invalidPathHint(component: component)
        }
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

    /// 图片 ⇒「编辑」按钮**不可点**（**规格未给**，切片 8.4 自拟）。
    ///
    /// ⚠️ 为什么要有这一档：编辑器是一个**文本**编辑器（§4.6 的编辑区、§9.6 的
    /// `PUT contents` 都只处理文本）。一张 `.png` 被点开之后，编辑器只能给出
    /// `EditorContentIssue.notText` 那个失败态 —— 而用户一路点下来什么都没做错。
    ///
    /// ⚠️ 与 `editTooLargeHint` **必须分开**：那句说的是"太大"，
    /// 而图片的问题**不是大小**（一张 3KB 的图标同样编辑不了）。
    /// 照那句说就是**假话**，且用户会去网页端找一个"压缩一下就能编辑"的办法。
    public static let editImageHint = "这个文件是图片，App 内无法编辑"

    // MARK: - `FilePreviewKind` → 那一句提示（**唯一落点**）

    /// 「编辑」按钮在这一档上不可点吗？不可点的话，那句话是什么。
    ///
    /// - Returns: `nil` = **可以点**（`.text`：≤1MB 的文本，正路上唯一可编辑的一档）。
    ///
    /// ⚠️ 收成一处而不是让 `FileView` 自己 `switch`：两档的理由不同（太大 / 不是文本），
    /// 而"哪一档说哪句话"是**文案**（领域层的事），不是布局。
    /// 写成两处之后，加第三档时只会更新其中一处。
    ///
    /// ⚠️ `.unsupported` 这一档返回 `nil`，因为**它根本不画操作行**
    /// （`FileView` 类型说明第 1 条「规格未给」：看不了的文件上没有"编辑"这一说）。
    /// 这里的 `nil` 是"没有人会来问"，不是"它可以点"。
    public static func editHint(for preview: FilePreviewKind) -> String? {
        switch preview {
        case .text: nil
        case .largeText: editTooLargeHint
        case .image: editImageHint
        case .unsupported: nil
        }
    }
}
