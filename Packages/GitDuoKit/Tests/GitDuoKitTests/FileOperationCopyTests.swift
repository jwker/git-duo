import Foundation
import Testing

@testable import GitDuoKit

/// 切片 8 的写通道文案（§4.5 / §4.6 / §5.8 / §5.9 / §5.15–§5.17）。
///
/// ## 为什么这几句值得单独测
///
/// 它们的共同点是"**必须分开说**"，而"分开"恰恰是最容易被一次图省事的复用抹掉的：
/// 把"新路径已写入，原路径仍在"换成"重命名失败"，代码照样编译、提示照样弹出来，
/// 只是**用户会以为什么都没变**（而仓库里已经多了一个文件）。
///
/// 另一类是**文案对实现的承诺**：页脚写着"409 时可选查看最新版或强制覆盖"，
/// 那两个按钮就必须真的存在 —— 断言"页脚里点到了那两颗按钮的名字"
/// 是唯一能把这条承诺钉在测试里的办法（`grep` 查不出"承诺落空"）。
@Suite("写通道文案 · 必须分开 / 必须与实现对齐（切片 8.1）")
struct FileOperationCopyTests {

    // MARK: - 编辑器（§4.6）

    @Test("两种模式的说明行不同，且都带上当前分支")
    func editorInstructionsDifferByMode() {
        let create = EditorCopy.instructions(mode: .create, branch: "feature/x")
        let edit = EditorCopy.instructions(mode: .edit, branch: "feature/x")

        #expect(create != edit)
        #expect(create.contains("新建文件"))
        #expect(edit.contains("编辑"))
        // 两处都要有分支名 —— 用户此刻最可能搞错的就是"我在哪条分支上改"。
        #expect(create.contains("feature/x"))
        #expect(edit.contains("feature/x"))
    }

    @Test("⚠️ 导航标题：编辑模式是文件名，新建模式是路径框那个**预填值**")
    func navigationTitleFollowsMode() {
        #expect(EditorCopy.navigationTitle(mode: .edit, fileName: "main.swift") == "main.swift")
        #expect(EditorCopy.navigationTitle(mode: .create, fileName: "随便") == EditorCopy.defaultNewFilePath)
        // ⚠️ 原型的两个默认路径不一致，取的是被断言钉住的那个（偏差 28）。
        #expect(EditorCopy.defaultNewFilePath == "NewFile.swift")
    }

    /// 2026-10-12 用户报回：「添加或者上传文件的时候都是直接上传到了根目录，
    /// 而不是上传到我打开的对应目录下」—— 新建文件那一条通道靠的就是这个预填前缀。
    ///
    /// ⚠️ 根目录下**逐字不变**（`NewFile.swift`）—— 偏差 28 那条"不许预填编出来的多级路径"
    /// 仍然成立，这里加的是**用户自己走进去的那一层**。
    @Test("⚠️ 新建模式的路径框预填**带当前目录前缀**（根目录下与过去逐字相同）")
    func newFilePathPrefillCarriesCurrentDirectory() {
        #expect(EditorCopy.defaultNewFilePath(in: nil) == "NewFile.swift")
        #expect(EditorCopy.defaultNewFilePath(in: RepoPath.root) == "NewFile.swift")
        #expect(EditorCopy.defaultNewFilePath(in: RepoPath(path: "docs")) == "docs/NewFile.swift")
        #expect(
            EditorCopy.defaultNewFilePath(in: RepoPath(path: "docs/api"))
                == "docs/api/NewFile.swift"
        )

        // ⚠️ 拼出来的那一串**必须能过路径框自己那套判据** ——
        // 否则用户"什么都不改直接提交"会被自己的预填值拦下。
        guard case let .acceptable(prefilled) = RepoPath.resolveNewFile(
            input: EditorCopy.defaultNewFilePath(in: RepoPath(path: "docs"))
        ) else {
            Issue.record("预填值本身必须是一个可提交的路径")
            return
        }
        #expect(prefilled.raw == "docs/NewFile.swift")
    }

    @Test("⚠️ 超过 1MB 时「编辑」不可点的那句话**不是**「不支持预览」那一句")
    func editTooLargeHintIsNotThePreviewHint() {
        #expect(!EditorCopy.editTooLargeHint.isEmpty)
        #expect(EditorCopy.editTooLargeHint != FileCopy.unsupportedBinaryHint)
        #expect(EditorCopy.editTooLargeHint != FileCopy.unsupportedImageHint)
        // 大文件**能看**（走 raw），不能的只是"在 App 里改它" ⇒ 两句话必须分开说。
        #expect(EditorCopy.editTooLargeHint.contains("1MB"))
    }

    @Test("页脚承诺「单个文件超过 1MB 去网页端」（原型逐字）")
    func editorFooterMentionsTheLimit() {
        #expect(EditorCopy.footer.contains("1MB"))
        #expect(EditorCopy.footer.contains("网页端"))
    }

    @Test("⚠️「编辑」的判据只有 `.text` 可点，不可点的两档是**两句不同的话**")
    func editHintFollowsPreviewKind() {
        // 正路上唯一可编辑的一档（≤1MB 的文本）。
        #expect(EditorCopy.editHint(for: .text) == nil)
        #expect(EditorCopy.editHint(for: .largeText) == EditorCopy.editTooLargeHint)
        #expect(EditorCopy.editHint(for: .image) == EditorCopy.editImageHint)

        // ⚠️ 两句话必须不同：把图片说成"超过 1MB"，用户会去网页端找一个
        //    "压缩一下就能编辑"的办法 —— 而那个办法不存在。
        #expect(EditorCopy.editImageHint != EditorCopy.editTooLargeHint)
        #expect(EditorCopy.editImageHint.contains("图片"))
        #expect(!EditorCopy.editImageHint.contains("1MB"),
                "图片的问题**不是大小** —— 一张 3KB 的图标同样编辑不了")
        #expect(!EditorCopy.editImageHint.contains("网页端"),
                "图片在网页端也编辑不了 ⇒ 不能给一个到不了的出口")
    }

    // MARK: - 提交弹层（§5.9）

    @Test("⚠️ 页脚点名的两个出口**必须真的存在**（决策 #69 的意义就在这一句）")
    func footerNamesBothConflictExits() {
        #expect(CommitSheetCopy.footer.contains(CommitSheetCopy.viewLatestAction))
        #expect(CommitSheetCopy.footer.contains(CommitSheetCopy.forceOverwriteAction))
        #expect(CommitSheetCopy.viewLatestAction == "查看最新版")
        #expect(CommitSheetCopy.forceOverwriteAction == "强制覆盖")
    }

    @Test("⚠️ 409 的说明**不替用户断定**是别人改的（他可能就是自己在另一台设备上改的）")
    func conflictHintDoesNotBlameOthers() {
        #expect(!CommitSheetCopy.conflictHint.isEmpty)
        #expect(!CommitSheetCopy.conflictHint.contains("别人"))
        #expect(CommitSheetCopy.conflictHint.contains("更新"))
        // ⚠️ 强制覆盖是危险操作 ⇒ 二次确认那两句必须在，且说清丢的是什么。
        #expect(!CommitSheetCopy.forceOverwriteConfirmTitle.isEmpty)
        #expect(!CommitSheetCopy.forceOverwriteConfirmHint.isEmpty)
        #expect(CommitSheetCopy.forceOverwriteConfirmHint.contains("丢弃"))
    }

    @Test("两行输入与提示条都带分支名（那两行只在「新分支 + PR」时出现）")
    func newBranchCopyCarriesTheBranch() {
        let a = CommitSheetCopy.newBranchHint(branch: "main")
        let b = CommitSheetCopy.newBranchHint(branch: "feature/x")
        #expect(a != b)
        #expect(a.contains("main"))
        #expect(a.contains("Pull Request"))
        #expect(CommitSheetCopy.targetCurrent(branch: "feature/x").contains("feature/x"))
        #expect(CommitSheetCopy.targetNewBranch == "新分支 + PR")
        #expect(!CommitSheetCopy.newBranchNameLabel.isEmpty)
        #expect(!CommitSheetCopy.prTitleLabel.isEmpty)
    }

    @Test("只读的「将写入」行带上完整路径（决策 #70② 要求把这件自动决定的事露出来）")
    func destinationNoticeShowsPath() {
        #expect(CommitSheetCopy.destinationNotice(path: RepoPath(path: "docs/a.md"))
            == "将写入 docs/a.md")
    }

    @Test("⚠️ 两条成功提示不同，且提交信息用**原型那种引号**")
    func successToastsDiffer() {
        let current = CommitSheetCopy.committedToast(branch: "main", message: "改一行")
        let withPull = CommitSheetCopy.committedWithPullToast(number: 58, message: "改一行")

        #expect(current != withPull)
        #expect(current.contains("main"))
        #expect(withPull.contains("#58"), "⚠️ 编号只能来自响应体，不能靠本地猜")
        #expect(current.contains("“改一行”"))
    }

    @Test("⚠️ 两句「做到一半」说的是**互不相同**的事，且都把既成事实说出来")
    func partialFailureToastsStateWhatHappened() {
        let branchOnly = CommitSheetCopy.branchCreatedNotCommittedToast(branch: "gitduo/x")
        let noPull = CommitSheetCopy.committedButNoPullToast(branch: "gitduo/x")

        #expect(branchOnly != noPull)
        #expect(branchOnly.contains("gitduo/x"))
        #expect(branchOnly.contains("已创建"), "⚠️ 那条分支**真的在仓库里**了，必须说出来")
        #expect(branchOnly.contains("未提交"))

        #expect(noPull.contains("gitduo/x"))
        #expect(noPull.contains("已提交"), "⚠️ 改动**真的进了那条分支**，说「提交失败」是假话")
        #expect(noPull.contains("未创建"))
        #expect(!CommitSheetCopy.openCompareInBrowserAction.isEmpty)
    }

    @Test("⚠️ 上传超限那句话里的 MB **从常量现算**（写死「1MB」改常量那天会变成假话）")
    func tooLargeHintDerivesFromConstant() {
        let megabytes = max(1, Int((Double(SaveFile.maxContentBytes) / 1_000_000).rounded(.up)))
        #expect(CommitSheetCopy.tooLargeHint.contains("\(megabytes)MB"))
        #expect(CommitSheetCopy.tooLargeHint.contains("网页端"))
    }

    @Test("⚠️ 422 的两句话**措辞不同**（§5.8 与 §5.16 各自定的），但都非空、都带下一步")
    func destinationExistsHintsAreDistinctPerContext() {
        #expect(!CommitSheetCopy.destinationExistsHint.isEmpty)
        #expect(!FileCopy.renameDestinationExistsHint.isEmpty)
        #expect(CommitSheetCopy.destinationExistsHint != FileCopy.renameDestinationExistsHint)
        #expect(CommitSheetCopy.destinationExistsHint.contains("改名"))
        #expect(FileCopy.renameDestinationExistsHint == "该路径上已有文件")
    }

    // MARK: - 文件操作的三个弹层（§5.15–§5.17）

    @Test("§5.15 菜单：标题带文件名，两行是「重命名 / 删除文件」")
    func fileOperationsSheetCopy() {
        #expect(FileCopy.fileOperationsSheetTitle(fileName: "main.swift") == "文件操作 · main.swift")
        #expect(FileCopy.renameAction == "重命名")
        #expect(FileCopy.deleteAction == "删除文件")
        #expect(FileCopy.cancelAction == "取消")
    }

    @Test("§5.16 重命名：标题、说明、按钮、三条提示")
    func renameSheetCopy() {
        #expect(FileCopy.renameSheetTitle == "重命名文件")
        #expect(FileCopy.renameSheetHint == "重命名会移动文件 · 原路径将不再存在")
        #expect(FileCopy.renameConfirmAction == "保存")
        #expect(FileCopy.renameEmptyHint == "先输入文件路径")
        #expect(FileCopy.renameInvalidPathHint(component: "..").contains(".."))
    }

    @Test("⚠️ 重命名的四种结局是**四句不同的话**（成功 / 已存在 / 一半 / 源没了）")
    func renameOutcomeMessagesAreDistinct() {
        let messages = [
            FileCopy.renamedToast(newPath: "docs/b.md"),
            FileCopy.renameDestinationExistsHint,
            FileCopy.renamePartiallyMovedToast,
            FileCopy.renameSourceGoneHint,
        ]
        for (index, lhs) in messages.enumerated() {
            for rhs in messages[(index + 1)...] { #expect(lhs != rhs) }
        }
        #expect(FileCopy.renamedToast(newPath: "docs/b.md").contains("docs/b.md"))
        #expect(FileCopy.renamePartiallyMovedToast == "新路径已写入，原路径仍在")
    }

    @Test("⚠️「源不在了」与「源写不了」必须分开说 —— 后者把**还在那里**的文件说成已不存在")
    func renameSourceIssuesAreDistinct() {
        #expect(FileCopy.renameSourceGoneHint != FileCopy.renameSourceNotWritableHint)
        #expect(FileCopy.renameSourceNotWritableHint.contains("网页端"), "做不了要给出路")
        #expect(!FileCopy.renameSourceNotWritableHint.contains("已不存在"))
    }

    @Test("§5.17 删除：标题、说明带分支、按钮、警告、两条结果")
    func deleteSheetCopy() {
        #expect(FileCopy.deleteSheetTitle(fileName: "a.md") == "删除「a.md」？")
        #expect(FileCopy.deleteSheetHint(branch: "feature/x").contains("feature/x"))
        #expect(FileCopy.deleteSheetHint(branch: "feature/x").contains("提交"))
        #expect(FileCopy.deleteConfirmAction == "删除文件")
        #expect(FileCopy.deleteWarning.contains("不可撤销"))
        #expect(FileCopy.deletedToast(fileName: "a.md") == "已删除 a.md")
        #expect(FileCopy.alreadyGoneHint == "该文件已不存在")
    }

    @Test("⚠️「已删除」与「已不存在」是两句话 —— 后者不是失败，不能共用一句")
    func deleteOutcomeMessagesAreDistinct() {
        #expect(FileCopy.deletedToast(fileName: "a.md") != FileCopy.alreadyGoneHint)
        // ⚠️ 删除成功那句带着文件名，而"已不存在"那句不带 ——
        //    后者是现取 sha 时才发现的状态，那一刻我们并不确定名字对不对。
        #expect(FileCopy.deletedToast(fileName: "a.md").contains("a.md"))
    }

    // MARK: - 409 的分类（与合并分支的 409 不共用常量）

    @Test("⚠️ 写通道的 409 与合并分支的 409 **不同源**：前者是版本过期，后者是内容冲突")
    func writeConflictDoesNotShareCopyWithMergeConflict() {
        // 合并分支那一句说的是"到网页端处理冲突"，而写通道这一句说的是"选一版"。
        // 两者互换会让用户在一个只要点一下的地方被送去网页端，或反过来。
        #expect(FileWriteFailure(.conflict).message == CommitSheetCopy.conflictHint)
        #expect(FileWriteFailure(.conflict).message != BranchCopy.mergeConflictHint)
        #expect(FileWriteFailure(.conflict).message != PullCopy.mergeConflictToast)
    }

    @Test("404 与其余错误的文案**不在这里给** —— 各入口的下一句不一样（有意为 `nil`）")
    func notFoundAndOtherHaveNoSharedMessage() {
        #expect(FileWriteFailure(.notFound).message == nil)
        #expect(FileWriteFailure(.forbidden("x")).message == nil)
        #expect(FileWriteFailure(.forbidden("x")) == .other(.forbidden("x")))
        #expect(FileWriteFailure(.rateLimited(resetAt: Date(timeIntervalSince1970: 0), isSecondary: false))
            == .other(.rateLimited(resetAt: Date(timeIntervalSince1970: 0), isSecondary: false)))
    }
}
