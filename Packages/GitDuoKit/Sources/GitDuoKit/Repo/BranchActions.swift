import Foundation
import GitHubAPI

/// 分支列表 —— `GET /repos/{o}/{r}/branches?per_page=100`（PRD §4.8 第 1、2 条）。
///
/// ⚠️ **只取一页、不做「加载更多」**（§9.7.1）：这一页还兼着"记忆分支是否仍存在"的校验，
/// 而校验**不该额外消耗请求**。分支超过 100 条的仓库在这个页面上只能说"100 条以上"。
public struct LoadBranches: Sendable {

    private let source: any RepoBranchDataSource

    public init(source: any RepoBranchDataSource) {
        self.source = source
    }

    public func load(fullName: String) async throws -> BranchList {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let page = try await source.branches(owner: owner, repo: repo)
        return BranchList(branches: page.items.map(RepoBranchMapper.branch), hasMore: page.hasMore)
    }
}

/// 一个仓库的分支列表 + "这份列表完不完整"。
public struct BranchList: Sendable {

    public let branches: [BranchSummary]

    /// 服务端还有下一页 ⇒ `branches.count` 只是**下界**（决策 #40 的口径）。
    ///
    /// ⚠️ `BranchCopy.sectionTitle` **不**为它加 `+`（与 `OpenIssueIndicator` 有意不同）：
    /// 那边的列表在用户眼前逐条加载，"30+" 说的是"还没看完"；
    /// 这里的列表是一次全量取回后渲染的，加 `+` 会指向一个本页不存在的续页动作。
    public let hasMore: Bool

    public init(branches: [BranchSummary], hasMore: Bool) {
        self.branches = branches
        self.hasMore = hasMore
    }

    public var count: Int { branches.count }

    /// 当前分支在不在这一页里 —— 「该分支不属于当前仓库」那条提示的判据。
    public func contains(_ name: String) -> Bool {
        branches.contains { $0.name == name }
    }
}

// MARK: - 删分支（决策 #53）

/// 删除一条分支 —— **三重判定的唯一落点**。
///
/// ## 顺序不是随意的
///
/// 1. **入口判据**（`canDelete`：非默认 **且** 非受保护）—— 本地就能答，不花请求；
/// 2. **未合并校验**（`compare` 的 `aheadBy > 0`）—— 一次请求，只在第 1 步通过后才发；
/// 3. `DELETE`。
///
/// 把第 2 步放在第 3 步之前、且**必须成功**才算通过：`compare` 失败（断网 / 配额）时
/// **不能**降级成"当作没有未合并提交"然后照删 —— 那正好是这条校验要防的事
/// （一次网络抖动换来一条分支的提交永久丢失）。
///
/// ## ⚠️ `compare` 的**参数顺序**是判据成立的前提（6.4 核对修正）
///
/// GitHub 的 `ahead_by` 是「**`head` 领先 `base`** 的提交数」。
/// 我们要的数正是「**这条分支领先默认分支**多少」⇒ 要写成
/// `compare/{defaultBranch}...{branch}`（默认分支在 **base** 位置）。
///
/// 文档原先写的是 `compare/{branch}...{base}` —— 按那个字面实现会拿到
/// "默认分支领先该分支"的数，于是**一条有 2 个未合并提交的分支算出来是 0**、
/// 校验通过、分支被删掉，而那两个提交再也没有引用指向它们。
/// 这不是口径问题、是实现必须按语义写对的地方（同决策 #47 / #53 的性质）。
public struct DeleteBranch: Sendable {

    private let source: any RepoBranchDataSource
    private let memory: any BranchMemoryStore

    public init(source: any RepoBranchDataSource, memory: any BranchMemoryStore) {
        self.source = source
        self.memory = memory
    }

    /// 走完三重判定；不通过时**不发删除请求**，把结论原样返回给调用方去提示。
    ///
    /// - Throws: 只有 `compare` 或 `DELETE` 本身失败才抛。被判定拦下时**不抛**
    ///   （那是正常的产品结果，不是错误）。
    public func run(
        fullName: String,
        branch: BranchSummary,
        currentBranch: String,
        defaultBranch: String
    ) async throws -> DeleteBranchResult {
        // ── 第 1 步：入口判据。UI 已经不给入口了，这里再拦一次
        //    （「不给入口」与「逻辑层拦截」两条都要在）。
        if let reason = branch.deleteBlockReason(defaultBranch: defaultBranch) {
            switch reason {
            case .defaultBranch: return .blockedDefault
            case .protected: return .blockedProtected
            }
        }

        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)

        // ── 第 2 步：未合并校验。⚠️ 见类型说明里关于参数顺序的那段。
        let comparison = try await source.compare(
            owner: owner, repo: repo, base: defaultBranch, head: branch.name
        )
        let unmerged = RepoBranchMapper.comparison(comparison)
        if unmerged.hasUnmergedCommits {
            return .blockedUnmerged(aheadBy: unmerged.aheadBy)
        }

        // ── 第 3 步：真的删。
        try await source.deleteBranch(owner: owner, repo: repo, name: branch.name)

        // 删的正是当前分支 ⇒ 记忆失效，下次解析会回落到默认分支（§9.4.1）。
        // ⚠️ 必须 `forget` 而不是"记一条默认分支"：`forget` 表达的是"从没记过"，
        //    而记一条默认分支会让"用户自己切回默认分支"与"分支被删后回落"在存储里
        //    变得无法区分（`didFallBack` 也就再也算不准了）。
        guard branch.name == currentBranch else { return .deleted }
        await memory.forget(fullName: fullName)
        return .deletedCurrent(fallback: defaultBranch)
    }
}

/// 删除分支的四种结局（含三种被拦下）。
///
/// ⚠️ 三种"被拦下"**必须分开**：它们对用户的含义不同 ——
/// 默认分支是"这条不能动，是仓库的门面"；受保护是"**规则**不允许，而规则是管理员设的"；
/// 未合并是"删了会丢东西"。合成一句会让后两者看起来像前者的特例。
public enum DeleteBranchResult: Sendable, Equatable {

    case blockedDefault
    case blockedProtected
    case blockedUnmerged(aheadBy: Int)

    case deleted

    /// 删掉的正是当前分支 ⇒ 已回落到 `fallback`。
    case deletedCurrent(fallback: String)

    /// 删成功了吗。
    public var didDelete: Bool {
        switch self {
        case .deleted, .deletedCurrent: true
        case .blockedDefault, .blockedProtected, .blockedUnmerged: false
        }
    }

    /// 给用户看的那句话 —— 文案取自 `BranchCopy`，**不在视图里再判一次**。
    ///
    /// 四种结局 ↔ 五句文案（三句 blocked 各一句）的对应只在这里，
    /// 视图拿到 `String` 直接显示（否则视图里会出现一个与这里同形的 switch，
    /// 而两处迟早只改一处）。
    public func message(branch: String) -> String {
        switch self {
        case .blockedDefault:
            BranchCopy.defaultBranchBlockedToast(branch: branch)
        case .blockedProtected:
            BranchCopy.protectedBranchBlockedToast(branch: branch)
        case let .blockedUnmerged(aheadBy):
            BranchCopy.unmergedBlockedToast(branch: branch, aheadBy: aheadBy)
        case .deleted:
            BranchCopy.deletedToast(branch: branch)
        case let .deletedCurrent(fallback):
            BranchCopy.deletedCurrentToast(branch: branch, fallback: fallback)
        }
    }
}

// MARK: - 建分支

/// 新建一条分支并记住它（PRD §4.8「新建分支」）。
public struct CreateBranch: Sendable {

    private let source: any RepoBranchDataSource
    private let memory: any BranchMemoryStore

    public init(source: any RepoBranchDataSource, memory: any BranchMemoryStore) {
        self.source = source
        self.memory = memory
    }

    /// - Parameters:
    ///   - name: **原始输入**。本方法先做 `trimmingCharacters`（用户手误多打的空格）
    ///     再交给 `BranchName.validate` —— 校验函数本身不收 trim（它把首尾空格
    ///     当作第 2 条规则所禁止的东西），而"用户多打了一个空格"确实该被宽容。
    ///   - from: 从哪条分支创建（当前分支）。
    ///   - sha: `from` 分支 HEAD 的提交 SHA。取法见 `BranchSummary.commitSHA`：
    ///     优先用分支列表里那一项，取不到才补一次 `GET /branches/{branch}`（§9.7.1）。
    ///
    /// - Returns: 新分支名（= 去掉首尾空格后的 `name`）。
    /// - Throws: `BranchCreationError.invalidName` 或端点本身的错误。
    public func run(
        fullName: String,
        name: String,
        from: String,
        sha: String
    ) async throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let issue = BranchName.validate(trimmed) {
            throw BranchCreationError.invalidName(issue)
        }

        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        try await source.createBranch(owner: owner, repo: repo, name: trimmed, sha: sha)

        // 建完就切过去 —— 原型 `createdToast` 那句"已从 X 创建并切换到 Y"
        // 承诺的就是这个，所以记忆必须**当场**写。漏了它会话里仍是旧分支，
        // 而界面已经说"已切换到 Y"（文案承诺落空）。
        await memory.remember(branch: trimmed, for: fullName)
        return trimmed
    }
}

/// 建分支被本地拦下的原因。
public enum BranchCreationError: Error, Equatable {

    /// 名字不合法 —— 带上 `BranchName.Issue`，文案走 `BranchNameCopy.message(for:)`。
    ///
    /// ⚠️ 不把它并成 `GitHubError`：那是**网络层**的九档错误，而这一条根本没出网。
    /// 混进去会让"重试"按钮出现在一个重试也没用的问题上。
    case invalidName(BranchName.Issue)

    /// 给用户看的那句话。
    public var message: String {
        switch self {
        case let .invalidName(issue): BranchNameCopy.message(for: issue)
        }
    }
}

// MARK: - 合并分支（决策 #52）

/// 合并一条分支到当前分支 —— `POST /repos/{o}/{r}/merges`。
///
/// ⚠️ **`.nothingToMerge` 不是失败**：204 的意思是"`head` 已经合进 `base`、
/// 没有任何东西可合"，而用户想要的结果本来就成立（`MergeOutcome` 的三种结局表）。
/// 把它当失败会让用户反复点，而每次都是 204。
///
/// ⚠️ 冲突回 **409** ⇒ 数据层抛 `.conflict`，调用方按 §4.8 的文案引导到网页端。
/// 注意 409 在本包还有第二个来源（文件保存时 `sha` 过期，§9.6）⇒
/// **文案按调用点给**，不能在一处把 409 一律说成"合并冲突"。
public struct MergeBranch: Sendable {

    private let source: any RepoBranchDataSource

    public init(source: any RepoBranchDataSource) {
        self.source = source
    }

    /// - Parameters:
    ///   - source: **从哪条来** —— 弹层里用户唯一要选的东西。
    ///   - target: **合进哪条** —— 恒为当前分支（`POST /merges` 的 `base`）。
    ///   - message: 可选的合并提交信息。
    public func run(
        fullName: String,
        source branchName: String,
        target: String,
        message: String?
    ) async throws -> MergeOutcome {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        // 空串按"没填"处理：服务端对空 `commit_message` 的行为没有文档保证。
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await source.merge(
            owner: owner,
            repo: repo,
            base: target,
            head: branchName,
            message: (trimmed?.isEmpty ?? true) ? nil : trimmed
        )
    }
}
