import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit
import UIKit

/// 文件查看页（PRD §4.5）的状态。
///
/// ## 它只有一件事要做对：把「三档降级」的结局如实搬到屏幕上
///
/// 判定与取数都在 `LoadFileContent` 里（领域层，有单测）。本类型只负责把
/// `FileViewOutcome` 的三档翻成三块**不同**的界面 —— 而它们必须不同：
/// - `.content` ⇒ 代码块（或图片）
/// - `.unsupported` ⇒ 「无法预览」+ 跳网页端出口（**没下载**）
/// - `.undecodable` ⇒ 「编码不认识」（**下载了**，但解不出来）
///
/// 后两者合成一块的后果在 `FileViewOutcome` 的说明里写了：总有一边的文案是假话。
///
/// ## ⚠️ 用哪个 `ref`：本类型自己解析，**不从路由接**
///
/// 原型这一屏用的是 `curBranch()` —— 也就是"该仓库当前的记忆分支"。
/// 本 App 的对应物是 `BranchMemoryStore`（没有记忆时回落该仓库的默认分支），
/// 而这条路与 `RepoDetailView` 用的是**同一个** `BranchResolver.initial`，
/// 所以两个页面在正常情况下算出来的是同一条分支。
///
/// 为什么不把已解析的分支经路由传进来：`Route.fileView` 只有
/// `fullName` / `path` / `readOnly` 三个参数（§8.2 正本），而这一屏也可能是从
/// 分支管理页、或从任何"当时没有仓库详情在手"的入口点进来的。
/// 让路由少带一个"上一个页面恰好知道"的值，这一屏才能自己站住。
///
/// ⚠️ 代价是"没有记忆"时会多问一次 `GET /repos/{owner}/{repo}`（只为拿
/// `defaultBranch`）。**但那次请求几乎必然命中 ETag 缓存**：用户是从仓库详情页
/// 点进来的，而它刚刚用**同一个地址、同一组请求头**取过头部 ⇒ 304、不计配额。
@MainActor
@Observable
final class FileViewModel {

    private(set) var outcome: LoadState<FileViewOutcome> = .idle

    /// 本次取数实际用的分支 —— 面包屑显示它、`Raw` 之外的网页端出口也用它。
    private(set) var branch: String?

    /// 有写操作（重命名 / 删除）在途 ⇒ 弹层里的确认按钮转圈、再点也没有第二次（§8.5「操作类」）。
    ///
    /// ⚠️ 与 `BranchesViewModel.isWorking` 同一条：两个写入口共用一个仓库的状态，
    /// 允许并发只会造出"一边在改名、一边在删除同一个路径"这种没人能说清的结果。
    private(set) var isWorking = false

    /// 当前呈现的弹层（§5.15–§5.17 三张）。
    ///
    /// ⚠️ **一个 `Identifiable` 枚举，不是三个布尔量**（同 `BranchesViewModel` /
    /// `RepoDetailView` 的说明）：文件操作菜单里的两个动作各自要**换成**另一张弹层
    /// （§5.16 / §5.17），用布尔量表达就是"关一张、开一张"，而它中间的那一帧是空屏。
    var sheet: SheetRoute?

    /// 本页的弹层路由。
    enum SheetRoute: Identifiable, Hashable, Sendable {
        case operations
        case rename
        case delete

        var id: String {
            switch self {
            case .operations: "operations"
            case .rename: "rename"
            case .delete: "delete"
            }
        }
    }

    private let loader: LoadFileContent
    private let detailLoader: LoadRepoDetail
    private let memory: any BranchMemoryStore
    private let renamer: RenameFile
    private let deleter: DeleteFile
    private let toast: ToastCenter

    let fullName: String

    /// 当前显示的路径。
    ///
    /// ⚠️ 它是 `var` 而不是 `let`，只为一件事：**重命名之后这一页要跟着换路径**
    /// （PRD §5.16「返回文件查看页（该页路径跟着变）」）。
    /// 做法是改本字段 + 重取一次内容，**不动导航栈** —— 换路由（pop + push 或
    /// 替换栈顶）会让"挂着弹层的那一页"先消失，表现是弹层被突然掀掉。
    /// 而这一页本来就只是"某个路径的内容"，路由上那一份是**进来时**的参数。
    private(set) var path: RepoPath

    /// 只读（他人仓库）—— 决定按钮行画哪一组（§4.5 的权限差异表）。
    let readOnly: Bool

    /// 目录行带的元数据。`nil` = 调用方不知道（从提交详情点进来时就是这样）。
    private let size: Int?
    private let blobSHA: String?

    /// 默认分支的缓存（回落值与 `ref` 为空时的兜底都要它）。
    private var defaultBranch: String?

    init(
        fullName: String,
        path: RepoPath,
        size: Int?,
        blobSHA: String?,
        readOnly: Bool,
        loader: LoadFileContent,
        detail: LoadRepoDetail,
        memory: any BranchMemoryStore,
        renameFile: RenameFile,
        deleteFile: DeleteFile,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.path = path
        self.size = size
        self.blobSHA = blobSHA
        self.readOnly = readOnly
        self.loader = loader
        self.detailLoader = detail
        self.memory = memory
        self.renamer = renameFile
        self.deleter = deleteFile
        self.toast = toast
    }

    // MARK: - 取数

    func start() async {
        guard !outcome.hasFinished else { return }
        await load()
    }

    func refresh() async {
        await load()
    }

    private func load() async {
        outcome.begin()

        // ⚠️ `attempted` 与 `branch` 分开：前者是"这一趟真的发出去了的 ref"，
        //    只有它存在才谈得上"这个 ref 在服务端不存在"。`currentRef()` 自己
        //    失败时（例如取头部失败）不该被误判成"分支失效"。
        var attempted: String?
        do {
            let ref = try await currentRef()
            attempted = ref
            branch = ref
            outcome.succeed(try await fetch(ref: ref))
            return
        } catch {
            guard let ref = attempted,
                  let gitHubError = error as? GitHubError,
                  let fallback = await fallbackRef(after: gitHubError, attempted: ref)
            else {
                outcome.fail(Self.failure(from: error))
                return
            }
            // §9.4.1 第 3 条：静默回落 + 重发一次，**不向用户报错**。
            await memory.forget(fullName: fullName)
            branch = fallback
            do {
                outcome.succeed(try await fetch(ref: fallback))
            } catch {
                outcome.fail(Self.failure(from: error))
            }
        }
    }

    private func fetch(ref: String) async throws -> FileViewOutcome {
        try await loader.load(
            fullName: fullName, path: path, size: size, blobSHA: blobSHA, ref: ref
        )
    }

    /// 本次取文件用的 `ref`：记忆值优先，没有记忆就用默认分支。
    ///
    /// 走 `BranchResolver.initial` 而不是自己写 if —— 那一句话是产品口径
    /// （§9.4.1 表第三行"无记忆 ⇒ 直接用默认分支"），只有一个落点。
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

    /// 这次失败要不要按 §9.4.1 第 3 条静默重发一次；要的话给出回落用的分支。
    ///
    /// 判据整个交给 `BranchResolver.shouldSilentlyRetry`（它同时管住
    /// "只有 404 才算"与"`attempted` 不能已经是默认分支"两条）。
    private func fallbackRef(after error: GitHubError, attempted: String) async -> String? {
        guard let fallback = try? await defaultBranchName() else { return nil }
        guard BranchResolver.shouldSilentlyRetry(
            after: error, attemptedBranch: attempted, defaultBranch: fallback
        ) else { return nil }
        return fallback
    }

    // MARK: - Raw（决策 #51 两处例外之一）

    /// 复制原文到剪贴板。**零请求** —— 正文已经在手上。
    ///
    /// - Returns: 是否复制成功。三种情况各有各的提示，且**成功那句是原型的原话**
    ///   （`已复制 Raw 内容`）。
    @discardableResult
    func copyRaw() -> Bool {
        guard let text = outcome.value?.content?.text else {
            toast.show(FileCopy.rawUnavailableToast)
            return false
        }
        // ⚠️ 不判 `text.isEmpty`：一个空文件复制出来就是空串，那是**正确**的结果。
        //    把它当成"没有可复制的内容"会让用户以为这个文件出了什么问题。
        UIPasteboard.general.string = text
        toast.show(FileCopy.rawCopiedToast)
        return true
    }

    // MARK: - 复制路径 / 复制文件名（2026-10-12 新增，按用户要求）

    /// 复制**这个文件的仓库内相对路径**（含文件名）—— `crumb` 行那颗「⋯」的第一项。
    ///
    /// ⚠️ **与上面的 `copyRaw` 不是一回事**：那个复制**内容**（`Raw` 按钮，
    /// 决策 #51 的两处例外之一），这个复制**路径**。两者同在这一屏上，
    /// 所以文案与读屏标签都分开写（`FileCopy.copyPathAction` / `crumbMenuAccessibilityLabel`）。
    ///
    /// ⚠️ **原型这一屏没有这个按钮**（`REVIEW-CHECKLIST` 第 56 条：按用户要求新增）
    /// ⇒ 它不来自原型的任何一处 `onclick`。
    ///
    /// ⚠️ **零请求**：路径就在 `path` 上，复制是纯本地操作（同 `copyRaw`）。
    ///
    /// ⚠️ 取 `path` 而**不是**路由上那一份：重命名之后这一页的路径会变
    /// （§5.16「返回文件查看页（该页路径跟着变）」），要复制的必须是**当前**这个。
    ///
    /// ⚠️ 它给的是**整条**路径（`RepoPath.raw`）—— 只要名字的那一档见 `copyFileName()`。
    func copyPath() {
        UIPasteboard.general.string = path.raw
        toast.show(FileCopy.pathCopiedToast)
    }

    /// 复制**这个文件的名字**（只有最后一段，不含目录）—— 菜单的第二项（2026-10-12 追加）。
    ///
    /// ⚠️ 与 `copyPath()` **必须给出不同的东西**：一个给
    /// `Packages/GitDuoKit/Sources/RepoPath.swift`，一个只给 `RepoPath.swift`。
    /// 两项住在同一个菜单里，写岔了不会有任何报错 —— 只有粘一次才知道。
    ///
    /// ⚠️ **不做根目录兜底**（与仓库页的 `RepoCopy.clipboardPath` 不同）：
    /// 这一屏是**文件**页，`path` 必定有最后一段，`displayName` 不会是空串。
    /// 抄那条兜底过来只会让"复制出一个仓库全名"这种事在这里也变成可能。
    ///
    /// ⚠️ **零请求**（同 `copyRaw` / `copyPath`），同样取 `path` 而不是路由上那一份。
    func copyFileName() {
        UIPasteboard.general.string = path.displayName
        toast.show(FileCopy.fileNameCopiedToast)
    }

    // MARK: - 重命名（§5.16、决策 #66）

    /// 提交重命名弹层里那串路径。**校验在这里做**（`RepoPath.resolveRenameDestination`），
    /// 弹层只负责把用户原样输入的字交出来。
    ///
    /// - Returns: 要显示在输入框下方的那句话；`nil` = **弹层该关了**。
    ///
    /// ## ⚠️ `nil` 有两档，这是有意的
    ///
    /// 1. 办成了（已经有 toast，且本页路径跟着变）；
    /// 2. **用户压根没改路径** —— §5.16 明写这一档"直接关闭、不提示"（同 §5.13 的做法：
    ///    他没做错什么）。
    ///
    /// 两档都由本方法把 `sheet` 置空（弹层那一侧不区分）。⚠️ 第二档**不能**让弹层
    /// 自己 `dismiss()`：那样 SwiftUI 关掉了呈现，而 `sheet` 字段还停在 `.rename`，
    /// 于是用户再点一次「重命名」时"要呈现的东西"和"正在呈现的东西"是同一个值 ⇒
    /// **弹层不再出现**，而屏幕上看起来像点漏了。
    func rename(input: String) async -> String? {
        guard !isWorking else { return nil }

        let destination: RepoPath
        switch RepoPath.resolveRenameDestination(from: path, input: input) {
        case let .rejected(issue):
            switch issue {
            case .unchanged:
                // §5.16：直接关掉，什么都不说。
                sheet = nil
                return nil
            case .empty:
                return FileCopy.renameEmptyHint
            case let .invalidComponent(component):
                return FileCopy.renameInvalidPathHint(component: component)
            }
        case let .acceptable(resolved):
            destination = resolved
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let outcome = try await renamer.run(
                fullName: fullName,
                source: path,
                destination: destination,
                // 重命名**没有提交信息输入框**（§5.16 只给了路径框）⇒ 传 `nil`
                // 让 `CommitMessageDefaults` 用那句默认信息，与另外两条写通道同源。
                message: nil,
                branch: try await refOrThrow()
            )
            switch outcome {
            case let .renamed(newPath):
                // ⚠️ 顺序：先换路径再 `load()` —— 后者取的就是 `path` 指向的东西。
                path = newPath
                toast.show(FileCopy.renamedToast(newPath: newPath.raw))
                sheet = nil
                await load()
            case .destinationExists:
                // §5.16：**不覆盖、不合并** —— 提示留在弹层里（用户想改的正是那个名字）。
                return FileCopy.renameDestinationExistsHint
            case .movedButOldRemains:
                // ⚠️ 仓库里**两个文件都在**。这句话说的是终态，不是失败——
                //    含糊成"重命名失败"会让用户以为什么都没变（而仓库里多了一份副本）。
                //    页面**原地不动**：他看的那个路径确实还在。
                toast.show(FileCopy.renamePartiallyMovedToast)
                sheet = nil
            case let .sourceUnavailable(issue):
                return issue == .gone
                    ? FileCopy.renameSourceGoneHint
                    : FileCopy.renameSourceNotWritableHint
            }
            return nil
        } catch let error as BranchCreationError {
            return error.message
        } catch {
            return ActionCopy.failed
        }
    }

    /// 这次写要落在哪条分支上。
    ///
    /// ⚠️ 直接用**已经在手的那条**（`branch`）—— 它是本页取文件时解析出来的，
    /// 页面显示的分支名就是它。再解析一遍会多一次请求，且可能与屏幕上那个名字不一致
    /// （那才是最难查的一种 bug）。
    /// 拿不到时重取一次：此时的状态是"内容还没加载出来"，
    /// 而"拿默认分支兜底"会把一次改名落到一条用户没在看的另一条分支上。
    private func refOrThrow() async throws -> String {
        if let branch { return branch }
        return try await currentRef()
    }

    // MARK: - 删除（§5.17、决策 #66）

    /// 确认删除。
    ///
    /// - Returns: 该不该**往回走一层**（`FileView` 拿它决定 `pop()`）。
    ///
    /// ## ⚠️ 它回答的不是"成功了吗"
    ///
    /// `.alreadyGone` 同样返回 `true`：文件已经不在了，用户想要的结果**本来就成立**
    /// （PRD §5.17 明写这一档"不报删除失败"）—— 而留在一个显示"加载失败"的页面上是错的。
    ///
    /// ⚠️ 失败（403 / 配额 / 断网）返回 `false`：**留在原地**。
    /// 那种失败下文件还在，把用户弹回目录列表会让他以为什么都没发生过。
    func confirmDelete() async -> Bool {
        guard !isWorking else { return false }

        isWorking = true
        defer { isWorking = false }

        do {
            let outcome = try await deleter.run(
                fullName: fullName,
                path: path,
                message: nil,
                branch: try await refOrThrow()
            )
            switch outcome {
            case .deleted:
                toast.show(FileCopy.deletedToast(fileName: path.displayName))
            case .alreadyGone:
                toast.show(FileCopy.alreadyGoneHint)
            }
            sheet = nil
            return true
        } catch {
            toast.show(ActionCopy.failed)
            sheet = nil
            return false
        }
    }

    // MARK: - 派生

    /// `Raw` 按钮出不出现 —— 图片与不支持预览的文件**没有"原文"可复制**（§4.5）。
    var canCopyRaw: Bool { outcome.value?.content?.text != nil }

    /// 「编辑」不可点时那句读屏提示；`nil` = 可以点。
    ///
    /// 判据收在 `EditorCopy.editHint(for:)` **一处**（它认的是"这一档能不能编辑"），
    /// 两档各有各的说法：超过 1MB 是"太大"（决策 #54 的边界、偏差 32），
    /// 图片是"它根本不是文本"。
    ///
    /// ⚠️ **没有内容时返回的也是 `nil`**（= "可点"），而那一档操作行根本不画
    /// （`FileView` 类型说明第 1 条）⇒ 两处调用点都在 `fileBody` 里、拿到的必定有内容。
    var editHint: String? {
        guard let content = outcome.value?.content else { return nil }
        return EditorCopy.editHint(for: content.preview)
    }

    /// 网页端出口的地址。
    ///
    /// ⚠️ 拿不到分支时用字面 `HEAD`：GitHub 的 `blob` 路由需要一段引用名，
    /// 而 `HEAD` 正是它认的"默认分支"写法（省掉它拼出来的地址会 404）。
    /// 地址形状收在 `RepoWebLinks.blob` —— 目录里 `symlink` / `submodule`
    /// 那两类条目的出口拼的是同一个地址，各写一遍就会有一处少写 `ref`。
    var webURL: URL? {
        RepoWebLinks.blob(fullName: fullName, ref: branch ?? "HEAD", path: path)
    }

    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}
