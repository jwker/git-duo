import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 「上传图片」弹层的状态（全局悬浮按钮 → 弹层 → 目标 → 选图 → 提交 → 成功）。
///
/// ## ⚠️ 它**不持有**目标以外的东西
///
/// 目标（仓库 + 目录 + 分支）是**一整份**（`UploadTarget`）——
/// 拆成三个字段就会出现"仓库换了、目录没换"这种组合，而那正是写操作里最不该有的状态。
///
/// ## ⚠️ 判据都在领域层
///
/// 目标怎么回落（仓库没了 / 目录没了 / 分支没了）由 `UploadTargetResolver` 判，
/// 路径怎么拼由 `UploadTargetPath` 拼 —— 本类型只负责**取事实**与**转述**（铁律 #14）。
@MainActor
@Observable
final class UploadImageViewModel {

    // MARK: - 页面（弹层内部的三屏）

    /// 弹层内部的三屏。⚠️ 用**枚举**而不是三个 `Bool` ——
    /// 三屏互斥，两个布尔量能同时为真。
    enum Page: Equatable {
        /// 首屏：目标摘要 + 图片 + 提交信息。
        case main
        /// 选仓库（从摘要行那一行进去）。
        case chooseRepository
        /// 选目录（挑完仓库进去）。
        case chooseDirectory
    }

    private(set) var page: Page = .main

    // MARK: - 目标

    /// 本次要写进哪里。`nil` = 还没选目标（首屏那一行显示「尚未选择目标」）。
    private(set) var target: UploadTarget?

    /// 正在解目标（读上下文 / 记忆 + 校验）。
    private(set) var isResolving = true

    // MARK: - 选仓库

    private(set) var repositories: [Repository] = []
    private(set) var isLoadingRepositories = false
    private(set) var repositoryFailure: String?

    // MARK: - 选目录

    /// 当前浏览到的那一层的目录清单（**只留目录**，文件不列 ——
    /// 这一屏只回答"写到哪一层目录"，文件是另一件事）。
    private(set) var directories: [TreeEntry] = []
    private(set) var browsingPath: RepoPath = .root
    private(set) var isLoadingDirectories = false
    private(set) var directoryFailure: String?

    // MARK: - 图片

    /// 已经压好 / 转好码的字节（`nil` = 还没选图）。
    private(set) var draft: UploadDraft?
    private(set) var isPreparing = false
    private(set) var preparationFailure: String?

    // MARK: - 提交

    /// 提交信息（用户输入；空则用默认信息 —— `CommitDraft.effectiveMessage` 那一档）。
    var message: String = ""

    private(set) var isSubmitting = false
    private(set) var submitFailure: String?

    /// 上传成功后**复制出去**的那串路径（带仓库名）。
    private(set) var uploadedPath: String?

    /// 当前目标所在仓库的**默认分支**（取目录那一档的回落基准）。
    ///
    /// ⚠️ 它与 `target.branch` **不是一回事**：后者是"写在哪条分支上"，
    /// 前者是"那条分支没了该回落到哪"。把它当成同一个值传下去，
    /// `LoadRepoTree` 的静默回落就会拿同一条分支重发一次（而那条已经不存在了）。
    private var defaultBranch: String = "main"

    // MARK: - 依赖

    private let repositoriesLoader: LoadRepositoriesPage
    private let detailLoader: LoadRepoDetail
    private let branchesLoader: LoadBranches
    private let treeLoader: LoadRepoTree
    private let saver: SaveFile
    private let intake: UploadIntake
    private let memory: any UploadTargetStore
    private let context: UploadContextStore
    private let toast: ToastCenter

    init(
        repositories: LoadRepositoriesPage,
        detail: LoadRepoDetail,
        branches: LoadBranches,
        tree: LoadRepoTree,
        saver: SaveFile,
        intake: UploadIntake,
        memory: any UploadTargetStore,
        context: UploadContextStore,
        toast: ToastCenter
    ) {
        self.repositoriesLoader = repositories
        self.detailLoader = detail
        self.branchesLoader = branches
        self.treeLoader = tree
        self.saver = saver
        self.intake = intake
        self.memory = memory
        self.context = context
        self.toast = toast
    }

    // MARK: - 生命周期

    /// 弹层出现：**解目标**。
    ///
    /// ## ⚠️ 顺序：上下文优先，其次记忆
    ///
    /// 上下文（用户此刻站在哪个仓库的哪一层）比记忆更贴近"他现在想传到哪" ——
    /// 而按钮是全局的，拿记忆会在他站在 A 仓库时把图传到 B 仓库（2026-10-23 定的口径）。
    func start() async {
        guard isResolving else { return }
        let contextTarget = await context.current()
        let remembered = await memory.target()

        if let contextTarget {
            // 上下文**不需要网络校验**：它就是当前页面上的那个仓库。
            target = await fillingBranch(contextTarget)
            isResolving = false
            return
        }

        guard let remembered else {
            isResolving = false
            return
        }

        // 记忆要**校验**（仓库可能改名、目录可能被删、分支可能被删）⇒ 三个事实各查一次。
        let facts = await facts(for: remembered)
        defaultBranch = facts.defaultBranch
        target = UploadTargetResolver.resolve(
            remembered: remembered,
            context: nil,
            facts: facts
        )
        isResolving = false
    }

    /// 上下文那一档的分支可能是空的（仓库首页不知道分支）⇒ 拿默认分支补上。
    ///
    /// ⚠️ 只补**空**的：已经解析出来的分支不动（用户可能就在别的分支上）。
    private func fillingBranch(_ target: UploadTarget) async -> UploadTarget {
        guard target.branch.isEmpty else { return target }
        let branch = (try? await detailLoader.repository(fullName: target.fullName))?.defaultBranch
            ?? "main"
        return UploadTarget(
            fullName: target.fullName,
            directory: target.directory,
            branch: branch
        )
    }

    /// 查三个事实：仓库还在不在、目录还在不在、分支还在不在，以及当前默认分支。
    private func facts(for target: UploadTarget) async -> UploadTargetFacts {
        // ① 仓库 + 默认分支（`GET /repos/{o}/{r}` ⇒ 404 = 仓库没了）
        guard let detail = try? await detailLoader.repository(fullName: target.fullName) else {
            return UploadTargetFacts(
                repositoryExists: false,
                directoryExists: false,
                branchExists: false,
                defaultBranch: ""
            )
        }

        // ② 分支还在不在（列表取不到 ⇒ **按"无法验证"处理**，不当作不存在 ——
        //    网络抖一下就清掉用户的记忆值，那清掉是写盘、不会自愈）。
        let availableBranches: [String]
        if let list = try? await branchesLoader.load(fullName: target.fullName) {
            availableBranches = list.branches.map(\.name)
        } else {
            availableBranches = []
        }
        let branchExists = availableBranches.isEmpty
            ? true
            : availableBranches.contains(target.branch)

        // ③ 目录还在不在（取那一层的清单 ⇒ 404 = 目录没了）
        let directoryExists: Bool
        if target.directory.isRoot {
            directoryExists = true
        } else {
            directoryExists = (try? await treeLoader.load(
                fullName: target.fullName,
                path: target.directory,
                remembered: target.branch,
                defaultBranch: detail.defaultBranch
            )) != nil
        }

        return UploadTargetFacts(
            repositoryExists: true,
            directoryExists: directoryExists,
            branchExists: branchExists,
            defaultBranch: detail.defaultBranch
        )
    }

    // MARK: - 改目标

    /// 去选仓库（从摘要行那一行进去）。
    func startChoosingRepository() async {
        page = .chooseRepository
        repositoryFailure = nil
        guard repositories.isEmpty else { return }
        isLoadingRepositories = true
        defer { isLoadingRepositories = false }
        do {
            let page = try await repositoriesLoader.load(source: .repos)
            // ⚠️ **只列可写的**（铁律 #7：可写性唯一来源 = `permissions.push`）——
            //    列一个写不上去的仓库，用户挑完才发现是死路。
            repositories = page.items.filter(\.canWrite)
        } catch {
            repositoryFailure = ActionCopy.failed
        }
    }

    /// 挑了一个仓库 ⇒ 目标落它，分支取它的默认分支，然后去选目录。
    func pickRepository(_ repository: Repository) async {
        let detail = try? await detailLoader.repository(fullName: repository.fullName)
        let branch = detail?.defaultBranch ?? "main"
        defaultBranch = branch
        target = UploadTarget(
            fullName: repository.fullName,
            directory: .root,
            branch: branch
        )
        browsingPath = .root
        page = .chooseDirectory
        await loadDirectories(at: .root)
    }

    /// 选目录那一屏：进下一层。
    func browse(_ entry: TreeEntry) async {
        await loadDirectories(at: entry.path)
    }

    /// 选目录那一屏：回到上一层。
    func browseUp() async {
        let up = browsingPath.deletingLastComponent()
        await loadDirectories(at: up)
    }

    /// 选目录那一屏：就选当前这一层。
    func chooseCurrentDirectory() {
        guard let target else { return }
        self.target = UploadTarget(
            fullName: target.fullName,
            directory: browsingPath,
            branch: target.branch
        )
        page = .main
        // ⚠️ 改了目标**立刻写回记忆**（2026-10-23 定的口径）——
        //    不写回的话"下次直接上传"用的还是上一次那个目标。
        Task { await memory.remember(self.target!) }
    }

    /// 选目录那一屏：取那一层的目录清单。
    private func loadDirectories(at path: RepoPath) async {
        guard let target else { return }
        browsingPath = path
        directoryFailure = nil
        isLoadingDirectories = true
        defer { isLoadingDirectories = false }
        do {
            let page = try await treeLoader.load(
                fullName: target.fullName,
                path: path,
                remembered: target.branch,
                // ⚠️ 回落基准是**默认分支**，不是当前那条分支 ——
                //    两者给成同一个值时，`LoadRepoTree` 的静默回落会拿同一条（已失效的）分支重发一次。
                defaultBranch: defaultBranch
            )
            directories = page.entries.filter { $0.kind == .directory }
        } catch {
            directories = []
            directoryFailure = ActionCopy.failed
        }
    }

    /// 回到首屏（不选目标，只是"算了"）。
    func backToMain() {
        page = .main
    }

    // MARK: - 选图

    /// 收到一张选中的图片的**字节** ⇒ 压缩 / 转码。
    ///
    /// ## ⚠️ 它收**字节**，不收 `PhotosPickerItem`
    ///
    /// 相册选择器是**系统视图**，它的 item 类型属于 `PhotosUI` ——
    /// 那是表现层的东西，ViewModel 不该 import 它。
    /// ⇒ 视图那一侧取字节、取文件名（`UploadFileName.photo`），把两样交给这里。
    func prepare(data: Data, fileName: String) async {
        preparationFailure = nil
        isPreparing = true
        defer { isPreparing = false }

        let outcome = await intake.prepare(data, fileName: fileName)
        switch outcome {
        case let .accepted(finalName, prepared, adjustment):
            draft = UploadDraft(
                source: .uploadImage,
                fileName: finalName,
                data: prepared,
                adjustment: adjustment
            )
        case .tooLarge:
            // 压不下来 / 动图 / 不是图片 ⇒ 同一句提示（用户能做的动作是同一个）。
            preparationFailure = CommitSheetCopy.tooLargeHint
        }
    }

    // MARK: - 提交

    /// 能不能提交：目标与图都在，且不在途。
    var canSubmit: Bool {
        target != nil && draft != nil && !isSubmitting
    }

    /// 提交：写文件 + 生成一条提交。
    func submit() async {
        guard let target, let draft else { return }
        isSubmitting = true
        submitFailure = nil
        defer { isSubmitting = false }

        // 落点：**目标目录 + 文件名**（目录那一格是仓库内的相对路径）。
        // ⚠️ `resolveUpload` 走的是「新建 / 重命名 / 上传落点」三条通道**唯一**的那份解析
        //    （它会校验"文件名必须是单独一段"）—— 不在这里另拼一次路径。
        guard case let .acceptable(path) = RepoPath.resolveUpload(
            directory: target.directory,
            fileName: draft.fileName
        ) else {
            submitFailure = ActionCopy.failed
            return
        }

        let commit = CommitDraft(message: message, target: .currentBranch, source: .uploadImage)
        do {
            let outcome = try await saver.run(
                fullName: target.fullName,
                path: path,
                content: draft.data,
                draft: commit,
                // 新建：**不带 `sha`**（决策 #70⑤：同名已存在时服务端回 422，不静默覆盖）。
                sha: nil,
                currentBranch: target.branch
            )
            guard case .committedToCurrentBranch = outcome else {
                // 「做到一半」那几档（建了分支没提交 / 提交了没建 PR）在这个出口上不可能发生
                // —— 目标恒为当前分支 —— 但**不猜**：真发生了就如实报失败。
                submitFailure = ActionCopy.failed
                return
            }
            // 成功：记住这个目标（下次直接上传用的就是它）。
            await memory.remember(target)
            uploadedPath = UploadTargetPath.displayPath(
                fullName: target.fullName,
                directory: target.directory,
                fileName: draft.fileName
            )
        } catch let error as BranchCreationError {
            submitFailure = error.message
        } catch {
            let failure = FileWriteFailure(Self.failure(from: error))
            submitFailure = failure.message ?? ActionCopy.failed
        }
    }

    /// 成功态之后：再来一张（目标留着，图片清掉）。
    func uploadAnother() {
        draft = nil
        uploadedPath = nil
        message = ""
    }

    /// 错误归一化（与 `RepoCodeViewModel` 同一口径）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}
