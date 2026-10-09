import Foundation
import GitDuoCore

/// 「我的 Pull Request / 我的 Issue」那一页的**查询口径**（PRD §4.21、决策 #73）。
///
/// ## 它为什么不复用搜索页
///
/// 搜索页的「Issue · PR」范围**必须发两条查询再合并**（决策 #47：App 用户令牌下不带
/// `is:issue` / `is:pull-request` 直接 422），合并出来的是一个 **Issue 与 PR 混排**的列表。
/// 而这一页要回答的是两个**各自独立**的问题 —— "我提了哪些 PR" / "我提了哪些 Issue"
/// ⇒ 每一项**各发一条、各是一页**，混排恰恰是它不能有的性质。
///
/// ## `author:@me`（外部事实，2026-10-09 核实）
///
/// 官方搜索语法（`docs.github.com` "Understanding the search syntax"，中英两版一致）：
///
/// > 如果搜索查询包含**需要用户名的限定符**（例如 `user` / `actor` / `assignee`），
/// > 可以使用任何有效的用户名指定特定人员，使用 **`@me` 指定当前用户**。
/// >
/// > ⚠️ `@me` **只能与限定符一起使用**，不能单独用作搜索词（如 `@me main.workflow`）。
///
/// ⇒ `author:@me is:pull-request` 是合法写法，而且那两个限定符**一个都不能少**
/// （少了 `is:` 就是 422，少了 `author:@me` 就变成"全站最近更新的 PR"）。
///
/// ## `@me` 解析的是"这个令牌的身份"，不是我们猜的用户名
///
/// 好处是**不需要先把登录名查出来再拼字符串** —— 少一次取数，也少一处
/// "登录名里带特殊字符时拼错查询"的可能。
public enum MyConversationsQuery {

    /// 首屏页大小 —— 与搜索页、其余列表一致（`SearchQueryBuilder.pageSize`）。
    ///
    /// ⚠️ 上限 100，超过会被服务端**静默**夹到 100（分页步长因此变了而不报错）。
    public static let pageSize = SearchQueryBuilder.pageSize

    /// 排序：**最近更新降序**（PRD §4.21）。
    ///
    /// ## ⚠️ 它是**独立的查询参数**，不是 `q` 里的限定符
    ///
    /// 官方 OpenAPI 里 `GET /search/issues` 的 `sort` 参数是一个**枚举**
    /// （`comments` / `reactions` / … / `created` / **`updated`**），
    /// 与 `q` 平级、另配一个 `order`（`asc` / `desc`）。
    /// 把它当限定符塞进 `q` 是行不通的 —— 而那样写不会报错，只会**安静地按相关度排**。
    ///
    /// 为什么要显式排：点进这一页的人想看的是"我最近提的 / 最近有动静的"，
    /// 而服务端对"按作者查"这种查询的默认相关度排序**给不出可预期的顺序**
    /// （同一个查询两次结果可能不一样）。PRD §4.21 因此把这件事写成了口径。
    public static let sortParameter = "updated"
    public static let sortOrder = "desc"

    /// 这一类会话对应的**完整 `q=` 值**。
    ///
    /// 顺序是 `author:@me` 在前、`is:` 在后，与决策 #73 里写的那两条逐字一致
    /// （顺序不影响语义，但两份文档与代码写成同一个形状更好对照）。
    ///
    /// ⚠️ 两个 `is:` 限定符**复用 `SearchQueryBuilder` 的常量**，不在这里再写一遍：
    /// 那两串字面量是决策 #47 的产物（少一个整条请求 422），
    /// 两处各存一份时"改成 `is:pr`"只会改到其中一处。
    public static func qualifiers(for kind: ConversationKind) -> String {
        let typeQualifier = kind == .pullRequest
            ? SearchQueryBuilder.pullRequestQualifier
            : SearchQueryBuilder.issueQualifier
        return "author:@me \(typeQualifier)"
    }
}

/// 这一页的全部可见文案（PRD §4.21 / §7）。
public enum MyConversationsCopy {

    /// 页面标题 —— 与「我的」页那两条菜单**逐字相同**（PRD §4.21 逐字）。
    ///
    /// ## ⚠️ 只留一份定义
    ///
    /// 「两个菜单项、同一个页面，只有标题与筛选口径不同」是 PRD §4.21 的原话
    /// ⇒ 菜单文字与页面标题是**同一个字符串**。两处各写一遍，早晚会出现
    /// "菜单改了、页面标题没改"（或反过来），而两屏不会同屏出现，
    /// **看一屏永远发现不了**。所以这里向 `ProfileCopy` 取（那里是原型逐字）。
    /// 同 `ExploreRepoCopy.readmeSection` 那条先例（两处同值时只留一份）。
    public static func title(for kind: ConversationKind) -> String {
        switch kind {
        case .pullRequest: ProfileCopy.menuPullRequests
        case .issue: ProfileCopy.menuIssues
        }
    }

    /// 说明行：`{N} 个结果`（PRD §4.21 逐字）。
    ///
    /// ⚠️ `{N}` 是**服务端匹配总数**（`total_count`，与 GitHub 网页搜索一致），
    /// **不是**屏幕上已加载的条数 —— 与搜索页结果标题同一口径
    /// （判据：**数字必须是对屏幕上的这个列表的真话**，见 `LoadSearch.Result.totalCount`）。
    /// 千分位用 `GroupedNumber`：真实条数动辄三位以上。
    public static func resultsCount(_ count: Int) -> String {
        "\(GroupedNumber.string(from: count)) 个结果"
    }

    /// 空态第一行（PRD §7 逐字，2026-10-09 新定）。
    public static func emptyTitle(for kind: ConversationKind) -> String {
        switch kind {
        case .pullRequest: "还没有创建过 Pull Request"
        case .issue: "还没有创建过 Issue"
        }
    }

    /// 空态第二行（PRD §7 逐字）。
    ///
    /// ⚠️ 它是**操作引导**（"怎么做才会有"），不是解释现状 ——
    /// 与探索页那两处**有意不同**：那两处说的是"**这个仓库**没有"（状态），
    /// 这两处说的是"**你**还没有"（归属）。
    public static func emptyHint(for kind: ConversationKind) -> String {
        switch kind {
        case .pullRequest: "在任意仓库里发起一个 Pull Request，它就会出现在这里"
        case .issue: "在任意仓库里创建一个 Issue，它就会出现在这里"
        }
    }

    /// 续页按钮 —— **与搜索页是同一个词**，直接复用。
    ///
    /// ⚠️ 这一页用**按钮**而不是"滚到底自动加载"，理由与搜索页完全相同：
    /// 两者走**同一个** Search 桶（30 次/分钟），滚动手势一次能连发好几发，
    /// 一旦触发 403，整个搜索页（四个范围共用）会一起瘫掉（决策 #44、PRD §4.21）。
    public static var loadMoreAction: String { SearchCopy.loadMoreAction }

    /// 「结果可能不完整」那一行 —— 同样与搜索页共用。
    public static var incompleteResults: String { SearchCopy.incompleteResults }
}
