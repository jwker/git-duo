import Foundation
import GitHubAPI

/// 分支的 DTO → 领域模型映射（PRD §4.8、TECH_SPEC §9.7.1、决策 #53）。
public enum RepoBranchMapper {

    // MARK: - 分支行

    /// 分支列表项 → 分支行。
    ///
    /// ⚠️ **`protected` 必须原样带过去** —— 它是"能不能删"的两条判据之一（决策 #53）。
    /// 在这里丢掉（或给它一个默认 `false`），界面就会在受保护分支上给出一个
    /// **必然 422** 的删除入口，而用户完全不知道自己做错了什么。
    public static func branch(_ dto: BranchDTO) -> BranchSummary {
        BranchSummary(
            name: dto.name,
            commitSHA: dto.commitSHA,
            isProtected: dto.protected
        )
    }

    // MARK: - 比较

    /// `compare` 响应 → 领域形态。
    ///
    /// ⚠️ 认不出的 `status` ⇒ `.unknown`（**不是** `.diverged`）：
    /// `RepoComparison.Status` 自己声明了 `unknown` 一档，而"保守按 diverged 处理"
    /// 那条规则写在它的类型文档里（派生判据 `hasUnmergedCommits` 只看 `aheadBy`，
    /// 所以这一档不影响删除校验的结论）。
    ///
    /// ⚠️ 三个计数原样带过去，**没有一个能用别的字段重算出来**：
    /// `commits` / `files` 数组会被服务端截断，`aheadBy + behindBy` 也不等于
    /// `totalCommits`（`diverged` 时两者都能非零，而 total 是"两端之间的提交总数"）。
    public static func comparison(_ dto: CompareDTO) -> RepoComparison {
        RepoComparison(
            status: RepoComparison.Status(rawValue: dto.status ?? "") ?? .unknown,
            aheadBy: dto.aheadBy,
            behindBy: dto.behindBy,
            totalCommits: dto.totalCommits
        )
    }
}
