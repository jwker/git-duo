import Foundation

/// 分支管理页的一行（PRD §4.8、TECH_SPEC §9.7.1）。
///
/// ## ⚠️ `isProtected` 是文档里没有、但必须有的一个字段（决策 #53）
///
/// PRD §4.8 原先写「**非默认分支**带『删除』按钮」。而 `GET /repos/{o}/{r}/branches`
/// 的每一项**还带一个 `protected`**（2026-10-07 实测）—— 照 PRD 那句话实现，
/// 会在受保护分支上给出一个**必然失败**的删除按钮（服务端直接拒绝），
/// 而那个报错文案解释不了"为什么这条能删、那条不能"。
///
/// 所以删除入口的判据是**两条**：`name != defaultBranch && !isProtected`。
/// 判据落在 `canDelete(defaultBranch:)` 这一个方法里 ——
/// 它是"能不能删"的**唯一实现**（同 `Permissions.canWrite` 的规矩）：
/// UI 不给入口是一回事，逻辑层再拦一次是另一回事，两处都要走这个函数。
public struct BranchSummary: Sendable, Hashable, Identifiable {

    public let name: String

    /// 该分支 HEAD 的提交 SHA。
    ///
    /// ⚠️ **新建分支要它**（`POST /git/refs` 的 `sha` 是必填）。规格给的取法：
    /// 优先用分支列表里这一项的值，**取不到才补一次** `GET /branches/{branch}`
    /// （§9.7.1）—— 多一次请求只为拿一个字段，能省则省。
    public let commitSHA: String

    /// 服务端标记的受保护分支（`protected`）。
    public let isProtected: Bool

    /// `ForEach` 的键。分支名在**同一个仓库内**唯一（跨仓库的重复不成问题 ——
    /// 本列表只列当前仓库的分支，PRD §4.8 第 1 条）。
    public var id: String { name }

    public init(name: String, commitSHA: String, isProtected: Bool = false) {
        self.name = name
        self.commitSHA = commitSHA
        self.isProtected = isProtected
    }

    /// 能不能给这个分支画「删除」入口 —— **唯一判据**（决策 #53）。
    ///
    /// - Parameter defaultBranch: 该仓库的默认分支（`Repository.defaultBranch`）。
    ///
    /// ⚠️ **默认分支不可删是产品规则**（PRD §4.8），服务端**不会**替你拦：
    /// `DELETE /git/refs/heads/main` 对默认分支是一次真实的、会成功的删除请求
    /// （GitHub 网页端不给入口，纯属它的 UI 决定）。少写左边这个判断，
    /// 用户就能把自己的仓库删到一个打不开的状态。
    public func canDelete(defaultBranch: String) -> Bool {
        name != defaultBranch && !isProtected
    }

    /// 不给删除入口的**原因**，用于读屏提示与"为什么这个按钮没有"的说明；
    /// 可删时为 `nil`。
    ///
    /// 与 `canDelete` 同源：它只是把那个布尔值背后的理由说出来，
    /// **不是**第二套判据（两套判据迟早分歧）。
    public func deleteBlockReason(defaultBranch: String) -> DeleteBlockReason? {
        if name == defaultBranch { return .defaultBranch }
        if isProtected { return .protected }
        return nil
    }

    /// 删除入口缺席的原因。
    public enum DeleteBlockReason: Equatable, Sendable {
        case defaultBranch
        case protected
    }
}

/// `GET /repos/{owner}/{repo}/compare/{base}...{head}` 的领域形态。
///
/// ## 用途之一：删除分支前的「未合并提交」校验（决策 #53）
///
/// ⚠️ **调用形状是 `compare/{defaultBranch}...{branch}`**（默认分支在 **base** 位置）。
///
/// GitHub 的 `ahead_by` 是「**`head` 领先 `base`** 的提交数」，而我们要的数正是
/// 「这条分支领先默认分支多少」。2026-10-07（6.4 落表现层时）核对发现文档原先写的是
/// `compare/{branch}...{base}` —— 照那个字面实现会拿到"默认分支领先该分支"的数：
/// 一条有 2 个未合并提交的分支算出来是 0 ⇒ 校验通过 ⇒ 分支被删掉，
/// 而那两个提交再也没有引用指向它们。**参数顺序是这条判据成立的前提**。
///
/// ## ⚠️ 只读这四个标量，**不要数 `commits` / `files` 数组的长度**
///
/// 那两个数组**会被服务端截断**（实测；GitHub 文档也明写上限），
/// 于是"有 250 个未合并提交"与"有 400 个"数出来是同一个值。
/// 判"有没有"只依赖 `aheadBy`，它是服务端现算的计数，不受截断影响。
public struct RepoComparison: Sendable, Hashable {

    public let status: Status

    /// 右侧（`head`）比左侧（`base`）多出的提交数。
    public let aheadBy: Int

    /// 左侧比右侧多出的提交数。
    public let behindBy: Int

    /// 两端之间的提交总数（**不等于** `aheadBy + behindBy`，见 `Status.diverged`）。
    public let totalCommits: Int

    public init(status: Status, aheadBy: Int, behindBy: Int, totalCommits: Int) {
        self.status = status
        self.aheadBy = aheadBy
        self.behindBy = behindBy
        self.totalCommits = totalCommits
    }

    /// 两端的关系。
    ///
    /// ⚠️ 取值集合来自实测（`trunk...trunk` ⇒ `identical`）+ 官方文档；
    /// 留一个 `unknown` 兜底，因为这是个**字符串枚举**：将来多一个取值时，
    /// 变成"解码失败、整页打不开"是不可接受的（同 `IssueDTO.state` 的处理）。
    public enum Status: String, Sendable, Hashable {
        case ahead
        case behind
        case diverged
        case identical

        /// 认不出来的取值 —— **当作 `diverged` 保守处理**：
        /// 未知状态下的删除校验宁可阻止（多问一句），也不要放行一个可能丢提交的删除。
        case unknown
    }

    /// 这条分支有没有未合并的提交 —— 删除前的**唯一判据**（决策 #53）。
    public var hasUnmergedCommits: Bool { aheadBy > 0 }
}
