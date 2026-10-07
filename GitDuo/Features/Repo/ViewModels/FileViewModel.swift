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

    private let loader: LoadFileContent
    private let detailLoader: LoadRepoDetail
    private let memory: any BranchMemoryStore
    private let toast: ToastCenter

    let fullName: String
    let path: RepoPath

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

    // MARK: - 派生

    /// `Raw` 按钮出不出现 —— 图片与不支持预览的文件**没有"原文"可复制**（§4.5）。
    var canCopyRaw: Bool { outcome.value?.content?.text != nil }

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
