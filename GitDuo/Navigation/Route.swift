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
    /// Issue 详情。
    ///
    /// ⚠️ `readOnly` 的含义**比 `.prDetail` 那个窄**（决策 **#79**）：它只表示
    /// "**这个入口假定我没有仓库写权限**"，**不是**"整页只读" —— 详情页的操作区
    /// 还要并上"我是不是这条 Issue 的作者"（GitHub 的规则：谁提的谁可关）。
    /// ⇒ 从「我的 Issue」进来时它是 `true`，而那里几乎每一条**都能操作**；
    /// 若把它写成"`readOnly` ⇒ 什么都不给"，用户就又改不了状态了（那正是本片要修的）。
    case issueDetail(fullName: String, number: Int, readOnly: Bool)
    case newIssue(fullName: String)
    case prDetail(fullName: String, number: Int, readOnly: Bool)
    case exploreIssueList(fullName: String)
    case explorePRList(fullName: String)
    case stars
    case folders
    case settings

    /// 「我的 Pull Request」/「我的 Issue」（切片 9 新增，`TECH_SPEC §8.2`、决策 #73）。
    ///
    /// ## ⚠️ 为什么带一个 `kind` 参数，而不是两个 case
    ///
    /// 两页**同构**，只有三处不同（标题 · 空态两行 · 查询口径），三者全部由
    /// `ConversationKind` 决定、全在领域层（`MyConversationsCopy` / `MyConversationsQuery`）。
    /// 做成两个 case 就要在 `RouteView` 里把同一个视图写两遍，而那两遍
    /// **必然**在某次改动里分叉（"改了 PR 那页的标题、忘了 Issue 那页"）。
    ///
    /// ## ⚠️ 它**不复用搜索页**
    ///
    /// 原型这两个菜单项是"直接跳详情"（演示数据里正好各有一条）—— 真实数据下
    /// 必须先有一张列表。而搜索页那个范围在 App 用户令牌下是 Issue / PR **混排**的
    /// （决策 #47），与菜单项上写的字不符 ⇒ 只能新增这两屏（决策 #73、PRD §4.21）。
    case myConversations(kind: ConversationKind)
}
