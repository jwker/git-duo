import Foundation

/// 仓库详情的四个分区。
/// 依据：PRD §4.16（代码 / Issues / Pull Requests / Commits）。
/// 依据：TECH_SPEC §8.2（2026-10-05 已补入文档，与 `Route` 同节定义）。
enum RepoSection: String, Hashable, Sendable, CaseIterable {
    case code
    case issues
    case pullRequests
    case commits
}

/// 编辑器打开模式（新建 / 编辑既有文件）。
/// 依据：TECH_SPEC §8.2（2026-10-05 已补入文档）。
enum EditorMode: Hashable, Sendable {
    /// 新建文件（需输入路径）
    case create
    /// 编辑既有文件
    case edit
}

/// 全部推入页的路由。
///
/// 依据：TECH_SPEC §8.2（逐字对齐文档中的枚举定义，**增删 case 必须先改文档**）。
/// 铁律：
/// 1. 路由用值类型枚举 + `navigationDestination(for:)`，**不用** `NavigationLink(destination:)` 闭包式写法（难以单测、难以程序化导航）。
/// 2. **只读态通过参数显式传递**（`readOnly:`），不让下层页面自行推断当前仓库归属——推断会让权限判定散落、口径不一。
/// 3. 本期**不注册深链**：`onOpenURL` 只保留 OAuth 回调分支（§3.9）。
enum Route: Hashable, Sendable {
    case search
    case repoDetail(fullName: String, section: RepoSection, path: String?)
    case exploreRepoDetail(fullName: String, path: String?)
    case fileView(fullName: String, path: String, readOnly: Bool)
    case editor(fullName: String, path: String?, mode: EditorMode)
    case commitDetail(fullName: String, sha: String, readOnly: Bool)
    case branches(fullName: String)
    case issueDetail(fullName: String, number: Int)
    case newIssue(fullName: String)
    case prDetail(fullName: String, number: Int, readOnly: Bool)
    case exploreIssueList(fullName: String)
    case explorePRList(fullName: String)
    case stars
    case folders
    case settings
}
