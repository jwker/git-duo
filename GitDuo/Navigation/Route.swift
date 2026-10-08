import Foundation
import GitDuoKit

/// ⚠️ **本文件原来还有一个本地 `RepoSection`，6.4 删掉了。**
///
/// 它曾是 `Route` 的唯一来源（`TECH_SPEC §8.2` 逐字记的就是那一段）。6.1 在领域层
/// 建了**同名同取值**的 `GitDuoKit.RepoSection`（另带 `title` / `initial` 与单测）。
/// 两份定义在同一模块里共存时，**同模块的类型会遮蔽 import 进来的那个** ⇒
/// `Route.swift` 之外的代码拿到的都是本地那份（它没有 `title`），
/// 症状是"给分段条取标题"编译不过，而报错指向的是一行完全正常的代码。
///
/// 现在**唯一来源 = `GitDuoKit.RepoSection`**（有单测，且 `allCases` 顺序即
/// 分段条上从左到右的顺序）。§8.2 已同步改写。
///
/// ⚠️ **本文件原来还有一个本地 `EditorMode`，切片 8.1 删掉了。**
///
/// 它曾是 `Route.editor` 那个参数的唯一来源（`TECH_SPEC §8.2` 逐字记的就是那两档）。
/// 8.1 在领域层建了**同名同取值**的 `GitDuoKit.EditorMode`（多了
/// `loadsExistingContent` 与单测），因为 8.1 起它多了两个用户 ——
/// `SaveFile`（`sha` 带不带由模式决定）与 `EditorCopy`（说明行与标题各说一句）。
///
/// 两份定义在同一模块里共存时，**同模块的类型会遮蔽 import 进来的那个** ⇒
/// 报错会指向一行完全正常的代码（与上面 `RepoSection` 那次同一个坑）。
/// 现在**唯一来源 = `GitDuoKit.EditorMode`**；§8.2 已同步改写。

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
