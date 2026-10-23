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
        /// 选分支（从选目录那一屏进去）。
        case chooseBranch
        /// 新建目录（在选目录那一屏进去）。
        case newDirectory
    }

    private(set) var page: Page = .main

    /// 弹层内部的**页栈**（“返回”回到上一页）。
    ///
    /// ⚠️ 它是**自己的数组**，不是一条 `NavigationStack`（理由见 `UploadImageSheet` 的类型说明）。
    private var pageStack: [Page] = []

    /// 去某一屏（把当前那一屏记下来，“返回”回得来）。
    func show(_ page: Page) {
        pageStack.append(self.page)
        self.page = page
    }

    /// 去某一屏，并把页栈**重置**成 [base]。
    ///
    /// ⚠️ 用在“一串连动”上：选完仓库 → 去选目录，
    /// 那时“返回”应该回**首屏**，而不是回“选仓库”那一屏
    /// （仓库已经定下来了，再回去重选一遍是倒退）。
    func show(_ page: Page, after base: Page) {
        pageStack = [base]
        self.page = page
    }

    /// 回上一屏；没有上一屏就回首屏。
    func back() {
        page = pageStack.popLast() ?? .main
    }

    /// 回**首屏**并清空页栈（选完了：目标定下来了，不该再“返回”到选目录那一屏）。
    func showRoot(_ page: Page) {
        pageStack.removeAll()
        self.page = page
    }

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

    // MARK: - 分支

    /// 该仓库的分支列表（选分支那一屏用）。
    private(set) var branches: [BranchSummary] = []
    private(set) var isLoadingBranches = false

    // MARK: - 新建目录

    /// 新目录的名字（用户输入，**只填一段**）。
    var newDirectoryName: String = ""
    private(set) var newDirectoryFailure: String?

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
    ///
    /// ## ⚠️ **“查不到” ≠ “不存在”**（这一条是这一整个方法的关键）
    ///
    /// 只有 **404** 才算“它没了”；
    /// 401（令牌失效）/ 5xx / 断网 只是**这一次没查成** ——
    /// 拿“查不到”当“没了”，表现就是**用户明明选过目标，重开却说没选过**。
    /// （同 `BranchResolver` 的口径：无法验证 ≠ 什么都不存在。）
    private func facts(for target: UploadTarget) async -> UploadTargetFacts {
        // ① 仓库 + 默认分支（`GET /repos/{o}/{r}` ⇒ 404 = 仓库没了）
        let detail: RepositoryDetail
        do {
            detail = try await detailLoader.repository(fullName: target.fullName)
        } catch let error as GitHubError {
            guard case .notFound = error else {
                // ⚠️ 查不成 ⇒ **当作还在**（保持目标能用），让上传那一步去报真实的错。
                return UploadTargetFacts(
                    repositoryExists: true,
                    directoryExists: true,
                    branchExists: true,
                    defaultBranch: target.branch
                )
            }
            return UploadTargetFacts(
                repositoryExists: false,
                directoryExists: false,
                branchExists: false,
                defaultBranch: ""
            )
        } catch {
            return UploadTargetFacts(
                repositoryExists: true,
                directoryExists: true,
                branchExists: true,
                defaultBranch: target.branch
            )
        }

        // ② 分支还在不在（列表取不到 ⇒ **按“无法验证”处理**，不当作不存在 ——
        //    网络抖一下就清掉用户的记忆值，那清掉是写盘、不会自愈）。
        let branchExists: Bool
        do {
            let list = try await branchesLoader.load(fullName: target.fullName)
            // ⚠️ **列表不完整时不能判“没了”**：服务端还有下一页（`hasMore`），
            //    我们的分支可能就在下一页里 ⇒ 那样会把一个还在的分支清掉。
            branchExists = list.hasMore || list.branches.isEmpty
                ? true
                : list.branches.contains { $0.name == target.branch }
        } catch {
            branchExists = true
        }

        // ③ 目录还在不在（取那一层的清单 ⇒ 404 = 目录没了）
        let directoryExists: Bool
        if target.directory.isRoot {
            directoryExists = true
        } else {
            do {
                _ = try await treeLoader.load(
                    fullName: target.fullName,
                    path: target.directory,
                    remembered: target.branch,
                    defaultBranch: detail.defaultBranch
                )
                directoryExists = true
            } catch let error as GitHubError {
                // ⚠️ 只有 404 算“目录没了”；其余（401 / 5xx / 断网）只是没查成。
                if case .notFound = error {
                    directoryExists = false
                } else {
                    directoryExists = true
                }
            } catch {
                directoryExists = true
            }
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
        show(.chooseRepository)
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
        show(.chooseDirectory, after: .main)
        // ⚠️ **选了仓库就写回记忆**（口径：改了就写回）——
        //    不等"目录也确认了"：用户挑完仓库就退出去，也是他选过的目标。
        await rememberCurrentTarget()
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
        showRoot(.main)
        // ⚠️ 改了目标**立刻写回记忆**（2026-10-23 定的口径）——
        //    不写回的话"下次直接上传"用的还是上一次那个目标。
        Task { await rememberCurrentTarget() }
    }

    // MARK: - 分支

    /// 去选分支（从选目录那一屏进去）。
    func startChoosingBranch() async {
        show(.chooseBranch)
        guard let target else { return }
        isLoadingBranches = true
        defer { isLoadingBranches = false }
        do {
            branches = try await branchesLoader.load(fullName: target.fullName).branches
        } catch {
            branches = []
        }
    }

    /// 换一条分支 ⇒ 重取那一层的目录（不同分支的目录内容不同）。
    func pickBranch(_ name: String) async {
        guard let target else { return }
        self.target = UploadTarget(
            fullName: target.fullName,
            directory: target.directory,
            branch: name
        )
        show(.chooseDirectory, after: .chooseDirectory)
        await loadDirectories(at: target.directory)
        await rememberCurrentTarget()
    }

    // MARK: - 新建目录

    /// 去新建目录。
    func startNewDirectory() {
        newDirectoryName = ""
        newDirectoryFailure = nil
        show(.newDirectory)
    }

    /// 用刚输入的名字作为新目录。
    ///
    /// ## ⚠️ 它**不会**先建目录 —— GitHub 的 `PUT /contents` **不能建空目录**
    /// （§5.8）。新目录是**随文件一起产生**的：这一格只是把落点改成那个路径。
    func chooseNewDirectory() {
        guard let target else { return }
        let name = newDirectoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        // ⚠️ **只填一段**：多级路径（`2026/10`）要一层层进，不能一口气填 ——
        //    那一格的语义是"在当前这一层下面建一个目录"。
        guard RepoPath.isValidComponent(name) else {
            newDirectoryFailure = UploadImageCopy.invalidDirectoryName
            return
        }
        guard let path = browsingPath.appending(name) else {
            newDirectoryFailure = UploadImageCopy.invalidDirectoryName
            return
        }
        self.target = UploadTarget(
            fullName: target.fullName,
            directory: path,
            branch: target.branch
        )
        showRoot(.main)
        Task { await rememberCurrentTarget() }
    }

    /// 把当前目标写回记忆。
    private func rememberCurrentTarget() async {
        guard let target else { return }
        await memory.remember(target)
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
    ///
    /// ⚠️ 回到首屏时**清空页栈** —— 从「选仓库」退出来之后，
    /// 再点那一行进「选目录」，返回键不应该先退到「选仓库」。
    func backToMain() {
        showRoot(.main)
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
            // ⚠️ **把上一张清掉**：用户是来“换一张”的，换失败却还留着旧的，
            //    界面上就变成“选了新图、其实用的还是旧的”。
            //    （压不下来 / 动图 / 不是图片 ⇒ 同一句提示：用户能做的动作是同一个。）
            draft = nil
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
