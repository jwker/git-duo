import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 分支管理页（PRD §4.8）的状态。
///
/// ## 为什么"当前分支"要在这里重新解析一次
///
/// 本页不是从仓库详情页**继承**当前分支的：用户可能是从首页最近访问直接进来的
/// （路由只有 `fullName`），也可能是上一条消息里刚删过分支。所以这里的做法是
/// **老老实实按 §9.4.1 解析一遍**（读记忆 → 拿分支列表校正 → 失效就回落）。
///
/// ⚠️ 解析用的是 `BranchResolver` 那两个纯函数，**不是**自己写一遍 if。
/// 本类型只负责把它的三个输入（记忆值 / 可用列表 / 默认分支）凑齐。
///
/// ## 三种写操作共用一份"在途"标记
///
/// 建 / 删 / 合并都改同一条仓库的分支状态。允许两个同时发会造出一些很难看的状态
/// （一边在删 `feature/x`、一边在把它合并到 `main`），所以 `isWorking` 一把锁全占。
@MainActor
@Observable
final class BranchesViewModel {

    // MARK: - 状态

    private(set) var list: LoadState<BranchList> = .idle

    /// 当前分支（解析后的值 —— 可能已经回落过）。
    private(set) var currentBranch = ""

    private(set) var defaultBranch = ""

    /// 有写操作在途 ⇒ 所有写入口禁用（§8.5「操作类」）。
    private(set) var isWorking = false

    /// 当前呈现的弹层。
    ///
    /// ⚠️ **一个 `Identifiable` 枚举，不是三个布尔量**（同 `ExploreView` 的说明）：
    /// 本页有三张弹层（新建 / 合并 / 删除确认），两个布尔量同时为真时
    /// "哪一张盖在上面"就变成了呈现顺序问题 —— 而那种 bug 只在特定点击序列下出现
    /// （点「删除」之后不关弹层又去点「合并」，在真机上很难复现）。
    var sheet: SheetRoute?

    /// 本页的弹层路由。
    enum SheetRoute: Identifiable, Hashable, Sendable {
        case createBranch
        case merge
        case deleteBranch(BranchSummary)

        var id: String {
            switch self {
            case .createBranch: "create"
            case .merge: "merge"
            case let .deleteBranch(branch): "delete-\(branch.name)"
            }
        }
    }

    // MARK: - 依赖

    private let detailLoader: LoadRepoDetail
    private let branchesLoader: LoadBranches
    private let deleteBranch: DeleteBranch
    private let createBranch: CreateBranch
    private let mergeBranch: MergeBranch
    private let memory: any BranchMemoryStore
    private let toast: ToastCenter

    let fullName: String

    init(
        fullName: String,
        detail: LoadRepoDetail,
        branches: LoadBranches,
        deleteBranch: DeleteBranch,
        createBranch: CreateBranch,
        mergeBranch: MergeBranch,
        memory: any BranchMemoryStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.detailLoader = detail
        self.branchesLoader = branches
        self.deleteBranch = deleteBranch
        self.createBranch = createBranch
        self.mergeBranch = mergeBranch
        self.memory = memory
        self.toast = toast
    }

    // MARK: - 生命周期

    func start() async {
        guard !list.hasFinished else { return }
        await load()
    }

    func refresh() async {
        await load()
    }

    private func load() async {
        list.begin()
        do {
            // 头部：本页要它的 `defaultBranch`（回落值），**不要 Star 基准**
            // （这一屏没有那个按钮，查它纯属白花一个请求）。
            let detail = try await detailLoader.repository(fullName: fullName)
            defaultBranch = detail.defaultBranch

            let remembered = await memory.branch(for: fullName)
            let branches = try await branchesLoader.load(fullName: fullName)
            list.succeed(branches)

            let resolution = BranchResolver.resolved(
                remembered: remembered,
                available: branches.branches.map(\.name),
                defaultBranch: defaultBranch
            )
            currentBranch = resolution.branch
            // 记忆值已失效 ⇒ 清掉（§9.4.1 表第二行）。
            if resolution.didFallBack { await memory.forget(fullName: fullName) }
        } catch {
            list.fail(Self.failure(from: error))
        }
    }

    // MARK: - 切分支

    /// 点分支行 → 切过去（只影响本仓库）。
    func switchTo(_ branch: BranchSummary) async {
        guard branch.name != currentBranch else { return }
        await memory.remember(branch: branch.name, for: fullName)
        currentBranch = branch.name
        toast.show(BranchCopy.switchedToast(branch: branch.name))
    }

    // MARK: - 删分支

    /// 确认删除。
    ///
    /// - Parameter target: 要删的那条分支。**由调用方（确认弹层）显式传进来**，
    ///   而不是从某个 `deleteTarget` 字段读 —— 后者会在"弹层还没关、列表已经刷新过"
    ///   时指向一条可能已经不存在的分支。
    func confirmDelete(_ target: BranchSummary) async {
        guard !isWorking else { return }
        sheet = nil

        isWorking = true
        defer { isWorking = false }

        do {
            let result = try await deleteBranch.run(
                fullName: fullName,
                branch: target,
                currentBranch: currentBranch,
                defaultBranch: defaultBranch
            )
            // ⚠️ 四种结局的文案在 `DeleteBranchResult.message(branch:)` 里定，
            //    这里不判 case —— 视图那一层要是也判一次，两处的分岔没人会发现。
            toast.show(result.message(branch: target.name))

            guard result.didDelete else { return }
            if case let .deletedCurrent(fallback) = result { currentBranch = fallback }
            await load()
        } catch {
            toast.show(Self.actionFailedToast)
        }
    }

    // MARK: - 建分支

    /// 新建并切换。`sha` 取自分支列表里当前分支那一项（§9.7.1：能用列表里的就别再补请求）。
    ///
    /// - Returns: 失败时给用户看的那句话；成功为 `nil`（成功有 toast）。
    func create(name: String) async -> String? {
        guard !isWorking else { return nil }

        // ⚠️ SHA 取不到时要**补一次** `GET /branches/{branch}`（§9.7.1 的取法），
        //    而不是"拿一个空串去建"——服务端对空 `sha` 回 422，
        //    而那个 422 的文案解释不了"是哪一步出了问题"。
        //
        // ⚠️ 写成两句而不是 `?? (try? await …).flatMap { … }`：`flatMap` 的闭包
        //    是**同步**的，里面不能 `await`，而省略号那一版会把整个 `await`
        //    塞进闭包里 ⇒ "async call in a function that does not support concurrency"。
        var sha = list.value?.branches.first { $0.name == currentBranch }?.commitSHA
        if sha == nil {
            let fresh = try? await branchesLoader.load(fullName: fullName)
            sha = fresh?.branches.first { $0.name == currentBranch }?.commitSHA
        }

        guard let sha else { return Self.actionFailedToast }

        isWorking = true
        defer { isWorking = false }

        do {
            let created = try await createBranch.run(
                fullName: fullName, name: name, from: currentBranch, sha: sha
            )
            // ⚠️ `from:` 要用**改之前**的那个 `currentBranch` ——
            //    先把 `currentBranch` 改成新分支再拼这句话，会得到
            //    「已从 X 创建并切换到 X」（一句话里两次同一个名字，而它是错的）。
            toast.show(BranchCopy.createdToast(branch: created, from: currentBranch))
            currentBranch = created
            // 成功 ⇒ 关掉弹层（失败时它必须留着，那句话要显示在输入框下方）。
            sheet = nil
            await load()
            return nil
        } catch let error as BranchCreationError {
            // ⚠️ 名字不合法是**表单校验**，不是网络错误 —— 它的那句话要显示在
            //    弹层里的输入框下方（而不是一条 2.4 秒就消失的 toast）。
            return error.message
        } catch {
            return Self.actionFailedToast
        }
    }

    // MARK: - 合并

    /// 把 `source` 合并到当前分支（决策 #52：目标恒为当前分支）。
    ///
    /// - Returns: 失败时给用户看的那句话；成功为 `nil`。
    func merge(source: String, message: String) async -> String? {
        guard !isWorking, !source.isEmpty else { return nil }

        isWorking = true
        defer { isWorking = false }

        do {
            let outcome = try await mergeBranch.run(
                fullName: fullName,
                source: source,
                target: currentBranch,
                message: message
            )
            switch outcome {
            case .merged:
                toast.show(BranchCopy.mergedToast(source: source, target: currentBranch))
            case .nothingToMerge:
                // ⚠️ **不是失败**：204 的意思是"已经合过了"，用户想要的结果本来就成立。
                //    这里给一句"没有东西可合"而不是合并成功 —— 后者会让用户以为
                //    刚才真的产生了一个合并提交。
                toast.show(BranchCopy.nothingToMergeToast(source: source))
            }
            sheet = nil
            await load()
            return nil
        } catch let error as GitHubError {
            // ⚠️ 按 case 判而不是 `error == .conflict`：`GitHubError` 的 case 带关联值，
            //    相等比较要求整包相等；这里只关心"是哪一档"。
            // ⚠️ 409 在本包**还有第二个来源**（文件保存时 `sha` 过期，§9.6）——
            //    那句话要按调用点给，所以"冲突 ⇒ 这句话"这条规则只写在这个调用点上。
            if case .conflict = error { return BranchCopy.mergeConflictHint }
            return Self.actionFailedToast
        } catch {
            return Self.actionFailedToast
        }
    }

    // MARK: - 派生

    /// 可以合并的源分支（当前分支自己不能合自己）。
    var mergeCandidates: [String] {
        (list.value?.branches ?? []).map(\.name).filter { $0 != currentBranch }
    }

    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }

    static let actionFailedToast = "操作失败 · 请重试"
}
