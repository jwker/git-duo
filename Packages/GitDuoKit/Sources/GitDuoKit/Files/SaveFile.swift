import Foundation
import GitHubAPI

/// 提交一个文件 —— §9.6.1 的①–④四条写通道，以及 §9.6.3 的「新分支 + PR」三步。
///
/// ## ⚠️ `sha` 是**参数**，本类型**不自己去取**
///
/// 决策 #64 说"编辑器页自己重取一次 `GET /contents/{path}?ref={branch}`"，
/// 而**取的时刻是进页面那一次**，不是这里、也不是提交前那一刻。理由不是省一次请求：
///
/// > `PUT` 带 `sha` 是**乐观锁**。它的语义是"我要更新的，是我**读到的那一版**"。
/// > 若在提交前现取一个最新 `sha` 再发，那么并发改动**永远撞不上 409** ——
/// > 我们会拿着新版的基准、把用户手上那份（基于旧版的）内容盖上去，
/// > **静默丢掉远端那一次改动**，而界面上写着"已提交"、没有任何异常。
///
/// 也就是说：`sha` 必须来自"用户开始编辑时读到的那一版"。`409`（`FileWriteFailure.conflict`）
/// 正是这条链路的**报警器**，取一个新鲜 `sha` 等于把报警器拆掉。
///
/// 所以本类型只负责"照它说的发"：`sha == nil` ⇒ 新建（或上传）；非 `nil` ⇒ 更新。
/// 取 `sha` 的那一次读在编辑器页（§4.6 的编辑区初值也来自同一次读 —— 两者必须同源）。
///
/// ## 「新分支 + PR」是三步，且**中途失败不回滚**（决策 #68①）
///
/// 建分支 → 提交 → 建 PR。三步都可能单独失败，而前两步**各自会留下既成事实**：
/// 建分支成功而提交失败 ⇒ 分支已经在那儿了。所以本类型用 `FileSaveOutcome`
/// 把"做到了哪一步"报出来，而**不是** `throws` 一个错误了事 ——
/// 报"提交失败"会让用户以为什么都没发生，再试一次却撞上"分支已存在"。
///
/// ⚠️ **也不做整体回滚**：客户端没有删分支的授权时机（刚建的分支里可能已经有
/// 用户的提交），而 `DELETE refs` 会把它上面的东西一起删掉。
public struct SaveFile: Sendable {

    /// Contents API 的**写**上限。
    ///
    /// ⚠️ 与读那一侧的内联上限是同一个数（官方 "up to 1 megabyte"）⇒ 直接引用
    /// `FilePreviewKind.maxInlineTextBytes`，**不另立一个常量**：
    /// 两个数分开写的那天，它们会以不同的理由漂开（而这句话在
    /// `CommitSheetCopy.tooLargeHint` 里是要印给用户看的）。
    ///
    /// ⚠️ 判定方向与读那一侧**不一样**：读那边宁可判小（多走一趟 raw 没有损失），
    /// 而写这边超了就是**做不了**，所以宁可按"服务端可能接受"处理 ——
    /// 真的超了服务端会回 422，比我们在本地拦掉一个本来能提交的文件要好。
    /// 本地这道判据只用来**提前给出口**（§5.8：提示并引导网页端，不静默失败）。
    public static let maxContentBytes = FilePreviewKind.maxInlineTextBytes

    private let files: any RepoFileWriteDataSource
    private let branches: any RepoBranchDataSource
    private let pulls: any RepoPullCreationDataSource

    /// 三条依赖 = §9.6.3 那三步各自的端点。
    ///
    /// ⚠️ **不共用一个"大端点"**：`RepoFileWriteDataSource` / `RepoBranchDataSource` /
    /// `RepoPullCreationDataSource` 三个协议各管一件事，而"这个用例到底依赖哪几个动作"
    /// 正是这层接缝存在的理由（见 `RepoEndpoints` 的类型说明）。
    /// 测试里也因此不必为一个 `SaveFile` 造出全部三个端点的替身 —— 只造用得到的那几个。
    public init(
        files: any RepoFileWriteDataSource,
        branches: any RepoBranchDataSource,
        pulls: any RepoPullCreationDataSource
    ) {
        self.files = files
        self.branches = branches
        self.pulls = pulls
    }

    /// 执行一次提交。
    ///
    /// - Parameters:
    ///   - path: 要写的路径（新建模式下由编辑器页解析用户输入的那条相对路径而来）。
    ///   - content: **原始字节**。文本用 UTF-8 的字节，上传的图片用相册/文件选择器给的
    ///     原始字节（决策 #70③：**不重编码**）。base64 编码是数据层的事 ——
    ///     那一步错了的表现是"内容损坏"，故收在一处（§4.6.2）。
    ///   - draft: 提交信息与目标（`target` 是「新分支 + PR」时还要分支名与 PR 标题）。
    ///   - sha: 更新时的版本基准；**新建 / 上传传 `nil`**。
    ///     传了 `nil` 而路径已存在 ⇒ 服务端 422（决策 #70⑤，不静默覆盖）。
    ///   - currentBranch: 当前分支 —— 当前分支那一档就是它；新分支那一档它是 `base`。
    ///   - headSHA: 当前分支 HEAD 的提交 SHA。**取不到就传 `nil`**，
    ///     本方法会补一次 `GET /branches/{branch}`（§9.7.1 的取法）。
    ///     能传就传的理由与分支列表页同源：那个值通常已经在手上了（分支列表行里）。
    ///
    /// - Returns: 见 `FileSaveOutcome`（**四种结局，其中两种是"做到一半"**）。
    /// - Throws:
    ///   - `BranchCreationError.invalidName` —— 新分支名不合法（**客户端先拦**，
    ///     规则收在 `BranchName`，与"新建分支"那条路共用同一份判据）；
    ///   - `GitHubError` —— 建分支失败、或**当前分支那一档**的任何失败。
    ///     ⚠️ 409（版本基准过期）也从这里抛，调用方按 `FileWriteFailure` 分类，
    ///     再决定要不要把两个出口换出来（§9.6.4）。
    public func run(
        fullName: String,
        path: RepoPath,
        content: Data,
        draft: CommitDraft,
        sha: String?,
        currentBranch: String,
        headSHA: String? = nil
    ) async throws -> FileSaveOutcome {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let message = draft.effectiveMessage

        // ── 当前分支那一档：一次 PUT，没有"做到一半"这一说。
        guard case let .newBranch(rawName, _) = draft.target else {
            let receipt = try await put(
                owner: owner, repo: repo, path: path, content: content,
                message: message, sha: sha, branch: currentBranch
            )
            return .committedToCurrentBranch(receipt)
        }

        // ── 新分支那一档：分支名先过客户端校验。
        //    ⚠️ 次序与 `CreateBranch.run` 逐字一致（先 trim 再校验）：
        //    校验函数本身不收 trim（它把首尾空格当作"含空格"那一档禁字符），
        //    而"用户手误多打了一个空格"确实该被宽容。
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let issue = BranchName.validate(name) {
            throw BranchCreationError.invalidName(issue)
        }

        // ── 第 1 步：建分支。⚠️ 这一步失败 ⇒ **什么都没发生**，照旧抛。
        let baseSHA = try await resolveHeadSHA(
            owner: owner, repo: repo, branch: currentBranch, known: headSHA
        )
        try await branches.createBranch(owner: owner, repo: repo, name: name, sha: baseSHA)

        // ── 第 2 步：提交到新分支。
        let receipt: FileSaveReceipt
        do {
            receipt = try await put(
                owner: owner, repo: repo, path: path, content: content,
                message: message, sha: sha, branch: name
            )
        } catch {
            guard let githubError = error as? GitHubError else { throw error }
            // ⚠️ 分支**已经建出来了** —— 报出去，别让用户以为白点了一次。
            return .branchCreatedButCommitFailed(branch: name, reason: githubError)
        }

        // ── 第 3 步：建 PR。
        do {
            let pull = try await pulls.createPull(
                owner: owner,
                repo: repo,
                title: draft.effectivePRTitle,
                head: name,
                base: currentBranch
            )
            return .createdBranchAndPull(branch: name, receipt: receipt, pullNumber: pull.number)
        } catch {
            guard let githubError = error as? GitHubError else { throw error }
            // ⚠️ 改动**已经进了那条新分支** —— 同样不能说"提交失败"。
            return .committedButPullCreationFailed(
                branch: name, receipt: receipt, reason: githubError
            )
        }
    }

    // MARK: - 内部

    /// 一次 `PUT` 并把响应折成收据。
    private func put(
        owner: String,
        repo: String,
        path: RepoPath,
        content: Data,
        message: String,
        sha: String?,
        branch: String
    ) async throws -> FileSaveReceipt {
        let result = try await files.putFile(
            owner: owner,
            repo: repo,
            path: path.raw,
            message: message,
            content: content,
            sha: sha,
            branch: branch
        )
        return FileSaveReceipt(path: path, blobSHA: result.blobSHA, commitSHA: result.commitSHA)
    }

    /// 当前分支 HEAD 的提交 SHA。手上没有才补一次请求（§9.7.1 的取法）。
    ///
    /// ⚠️ **不缓存、不复用上一次的结果**：建分支用的基准差了，那条分支就从错误的位置
    /// 分了出去 —— 而界面看起来完全正常（分支确实建出来了，只是少了几个提交）。
    private func resolveHeadSHA(
        owner: String,
        repo: String,
        branch: String,
        known: String?
    ) async throws -> String {
        if let known, !known.isEmpty { return known }
        return try await branches.branch(owner: owner, repo: repo, name: branch).commitSHA
    }
}

// MARK: - 收据

/// 一次成功写入的**收据**。
public struct FileSaveReceipt: Sendable, Equatable {

    /// 写到了哪个路径（与请求里的相同；留着它是为了让提示条不必再回头找一遍）。
    public let path: RepoPath

    /// 写入后的**新** blob SHA。
    ///
    /// ⚠️ 编辑器页**必须**拿它替换掉手上那份基准 —— 不然用户连续改两次时，
    /// 第二次会拿着**第一次之前**的 `sha` 去更新，服务端回 409，
    /// 而屏幕上看起来是"刚提交成功、再提交一次就说被人改过了"。
    public let blobSHA: String

    /// 这次提交的 SHA（`PUT` 响应体里 `commit.sha`）。
    ///
    /// ⚠️ 本期**没有一处界面显示它**（PRD 的提示条只说分支与提交信息）。
    /// 留着它不是"以后可能有用"—— 而是它是**这次写操作的唯一可核对凭据**：
    /// 真机验收时要靠它去网页端确认"那一次提交真的产生了"（照切片 1 的做法：
    /// 验收标准落在服务端事实，而不是界面说了什么）。
    public let commitSHA: String

    public init(path: RepoPath, blobSHA: String, commitSHA: String) {
        self.path = path
        self.blobSHA = blobSHA
        self.commitSHA = commitSHA
    }
}

// MARK: - 结局

/// 一次提交的四种结局。
///
/// ⚠️ **后两种不是错误**（决策 #68①）：它们是"多步操作做到一半"的**正常结局**，
/// 而且必须被报给用户 —— 那一刻仓库里确实已经有了东西（一条分支、一次提交）。
/// 报成 `throws` 会让调用方只剩"一句话说失败"这个选择，而那句话是假的。
///
/// 为什么**不是** `Result`：`Result` 的形状是"成功携带值 / 失败携带错误"，
/// 而这里有两个**既成功又失败**的档，它们在 `Result` 里没有位置
/// （硬塞会变成"成功但值里带个错误"这种自相矛盾的类型）。
public enum FileSaveOutcome: Sendable, Equatable {

    /// 一次 `PUT` 就完事（当前分支那一档）。
    case committedToCurrentBranch(FileSaveReceipt)

    /// 三步都成了。
    case createdBranchAndPull(branch: String, receipt: FileSaveReceipt, pullNumber: Int)

    /// 第 1 步成了、第 2 步失败 ⇒ **分支已经建出来了**。
    ///
    /// ⚠️ 带 `reason` 是**为了不把它吞掉**（`AGENTS.md §2`：循环 / 长任务里的失败不要静默吞掉）。
    /// 界面文案固定（`CommitSheetCopy.branchCreatedNotCommittedToast` 不随成因变），
    /// 但调用方至少能把它写进日志 —— 否则"提交为什么失败"在现场无从复盘。
    case branchCreatedButCommitFailed(branch: String, reason: GitHubError)

    /// 前两步成了、第 3 步失败 ⇒ **改动已经进了那条新分支**，只是 PR 没建起来。
    ///
    /// 配一个去网页端建 PR 的出口（`CommitSheetCopy.openCompareInBrowserAction`）。
    case committedButPullCreationFailed(
        branch: String,
        receipt: FileSaveReceipt,
        reason: GitHubError
    )

    /// 有没有真的写进去（前两档为真）。
    ///
    /// ⚠️ 收敛成一处，别让调用方写 `if case .committedToCurrentBranch = o || ...`：
    /// 那句要判四档，而加一档时**漏判不会报错** —— 表现是"提交成功了但界面还在转圈"。
    public var didWrite: Bool {
        switch self {
        case .committedToCurrentBranch, .createdBranchAndPull, .committedButPullCreationFailed:
            true
        case .branchCreatedButCommitFailed:
            false
        }
    }
}
