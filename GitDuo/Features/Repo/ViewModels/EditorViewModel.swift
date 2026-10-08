import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 编辑器页（PRD §4.6、TECH_SPEC §9.6）的状态。
///
/// ## 它必须弄对的一件事：**"读到的那一版"就是提交时的基准**
///
/// 决策 #64：编辑模式下，进页面那一次 `GET /contents/{path}` 同时给两样东西 ——
/// 编辑区的**初值**与提交时要带的 `sha`。两者**必须同源**：
/// 在提交前现取一个新 `sha`（哪怕只差一秒）会让并发改动**永远撞不上 409** ——
/// 也就是把乐观锁的报警器拆掉（完整推演见 `SaveFile` 的类型说明）。
///
/// 所以本类型**只在 `prepare()` 里读一次**，把 `blobSHA` 存进 `baseSHA`、之后一律用它。
/// 唯一的例外是 409 之后用户主动选的那两条路（强制覆盖 / 查看最新版之后重提）——
/// 那时基准换成**用户看过**的那一版（`submit(_:using:)` 的 `overrideSHA`），这是有意的。
///
/// ## ⚠️ 新建模式**不读内容**，`baseSHA` 恒为 `nil`
///
/// `nil` ⇒ 数据层按"新建"发（`sha` 整条键不写，不是写 `null`）。
/// 那条路径上已有同名文件时服务端回 **422**，文案是
/// `CommitSheetCopy.destinationExistsHint` —— **不静默覆盖**（决策 #70⑤）。
///
/// ## ⚠️ 分支解析同 `FileViewModel`，且是**同一份判据**
///
/// 说明行里那句 `· 分支 {当前分支}`、提交时带的 `branch`、以及两处网页端出口
/// 都要它。走 `BranchResolver.initial` 而不是自己写 if：那一句话是产品口径
/// （§9.4.1 表第三行"无记忆 ⇒ 直接用默认分支"），只有一个落点。
@MainActor
@Observable
final class EditorViewModel {

    // MARK: - 输入（进页面时定下）

    let mode: EditorMode

    let fullName: String

    /// 编辑模式那个文件（路由带进来的）；**新建模式为 `nil`**。
    let editingPath: RepoPath?

    /// 新建模式的路径输入框 —— 预填 `EditorCopy.defaultNewFilePath`（§4.6）。
    ///
    /// ⚠️ 它装的是**真值**不是占位符：用户不改就能直接提交（PRD §4.6 的更新）。
    var newFilePath: String

    /// 编辑区正文。
    ///
    /// 新建模式初值**空**；编辑模式初值是该文件的当前内容（PRD §4.6 那张表逐字）。
    var text = ""

    // MARK: - 状态

    /// 首屏态。
    ///
    /// 编辑模式 = "解析分支 + 读一次内容"；新建模式 = **只有解析分支**
    /// （紧接着 `succeed(())`，于是新建模式永远不会停在骨架屏上）。
    private(set) var load: LoadState<Void> = .idle

    /// 本次用的分支（说明行、提交、网页端出口都要它）。
    private(set) var branch: String?

    /// 乐观锁基准 —— **进页面那一次读到的**那一版（决策 #64）。新建模式恒 `nil`。
    private(set) var baseSHA: String?

    // MARK: - 依赖

    private let loader: LoadFileContent
    private let detailLoader: LoadRepoDetail
    private let memory: any BranchMemoryStore
    private let saver: SaveFile

    /// 默认分支的缓存（回落值与 `ref` 为空时的兜底都要它）。
    private var defaultBranch: String?

    init(
        fullName: String,
        mode: EditorMode,
        path: RepoPath?,
        loader: LoadFileContent,
        detail: LoadRepoDetail,
        memory: any BranchMemoryStore,
        saver: SaveFile
    ) {
        self.fullName = fullName
        self.mode = mode
        self.editingPath = path
        self.newFilePath = EditorCopy.defaultNewFilePath
        self.loader = loader
        self.detailLoader = detail
        self.memory = memory
        self.saver = saver
    }

    // MARK: - 取数

    func start() async {
        guard !load.hasFinished else { return }
        await prepare()
    }

    /// 失败页那个「重试」。
    func retry() async {
        await prepare()
    }

    private func prepare() async {
        load.begin()

        // ── 分支先定：它在编辑模式下是"读哪一版"的输入，在新建模式下也要给说明行。
        let ref: String
        do {
            ref = try await currentRef()
        } catch {
            load.fail(Self.failure(from: error))
            return
        }
        branch = ref

        // ── 新建模式到此为止（它一个内容请求都不发）。
        guard mode.loadsExistingContent, let path = editingPath else {
            load.succeed(())
            return
        }

        // ── 编辑模式：这一次读**同时**给编辑区初值与乐观锁基准（见类型说明）。
        do {
            let outcome = try await loader.load(fullName: fullName, path: path, ref: ref)
            guard let content = outcome.content, let body = content.text else {
                // ⚠️ 正常路上**到不了这里**（§4.5 的「编辑」只在 ≤1MB 的文本文件上可点），
                //    但服务端行为变了时不能让编辑器画出一个**空**编辑区 ——
                //    用户会以为这个文件本来就是空的，然后把内容写进去、覆盖掉原件。
                load.fail(.decoding(EditorContentIssue.notText))
                return
            }
            text = body
            baseSHA = content.blobSHA
            load.succeed(())
        } catch {
            load.fail(Self.failure(from: error))
        }
    }

    /// 本次要用的 `ref`：记忆值优先，没有记忆就用默认分支（§9.4.1 表第三行）。
    private func currentRef() async throws -> String {
        let remembered = await memory.branch(for: fullName)
        return BranchResolver.initial(
            remembered: remembered,
            defaultBranch: try await defaultBranchName()
        )
    }

    private func defaultBranchName() async throws -> String {
        if let cached = defaultBranch { return cached }
        let detail = try await detailLoader.repository(fullName: fullName)
        defaultBranch = detail.defaultBranch
        return detail.defaultBranch
    }

    // MARK: - 给视图的两处派生

    /// 导航标题要的那个"文件名"。
    ///
    /// ⚠️ 新建模式给的是**路径框的预填值**而不是 `editingPath`（它是 `nil`）——
    /// 而 `EditorCopy.navigationTitle(mode:fileName:)` 在新建模式下会忽略这个参数、
    /// 直接返回同一个常量。这里给什么都不会错，但给"预填值"是为了
    /// 万一将来那条规则改了，两处仍然同源。
    var navigationFileName: String {
        editingPath?.displayName ?? EditorCopy.defaultNewFilePath
    }

    // MARK: - 提交

    /// 执行一次提交（§5.9 弹层点「提交」时调用）。
    ///
    /// - Parameter overrideSHA: 本次要用的版本基准；`nil` = 用进页面读到的那个。
    ///   **两个出口都传 409 时取回的那个 sha** —— "强制覆盖"与"查看最新版之后重提"
    ///   在这里是同一个动作（用户已经看过远端那一版了），差别只在弹层那边
    ///   给不给他看那一眼、以及要不要二次确认。
    func submit(_ draft: CommitDraft, using overrideSHA: String? = nil) async -> CommitAttempt {
        // ── ① 目标路径。新建模式由输入框解析（校验收在 `RepoPath.resolveNewFile`）。
        let path: RepoPath
        if let editingPath {
            path = editingPath
        } else {
            switch RepoPath.resolveNewFile(input: newFilePath) {
            case let .acceptable(resolved): path = resolved
            case let .rejected(issue): return .rejected(EditorCopy.pathHint(for: issue))
            }
        }

        // ── ② 本地判据：超过 Contents 的写上限 ⇒ **一个请求都不发**。
        //    §5.8 明写"提示并引导网页端，**不静默失败**"。先拦在这里是为了不让用户
        //    白等一次注定 422 的往返 —— 而那句话（`tooLargeHint`）本来就是给这一档的。
        let bytes = Data(text.utf8)
        guard bytes.count <= SaveFile.maxContentBytes else {
            return .rejected(CommitSheetCopy.tooLargeHint)
        }

        guard let branch else { return .rejected(ActionCopy.failed) }

        do {
            let outcome = try await saver.run(
                fullName: fullName,
                path: path,
                content: bytes,
                draft: draft,
                sha: overrideSHA ?? baseSHA,
                currentBranch: branch
            )
            // ⚠️ 写成功之后基准要换成**新** blob 的 sha（`FileSaveReceipt.blobSHA`）——
            //    不换的话，用户接着改第二次会拿着**第一次之前**的基准去更新，
            //    服务端回 409，而屏幕上看起来是"刚提交成功、再提交就说被人改过了"。
            if let receipt = outcome.receipt { baseSHA = receipt.blobSHA }
            return .settled(outcome)
        } catch let error as BranchCreationError {
            // 分支名不合法是**表单校验**、不是网络错误 —— 那句话显示在原位
            //（照 `BranchesViewModel` 对同一个错误的处置）。
            return .rejected(error.message)
        } catch {
            let failure = FileWriteFailure(Self.failure(from: error))
            guard failure == .conflict else {
                return .rejected(failure.message ?? ActionCopy.failed)
            }

            // ── 409：两个出口（查看最新版 / 强制覆盖）都要求"远端最新版"，先取回来。
            guard let latest = await latestVersion(of: path, ref: branch) else {
                // 取最新版**本身**失败了 ⇒ 两个出口都拿不到依据，退回"留在原地"、
                // 把 409 那句话再说一遍（用户再点一次就是）。
                return .rejected(CommitSheetCopy.conflictHint)
            }
            return .conflict(latest)
        }
    }

    /// 409 之后取回的"远端最新版"（§5.9③）。
    ///
    /// ⚠️ 取不到就返回 `nil`、**不抛** —— 调用方要据此决定"两个出口能不能换出来"，
    /// 而那是一个正常的判断（网络此刻不好），不是一次失败。
    private func latestVersion(of path: RepoPath, ref: String) async -> RemoteLatest? {
        guard let outcome = try? await loader.load(fullName: fullName, path: path, ref: ref),
              let content = outcome.content
        else { return nil }
        return RemoteLatest(sha: content.blobSHA, text: content.text)
    }

    // MARK: - 错误归一化

    /// 把任意错误收敛成 `GitHubError`（同其余 ViewModel：映射失败归 `.decoding`，
    /// **不是** `.transport` —— 后者会让界面给出"检查网络"的错误引导）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}

/// 编辑器拿到的内容不是可编辑的文本。
///
/// ⚠️ 正常路上**到不了**（§4.5 的「编辑」只在 ≤1MB 的文本文件上可点）。
/// 它存在是为了让"不该打开编辑器时打开了一个空编辑区"变成一个可见的失败，
/// 而不是一次静默的数据事故（用户会把内容写进一个他根本没看到过的文件）。
private enum EditorContentIssue: Error {
    case notText
}
