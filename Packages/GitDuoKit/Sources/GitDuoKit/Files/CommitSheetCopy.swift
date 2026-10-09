import Foundation

/// 「提交更改」弹层（§5.9）与 §5.8 三个出口下游的全部可见文案。
///
/// ## ⚠️ 为什么不并进同目录下的 `CommitCopy`
///
/// `CommitCopy` 管的是**读**那一侧（提交列表 §4.4 分区四、提交详情页 §4.7：
/// 短哈希徽章、diff 提示、空态）。本类型管的是**写**那一侧（commit 这个**动作**）。
/// 两者共用的只有一个词根"提交"—— 合成一份会让"这个文件在讲哪件事"
/// 从文件名上消失。
///
/// ## 逐字来源
///
/// - 弹层标题、占位、分段、提示条、按钮、页脚、两条成功提示 → 原型
///   `scripts/15-sheets.js` 的 `openCommitSheet` / `doCommit`（逐字）；
/// - 两行输入与 409 两个出口、以及多步操作的两句 → PRD §5.9 ①–④（2026-10-08 补入）；
/// - `compressedNotice`（`已压缩 3.2MB → 0.8MB`）→ `PRD §5.8` / **决策 #71⑤**（2026-10-09 补入）；
/// - 标了「**规格未给**」的几条是本片自拟的，已在 `REVIEW-CHECKLIST` 登记。
public enum CommitSheetCopy {

    // MARK: - 来源（弹层标题那一段，取值逐字来自 PRD §5.9）

    public static let sourceNewFile = "新建文件"
    public static let sourceUploadFile = "上传文件（文件 App）"
    public static let sourceUploadImage = "上传图片（相册）"

    /// `编辑 {文件名}`（原型 `openCommitSheet('编辑 '+p.f)` 逐字）。
    public static func sourceEditing(fileName: String) -> String {
        "编辑 \(fileName)"
    }

    /// 提交信息为空时的默认值（原型 `doCommit` 逐字）。
    ///
    /// ⚠️ 它**同时是 PR 标题的兜底值**（`CommitDraft.effectivePRTitle`）——
    /// 因为 `POST /pulls` 的 `title` 必填，不能让一个空标题发出去。
    public static let defaultMessage = "update via GitDuo"

    // MARK: - 弹层骨架（原型逐字）

    /// 弹层标题：`提交更改 · {来源}`。
    public static func sheetTitle(source: String) -> String {
        "提交更改 · \(source)"
    }

    /// 提交信息输入框的占位（原型逐字）。
    public static let messagePlaceholder = "提交信息（commit message）"

    /// 目标分段 —— 第一档：`提交到 {当前分支}`（原型逐字）。
    public static func targetCurrent(branch: String) -> String {
        "提交到 \(branch)"
    }

    /// 目标分段 —— 第二档（原型逐字）。
    public static let targetNewBranch = "新分支 + PR"

    /// 选中「新分支 + PR」后出现的提示条（原型逐字）。
    ///
    /// ⚠️ 模板里的那个 `{当前分支}` 取自**原型那两处都是当前分支**
    /// （`openCommitSheet` 里 `改动不直接进 ${curBranch()}`）——
    /// 它是**参数**而不是常量，因为切成别的仓库 / 别的分支时这句话会变。
    public static func newBranchHint(branch: String) -> String {
        "将创建新分支并自动打开 Pull Request，改动不直接进 \(branch)"
    }

    /// 确认按钮（原型逐字）。
    public static let confirmAction = "提交"

    /// 页脚（原型逐字）。
    ///
    /// ⚠️ 它承诺的是"409 时**可选**查看最新版或强制覆盖" —— 那两个出口必须真的存在
    /// （决策 #69 落的正是这条）。否则就是文案承诺了实现做不到的事。
    public static let footer = "冲突保护：提交遇 409（远端已更新）时，可选查看最新版或强制覆盖"

    // MARK: - 上传出口独有的只读行（决策 #70②）

    /// `将写入 {路径}` —— **只读**一行，把 App 自动决定的那件事露出来（§5.8）。
    ///
    /// ⚠️ 它**不是输入框**：改路径请改用「新建文件」（§5.8 明写）。
    public static func destinationNotice(path: RepoPath) -> String {
        "将写入 \(path.raw)"
    }

    // MARK: - 「已压缩」那一句（决策 #71⑤）

    /// 提交弹层里那行只读落点下的一句：`已压缩 3.2MB → 0.8MB`。
    ///
    /// ## ⚠️ 这一句为什么必须有
    ///
    /// 决策 #71 让 App 在上传前**改掉了用户选中的那份字节**（重编码、有损、还会剥掉
    /// EXIF 含 GPS）。不写这一句，用户拿到的是一张**他自己没同意改过**的图 ——
    /// 而"App 替你决定了什么"这条在 #70② 那行「将写入 `{path}`」上已经立过一次
    /// （路径是 App 定的 ⇒ 露出来）。这里同一个理由，只是被决定的东西从"存到哪"变成了"存的是什么"。
    ///
    /// ## ⚠️ 两个数都是**真的**
    ///
    /// 前一个是选中那一刻的字节数、后一个是**真正要写上去的**字节数（`UploadCompression`
    /// 的两个字段都由 `UploadIntake` 实测填进去，没有一处是估的）。
    /// 印一个编出来的"省了多少"很容易，但那句话会在某次改动之后安静地变成假话。
    ///
    /// ⚠️ 没压过（≤1MB 的图 / 非图片）时**这一句不出现** —— 调用方传 `nil` 即可（`CommitSheet`）。
    public static func compressedNotice(_ compression: UploadCompression) -> String {
        "已压缩 \(sizeLabel(compression.originalBytes)) → \(sizeLabel(compression.finalBytes))"
    }

    /// 一位小数的 MB（`3.2MB`）。
    ///
    /// ⚠️ 与上面 `megabytes(_:)`（**向上取整的整数**）**是两个量**：那个说的是"上限是几 MB"
    /// （说 `4.7MB` 没有意义），这个说的是"这个文件多大"（说 `5MB` 会让 0.8 与 1.4 看起来一样大）。
    /// 合成一个必然有一处说错。
    ///
    /// ⚠️ 下限 `0.1MB`：一位小数下印 `0.0MB` 是句废话（它没告诉用户"其实很小"）。
    /// 这不是谎报 —— 它仍然落在"≤1MB"这一侧，而这一句的用途是让用户看到"小了"，不是精确报数。
    private static func sizeLabel(_ bytes: Int) -> String {
        String(format: "%.1fMB", max(0.1, Double(bytes) / 1_000_000))
    }

    // MARK: - 「新分支 + PR」多出的两行输入（决策 #67）

    public static let newBranchNameLabel = "分支名"
    public static let prTitleLabel = "PR 标题"

    /// 分支名输入框的读屏提示 —— 说清"这是能改的"。
    ///
    /// ⚠️ **规格未给**（自拟）。加它是因为预填值本身**看起来像一段不可改的说明文字**，
    /// 而决策 #67 存在的理由恰恰是"用户对这两个值必须有控制权"。
    public static let newBranchNameAccessibilityHint = "可以修改，它会成为仓库里的一条分支"

    // MARK: - 两条成功提示（原型 `doCommit` 逐字，编号改为服务端回的）

    /// 提交到当前分支。
    public static func committedToast(branch: String, message: String) -> String {
        "已提交到 \(branch) · “\(message)”"
    }

    /// 提交到新分支并开出了 PR。
    ///
    /// ⚠️ 原型写的是 `PR #58` —— 那是**演示编号**，真实编号只能来自
    /// `POST /pulls` 的响应体（同 `CreatedIssue.number` 的理由）。
    public static func committedWithPullToast(number: Int, message: String) -> String {
        "已提交到新分支并创建 PR #\(number) · “\(message)”"
    }

    // MARK: - 多步操作的部分失败（决策 #68①、PRD §5.9④）

    /// 分支建好了、提交失败了。
    ///
    /// ⚠️ 这句话里那个"已创建"**必须是真的** —— 那一刻分支确实在仓库里了，
    /// 用户再点一次会撞上"分支已存在"；而如果这里只说"提交失败"，
    /// 他根本不知道自己已经留下了一条分支（决策 #68 点名的情形）。
    public static func branchCreatedNotCommittedToast(branch: String) -> String {
        "\(branch) 已创建，但改动未提交"
    }

    /// 提交成功、PR 没建起来。
    ///
    /// ⚠️ 同上：改动**确实已经进了那条新分支**，所以不能说"提交失败"。
    /// 配一个去网页端建 PR 的出口（`openCompareInBrowserAction`）。
    public static func committedButNoPullToast(branch: String) -> String {
        "改动已提交到 \(branch)，PR 未创建"
    }

    /// 「PR 未创建」时的出口按钮。
    ///
    /// ⚠️ **规格未给**（自拟，PRD §5.9④ 只写"给网页端出口"）。
    /// 落到 GitHub 的**建 PR 页**（`compare/{base}...{head}?expand=1`）而不是分支页：
    /// 这一步用户要做的事**就是建 PR**，送到分支页他还得自己找入口。
    public static let openCompareInBrowserAction = "在 GitHub 上创建 Pull Request"

    // MARK: - 409 的两个出口（决策 #69、PRD §5.9③）

    /// 409 之后那一句说明。
    ///
    /// ⚠️ **规格未给**（自拟，PRD 只给了两个按钮名）。两条约束：
    /// ① **不替用户断定"别人改了这个文件"**（§9.6.4：他可能就是同一个人在另一台设备上改的）；
    /// ② 要说清"要做一个选择"，因为下一步是两个按钮而不是"重试"。
    public static let conflictHint = "这个文件在你看过之后被更新过，需要先确认用哪一版"

    /// 出口一（PRD §5.9③ 逐字）。
    public static let viewLatestAction = "查看最新版"

    /// 出口二（PRD §5.9③ 逐字）。
    public static let forceOverwriteAction = "强制覆盖"

    /// 「查看最新版」之后的说明 —— ⚠️ **不自动重提**（PRD §5.9③ 明写）。
    ///
    /// ⚠️ **规格未给**（自拟）。它防的是"用户以为已经重提上去了"。
    public static let viewLatestHint = "已取回最新内容，看清之后再提交"

    /// 返回提交弹层（从「查看最新版」那一屏回到能改信息的那一屏）。
    public static let backToSheetAction = "返回"

    /// 强制覆盖的二次确认标题（§9.6.4 要求"危险操作需二次确认"）。
    public static let forceOverwriteConfirmTitle = "确认覆盖？"

    /// ⚠️ **规格未给**（自拟）。说清**丢的是什么**：远端那一次改动，
    /// 而它只能去网页端的提交历史里找回（与 `FileCopy.deleteWarning` 同一句式）。
    public static let forceOverwriteConfirmHint = "远端那一版会被丢弃，且无法从 App 里找回"

    /// 结果屏上关闭弹层的按钮（两档"做到一半"用）。
    ///
    /// ⚠️ **规格未给**（自拟，PRD §5.9④ 只写了"必须说出哪一步成了"）。
    /// 不用 `FileCopy.cancelAction`（"取消"）：这一屏上**没有可取消的东西**，
    /// 那两件事都已经在仓库里了 —— 说"取消"会让用户以为按下去能撤销它。
    public static let partialDoneAction = "知道了"

    // MARK: - 写失败的那几句（与 `FileWriteFailure` 一一对应）

    /// 422：目标路径上已经有文件了。
    ///
    /// ⚠️ 与 `FileCopy.renameDestinationExistsHint`（`该路径上已有文件`）**措辞不同**，
    /// 这是**有意**的：那一句是 PRD §5.16 给重命名写的逐字文案，
    /// 这一句是 §5.8 给上传 / 新建写的（`已有同名文件，请改名或到网页端处理`）。
    /// 两句都必须带"下一步"（改名 / 网页端），因为 422 本身解释不了这件事。
    public static let destinationExistsHint = "这个路径上已有同名文件，请改名或到 GitHub 网页端处理"

    /// 选中 / 拖进来的文件超过 1MB（§5.8 底部那句话的下游）。
    ///
    /// ⚠️ **规格未给**（自拟）。必须有这一句而不是静默不做 ——
    /// 真实照片动辄 >1MB，用户选完图什么都不发生会让他以为 App 坏了
    /// （§5.8 明写"不静默失败"）。
    ///
    /// ⚠️ 上限**从常量现算**（照 `FileCopy.unsupportedImageHint` 的先例）：
    /// 写死"1MB"的话，改 `SaveFile.maxContentBytes` 那天这句话会安静地变成假话。
    public static var tooLargeHint: String {
        "这个文件超过 \(megabytes(SaveFile.maxContentBytes))MB，请到 GitHub 网页端处理"
    }

    /// 说"几 MB"（向上取整，说"4.7MB"对用户没有意义 —— 同 `FileCopy` 那句的取舍）。
    private static func megabytes(_ bytes: Int) -> Int {
        max(1, Int((Double(bytes) / 1_000_000).rounded(.up)))
    }

    // MARK: - 结局 → 提示条上那句话（**唯一落点**）

    /// 一次提交的四种结局 → 提示条上那一句话。
    ///
    /// ## ⚠️ 为什么必须收在一处
    ///
    /// 提交这条路有**两个入口**：编辑器页（§4.6）与 §5.8 的两个上传出口。
    /// 两处各写一遍 `switch outcome` 的后果不是多几行 —— 而是同一个结局
    /// 在两个入口下弹出**不同的话**，而那种不一致只在用户换一条路走时才看得到。
    ///
    /// ⚠️ 两个成功档的文案里要**分支名与提交信息**，而它们不在 `FileSaveOutcome` 里
    /// （`.committedToCurrentBranch` 只带收据）⇒ 由调用方补两个参数进来。
    /// 「新分支」那两档用的是 `outcome` 里那个分支（**不是** `currentBranch`：
    /// 用户填的那条新分支名才该出现在提示里）。
    ///
    /// - Parameters:
    ///   - currentBranch: 进弹层时的那条分支（只给"提交到当前分支"那一档用）。
    ///   - message: **真正发出去**的那条提交信息（`CommitDraft.effectiveMessage`）——
    ///     不是用户输入框里的原文（空的时候它会回落成默认信息）。
    public static func toast(
        for outcome: FileSaveOutcome,
        currentBranch: String,
        message: String
    ) -> String {
        switch outcome {
        case .committedToCurrentBranch:
            committedToast(branch: currentBranch, message: message)

        case let .createdBranchAndPull(_, _, number):
            committedWithPullToast(number: number, message: message)

        case let .branchCreatedButCommitFailed(branch, _):
            branchCreatedNotCommittedToast(branch: branch)

        case let .committedButPullCreationFailed(branch, _, _):
            committedButNoPullToast(branch: branch)
        }
    }
}
