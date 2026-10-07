import Foundation

/// 分支列表的一行 —— `GET /repos/{owner}/{repo}/branches`（PRD §4.8、TECH_SPEC §9.7.1）。
///
/// ## ⚠️ `protected` 是**实测**才发现的字段（决策 #53）
///
/// PRD §4.8 原先只写「**非默认分支**带『删除』按钮」。实测 `GET /branches` 的每一项
/// 还带一个 `protected`（2026-10-07：`cli/cli/branches/trunk` ⇒ `protected = true`）。
/// 照 PRD 那句话实现，会在**受保护分支**上给出一个必然被服务端拒绝（422）的删除入口，
/// 而那个报错文案解释不了"为什么这条能删、那条不能"。
///
/// 所以"能不能删"的判据是**两条**，落在领域层 `BranchSummary.canDelete(defaultBranch:)`
/// 这**一个**方法里（UI 不给入口是一回事、逻辑层再拦一次是另一回事，两处都走它）。
public struct BranchDTO: Sendable, Equatable, Decodable {

    public let name: String

    /// 分支 HEAD 的提交 SHA —— 新建分支要它（`POST /git/refs` 的 `sha` 必填）。
    ///
    /// ⚠️ **列表里就有它**，所以"新建分支"不必先补一次 `GET /branches/{branch}`（§9.7.1）。
    /// 只有 list 响应里拿不到时（例如分支名是刚输入的、不在已加载的那一页里）才补。
    public let commitSHA: String

    /// 服务端标记的受保护分支。
    ///
    /// ⚠️ 声明成**必需**：判"能不能删"完全依赖它，
    /// 缺席时补 `false` 会给出一个必然 422 的删除入口 —— 错误的值比没有值更危险。
    /// 实测该字段在 list 与单分支两个端点上都存在。
    public let protected: Bool

    public init(name: String, commitSHA: String, protected: Bool) {
        self.name = name
        self.commitSHA = commitSHA
        self.protected = protected
    }

    /// `commit` 子对象 —— 列表里只带 `sha` 与 `url`。
    ///
    /// ⚠️ 单分支端点（`GET /branches/{branch}`）里的 `commit` 是**完整提交对象**
    /// （多出 `commit` / `author` / `parents` 等）。这里只声明 `sha`，
    /// 于是两种响应共用同一个解码路径 —— 多出来的字段会被自动忽略。
    public struct CommitPointer: Sendable, Equatable, Decodable {
        public let sha: String

        public init(sha: String) {
            self.sha = sha
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case commit
        case protected
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        commitSHA = try container.decode(CommitPointer.self, forKey: .commit).sha
        protected = try container.decode(Bool.self, forKey: .protected)
    }

    // ⚠️ **有意不收 `_links` / `protection` / `protection_url`**：
    //     本切片只在"能不能删"这一处用到受保护信息，而判据就是一个布尔值。
    //     受保护的**细则**（要求状态检查、要求评审……）没有任何界面要显示，
    //     收了就是死字段（同 `IssueDTO` "只声明卡片真正用到的字段"的取舍）。
}

/// `POST /repos/{owner}/{repo}/compare/{base}...{head}` 的四项标量。
///
/// ## ⚠️ 为什么不解码 `commits` / `files`
///
/// 这个端点的响应里还有 `commits[]` 与 `files[]` 两个**可能很大**的数组，
/// 而服务端对它们**有截断上限**（官方文档明确，实测同样）——
/// 也就是说"数数组长度"得到的数**本身就是错的**（250 个与 400 个会数出同一个值）。
///
/// 于是这里**根本不声明它们**，两个好处一次拿到：
/// ① 判据只剩 `ahead_by` 这类服务端现算的计数，想数也没得数；
/// ② 省掉一次可能几十 KB 的无用解码（删除分支前的这次校验只为一个数字）。
///
/// 领域模型的对应物是 `RepoComparison`（切片 6.1），字段一一对应。
public struct CompareDTO: Sendable, Equatable, Decodable {

    /// `identical` / `ahead` / `behind` / `diverged`。
    ///
    /// ⚠️ 原样保留字符串，**不枚举化**（同 `IssueDTO.state`）：
    /// 领域层 `RepoComparison.Status(rawValue:)` 负责兜底成 `.unknown`，
    /// 而那里的 `.unknown` 有意按 `diverged`（保守：宁可多问一句）处理。
    public let status: String?

    /// `head` 比 `base` 多出的提交数 —— **判「有没有未合并提交」的唯一依据**（决策 #53）。
    public let aheadBy: Int

    public let behindBy: Int

    public let totalCommits: Int

    public init(status: String? = nil, aheadBy: Int, behindBy: Int, totalCommits: Int) {
        self.status = status
        self.aheadBy = aheadBy
        self.behindBy = behindBy
        self.totalCommits = totalCommits
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case aheadBy = "ahead_by"
        case behindBy = "behind_by"
        case totalCommits = "total_commits"
    }

    // ⚠️ `base_commit` / `merge_base_commit` / `commits` / `files` / `url` / `html_url` /
    //    `permalink_url` / `diff_url` / `patch_url` 全部有意不收 —— 见类型说明。
}
