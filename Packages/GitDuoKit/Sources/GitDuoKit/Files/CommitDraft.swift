import Foundation

/// 提交更改弹层（§5.9）上那份**草稿态**。
///
/// ## 为什么不是"两个 `@State` 字符串"
///
/// 三条规则必须只有一处落点，而三条都属于"写错了不会报错、只会安静地写错东西"：
///
/// 1. **提交信息为空时用默认信息**（`update via GitDuo`，§5.9、原型 `doCommit` 逐字）——
///    那是**发出去的内容**、也是 PR 标题的兜底值，不是界面上的话。
/// 2. **PR 标题为空时回落到同一条默认信息** —— 官方 `POST /pulls` 的 `title` 必填，
///    而"空 PR 标题"在服务端是一档参数校验失败，文案解释不了"我明明只想用默认值"。
/// 3. **两处 trim 的时机**（见 `effectiveMessage` 的说明）。
///
/// 与 `NewIssueDraft` 同源：可见契约与产品规则落领域层，才能被单测钉住。
public struct CommitDraft: Sendable, Hashable {

    /// 用户输入的提交信息（原样保存，含前后空格）。
    public var message: String

    /// 写到哪去（当前分支 / 新分支 + PR）。
    public var target: FileWriteTarget

    /// 这次提交**从哪来** —— 决定弹层标题那一段（`提交更改 · {来源}`，§5.9 首行）。
    ///
    /// ⚠️ 它是**草稿的一部分**而不是调用方另传一个参数给视图：
    /// 标题与"哪个页面的动作"必须同源，两处各传一次会出现
    /// "编辑器上写的是新建文件、弹层标题写的是编辑 X"。
    public var source: CommitSource

    public init(
        message: String = "",
        target: FileWriteTarget = .currentBranch,
        source: CommitSource
    ) {
        self.message = message
        self.target = target
        self.source = source
    }

    /// 真正发出去的那条提交信息（§5.9：空则用默认信息）。
    ///
    /// ⚠️ **trim 在"发出去"这一步，不在落盘那一份上**：`message` 原样保存，
    /// 于是用户在输入框里打的尾随空格**不会在他打字过程中被吃掉**
    /// （那是编辑器里最让人困惑的一类行为）。原型 `doCommit` 也是这个次序
    /// （`(value||'').trim()||'update via GitDuo'`）。
    public var effectiveMessage: String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? CommitSheetCopy.defaultMessage : trimmed
    }

    /// 真正发出去的 PR 标题（只有「新分支 + PR」那一档用得上）。
    ///
    /// 回落链：用户填的 PR 标题 → 非空则用；否则用 `effectiveMessage`。
    /// ⚠️ 回落**不是**"再给一句默认标题"：PR 标题与提交信息说的是同一件事，
    /// 用户在提交信息里写的那句就是他想留下的那句话（决策 #67 的预填规则）。
    public var effectivePRTitle: String {
        let trimmed = target.newBranchPRTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? effectiveMessage : trimmed
    }

    /// 用户填的分支名 —— **原样**，不做 trim 也不校验。
    ///
    /// ⚠️ 故意不在这里 trim：`SaveFile` 会 trim 一次再交给 `BranchName.validate`
    /// （照 `CreateBranch.run` 的次序）。两处都 trim 不会出错，但会让
    /// "谁是那条规则的落点"变成一个看代码才知道的问题。
    public var effectiveBranchName: String? {
        target.newBranchName
    }
}

/// 这次提交从哪个入口来 —— 弹层标题的 `{来源}`（§5.9 首行，取值逐字来自 PRD）。
public enum CommitSource: Sendable, Hashable {

    /// 编辑器（新建模式）→ `新建文件`。
    case newFile

    /// 编辑器（编辑模式）→ `编辑 {文件名}`。
    case edit(fileName: String)

    /// §5.8 的第二个出口 → `上传文件（文件 App）`。
    case uploadFile

    /// §5.8 的第三个出口 → `上传图片（相册）`。
    case uploadImage

    /// 弹层标题那一段（原型 `openCommitSheet(src)` 的三个取值 + 编辑模式那一条）。
    public var title: String {
        switch self {
        case .newFile: CommitSheetCopy.sourceNewFile
        case let .edit(fileName): CommitSheetCopy.sourceEditing(fileName: fileName)
        case .uploadFile: CommitSheetCopy.sourceUploadFile
        case .uploadImage: CommitSheetCopy.sourceUploadImage
        }
    }

    /// 这个来源**路径是自动定的**吗（§5.8 的两个上传出口）。
    ///
    /// ⚠️ 判据放在类型上而不是让弹层写 `if source == .uploadFile || source == .uploadImage`：
    /// 那句在视图里出现两次（要不要画只读的「将写入 `{path}`」行、
    /// 要不要显示"改路径请改用新建文件"），两处迟早只改一处。
    /// 而那一行**是决策 #70② 明确要求露出来的**（用户根本不知道东西存哪去了）。
    public var pathIsAutomatic: Bool {
        switch self {
        case .uploadFile, .uploadImage: true
        case .newFile, .edit: false
        }
    }
}
