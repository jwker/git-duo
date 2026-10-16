import Foundation
import GitDuoKit

/// ⚠️ **本文件原来还有一个本地 `RepoSection`，6.4 删掉了。**
///
/// 它曾是 `Route` 的唯一来源（`TECH_SPEC §8.2` 逐字记的就是那一段）。6.1 在领域层
/// 建了**同名同取值**的 `GitDuoKit.RepoSection`（另带 `title` 与单测；
/// 它当时还有个 `initial`，**2026-10-14 随分段条一起删了** —— 见 `RepoSection` 的类型说明）。
/// 两份定义在同一模块里共存时，**同模块的类型会遮蔽 import 进来的那个** ⇒
/// `Route.swift` 之外的代码拿到的都是本地那份（它没有 `title`），
/// 症状是"给入口取标题"编译不过，而报错指向的是一行完全正常的代码。
///
/// 现在**唯一来源 = `GitDuoKit.RepoSection`**（有单测，且 `allCases` 顺序即
/// 仓库首页四行入口里后三行从左到右的顺序）。§8.2 已同步改写。
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

    /// 「我的」（PRD §4.17）—— **2026-10-16 起它是一条推入页**（走查第 85 条）。
    ///
    /// 它原先是**底部第 4 格 Tab 的根页**。那一格让给了「搜索」（见 `AppTab` 的说明：
    /// 搜索是高频入口，从前却在三个根页右上角各挂一颗放大镜），
    /// 「我的」改从**首页右上角那颗头像**进 —— 于是它成了首页栈上的一页，
    /// 后续（我的 Star / 设置 / 我的 PR·Issue）照旧一条条往上推。
    ///
    /// ## ⚠️ 它没有参数
    ///
    /// 登录名取自 `authState`（`RouteView` 里那句 `?? ""` 与 `.settings` 同一条理由），
    /// 资料由组合根那份 `profileOverview` 取。**不要**在这里加一个 `login:` ——
    /// 那会让登录名出现两个来源，而这两处一旦不一致，表现是"头像是一个人、列表是另一个人"。
    case profile

    /// ⚠️ **`case search` 已删除**（2026-10-16，走查第 85 条）。
    ///
    /// 它原是首页 / 仓库 / 探索三处右上角放大镜的共同落点。那三颗放大镜随本次改动
    /// 一并移除（搜索改挂底部 Tab），于是这条路由**没有任何调用方** ——
    /// 留着它就是一条"编译器不报错的死代码"，而 `RouteView` 的穷尽性检查
    /// 正是本项目用来防漏页的机制（见 `RouteView` 的类型说明），
    /// 让一个永不命中的分支赖在里面，等于削弱那道检查。

    /// 「我的仓库」**首页**（PRD §4.4）—— 2026-10-14 起它是**枢纽页**（走查第 63 条）。
    ///
    /// ## ⚠️ 它的两个参数是**删掉**的，不是改名的
    ///
    /// 原签名 `repoDetail(fullName:section:path:)`：
    /// - `section` —— 首页不再"默认选中某一段"（分段条撤掉，四个入口各推一页）；
    /// - `path` —— 目录层级搬进了 `.repoCode` 那一页，**这一页根本没有目录**。
    ///
    /// ⚠️ `path` 那条尤其要记一笔：它曾经是"从面包屑某层推入的深层目录"，
    /// 丢了它表现为**每次点面包屑都回到仓库根**（且源码里看不出异常）。
    /// 现在这份职责在 `.repoCode` 里由**页内层级栈**承担 —— 那边的 `RepoCodeView`
    /// 说明写着"层级不进路由"的理由。
    case repoDetail(fullName: String)

    /// **代码页**（§4.4 的代码浏览；2026-10-14 从首页里搬出来独立成页）。
    ///
    /// ## 它一份服务两种仓库
    ///
    /// `readOnly` 就是"这是不是我自己的仓库"（铁律 #7：只读态显式传参、不让下层页推断）：
    /// - `.repoDetail` 那四行入口的第一行传 `false`（§4.4）；
    /// - §4.13 探索页的「文件浏览」入口传 `true`（他人仓库那一档）。
    ///
    /// ## ⚠️ `path` 是**起始层**，不是"当前层"
    ///
    /// 目录层级是**这一页内部**的导航（`RepoCodeView` 里那个 `levels` 数组
    /// —— ⚠️ **不是**一条嵌套的 `NavigationStack`，那样会崩，见那边的说明）——
    /// 进了路由就意味着"每进一层是一页新页面"，那正是本次要修掉的两个问题
    /// （首屏被头部大卡吃掉一半、每层都要重取一遍头部）。
    ///
    /// 那为什么还要一个 `path`？因为**入口有可能不是根目录**：
    /// README 里一个指向 `docs/` 的链接（`FileView` 那条）点下去，用户期望的是
    /// "打开那个目录"，而不是"回到仓库根再自己找一遍"。
    ///
    /// ⚠️ 两者不矛盾，区别在于**用户进去之后**：路由不再变。页内那个层级从这一层
    /// **往下**推，返回一层也不会走路由 —— 路由只负责"从哪一层开始看"。
    /// `nil` = 仓库根（§4.4 首页第一行与 §4.13 入口行都走这一档）。
    case repoCode(fullName: String, readOnly: Bool, path: String?)

    /// **列表分区页**（Issues / Pull Requests / Commits 各自成页，2026-10-14）。
    ///
    /// ⚠️ 三页**同构**（标题 + 一份列表 + 各自的档位与游标），只有一个 `section` 之差
    /// —— 与 `.myConversations(kind:)` 同一条处置：做成三个 case 就要在 `RouteView`
    /// 里把同一个视图写三遍，而那三遍**必然**在某次改动里分叉。
    ///
    /// ⚠️ 它只从 `.repoDetail` 的四行入口进入 ⇒ **没有 `readOnly` 参数**：
    /// 那一页是"自己的仓库"，行里推详情时显式传 `readOnly: false`
    /// （他人仓库那三样走的是 §4.13 自己的两个列表页）。
    case repoSection(fullName: String, section: RepoSection)

    /// 探索仓库详情（§4.13，**他人仓库**）。
    ///
    /// ⚠️ 它的 `path` 也是**删掉**的（2026-10-14）：这一页原先内嵌着目录浏览，
    /// 所以子目录要"推入一层新页面"；现在 ⑤ / ⑥ 两分区改成一条入口行、
    /// 目录层级跟着 `.repoCode` 走 ⇒ 这一页不再有"哪一层"这件事。
    case exploreRepoDetail(fullName: String)

    case fileView(fullName: String, path: String, readOnly: Bool)
    /// 编辑器页（§4.6）。
    ///
    /// ⚠️ `path` 与 `directory` **各服务一个模式，不能互相顶替**：
    /// - `path` = **编辑模式**要打开的那个文件；新建模式恒 `nil`。
    /// - `directory` = **新建模式**要建在**哪一层目录**（`nil` / 空 = 仓库根，§4.6）。
    ///
    /// 原先新建模式只带 `path: nil` ⇒ 路径框恒预填 `NewFile.swift`、文件恒落仓库根。
    /// 2026-10-12 用户报回「添加 / 上传都落在根目录、而不是我打开的对应目录」后补上
    /// `directory` —— 它只给路径框一个**预填前缀**（用户可以改掉），不是"锁死落点"。
    case editor(fullName: String, path: String?, mode: EditorMode, directory: String?)
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
