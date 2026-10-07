import Foundation

/// 搜索的四个范围（PRD §4.2、TECH_SPEC §9.2）。
///
/// 取值与显示名**逐字取自原型** `scripts/04-search.js`：
/// ```js
/// const SEARCH_SCOPES = [['repos','仓库'],['users','用户'],['code','代码'],['issues','Issue · PR']];
/// ```
/// `CaseIterable` 的顺序**就是**分段控件上的顺序 —— 原型用同一份数组渲染，
/// 所以这里不另写一遍"显示顺序"，避免两处迟早对不上。
///
/// ⚠️ `rawValue` 保留原型里那串短名（`repos` / `issues`，而不是枚举名）。
/// 它是缓存键与分段控件标识的**稳定字符串**：改名不会报错，只会让已有的缓存全部失效、
/// 让"切范围秒开"变成"每次都重新出网"。
public enum SearchScope: String, Sendable, Hashable, CaseIterable, Identifiable {

    case repositories = "repos"
    case users
    case code
    case issues

    public var id: String { rawValue }

    /// 分段控件上的文案，同时也是结果标题里的「范围名」（`{范围名} · {N} 个结果`）。
    public var title: String {
        switch self {
        case .repositories: "仓库"
        case .users: "用户"
        case .code: "代码"
        case .issues: "Issue · PR"
        }
    }

    /// 这个范围要求输入里**至少有一个检索词**（不能全是 `language:` 这类限定符）。
    ///
    /// 只有代码范围是 `true`。依据是官方对代码搜索的说明（`docs.github.com`，
    /// "Search code" 的 Considerations）：**"You must always include at least one search term
    /// when searching source code. For example, searching for `language:go` is not valid,
    /// while `amazing language:go` is."**
    ///
    /// ⚠️ 这条门槛**必须在本地拦**：服务端会回 422，而**那次失败照样扣配额**，
    /// 代码搜索那一档只有 10 次/分钟（其余范围 30）—— 四档里最紧的一档。
    public var requiresBareTerm: Bool { self == .code }
}

/// 搜索输入防抖的两档间隔（TECH_SPEC §9.2）。
///
/// ## 为什么只有"间隔"而没有"防抖器"
///
/// 防抖的**计时**属 ViewModel，属 `LoadTrendingBoard` 注释里写过的同一条分工：
/// 领域层保证"被调一次就正确一次"，"用户还在打字就先别发"只有界面层知道
/// （它才看得见有没有新的输入到来）。这一层只把**该等多久**这个产品口径钉住。
///
/// ## 为什么代码范围更长
///
/// 它那一档配额只有 **10 次/分钟**（其余范围 30），且在服务端是最贵的查询。
/// 300ms 与 500ms 对用户的手感差别很小，对配额是 1.7 倍。
public enum SearchDebounce {

    /// 常规范围：**300ms**。
    public static let standard: Duration = .milliseconds(300)

    /// 代码范围：**500ms**。
    public static let code: Duration = .milliseconds(500)

    public static func interval(for scope: SearchScope) -> Duration {
        scope == .code ? code : standard
    }
}

/// 「新输入到来 ⇒ 上一次的响应作废」的那道闸门（**不做计时**，计时见 `SearchDebounce`）。
///
/// ## 为什么要单独一个类型
///
/// 防抖与取消是**两件事**：防抖决定"什么时候发"，取消决定"发回来的东西还要不要"。
/// 后者的错法很安静 —— 先输 `swi`、再输 `swiftui`，若 `swi` 的响应后到，
/// 屏幕上留下的就是 `swi` 的结果，而输入框里明明写着 `swiftui`。
/// 把它放在领域层才能被单测钉住（App target 没有测试 target）。
///
/// 用法：每次发起请求时 `let token = self.token.issue()`；回来时先问
/// `self.token.isCurrent(token)`，不是最新的就**整份丢掉**，不往屏幕上写。
public struct SearchRequestToken: Sendable, Equatable {

    private var generation: UInt64 = 0

    public init() {}

    /// 开一次新的请求并返回它的号。**上一次的号就此作废。**
    public mutating func issue() -> UInt64 {
        generation &+= 1
        return generation
    }

    /// 这个号还是最新的吗？不是 ⇒ 它的结果已经过期。
    public func isCurrent(_ token: UInt64) -> Bool { token == generation }

    /// 当前号（排查与测试用）。
    public var current: UInt64 { generation }
}
