import Foundation

/// 仓库内的相对路径（TECH_SPEC §9.5 末条：「进入目录前校验 path 拼接，
/// 避免 `..` 与双重斜杠」）。
///
/// ## 为什么需要一个类型，而不是到处拼字符串
///
/// 面包屑的每一级都是**用户可点的**（PRD §4.4：中间层级可点跳转），
/// 依次拼出 `a/b/c`。用字符串拼就有三种写错的方式，而三种都不会报错：
/// - 某一段为空 ⇒ `a//c`（服务器会当成另一条路径，可能 404、也可能真的命中某个奇怪条目）；
/// - 某一段含 `/` ⇒ 一次点击跨了两级，而面包屑显示的还是三级；
/// - 出现 `..` ⇒ 相对跳转变成向上跳转，用户以为在往下走。
///
/// 这三种都属于"界面看起来正常、行为不对"，所以它们被挡在**构造点**上：
/// 唯一的空路径是根（`RepoPath.root`，`components` 为空），
/// 其余一律经过 `appending(_:)` —— 而它会校验。
public struct RepoPath: Sendable, Hashable {

    /// 规范化后的路径：段之间用 `/` 连接，`"/"` 表示根。
    public let raw: String

    /// 根目录（仓库内路径的起点）。
    public static let root = RepoPath(raw: "", components: [])

    /// 逐段拆分后的结果（根为空数组）。
    public let components: [String]

    /// 是不是根。
    public var isRoot: Bool { components.isEmpty }

    /// 最后一段（根为 `nil`）—— 面包屑里那个**加粗不可点**的当前层。
    public var lastComponent: String? { components.last }

    /// 面包屑要显示的名字。⚠️ 根路径显示仓库全名，由调用方给（本类型不认识仓库）。
    public var displayName: String { components.last ?? "" }

    // MARK: - 构造

    /// 从一段**已经可信**的路径字符串构造（服务端返回的 `path`、路由参数）。
    ///
    /// ⚠️ 它不校验 —— 服务端给的路径不需要我们"再确认一遍"，
    /// 而用户输入一律走 `appending(_:)`。留着这条通道是为了不把
    /// "解析一个既有路径"变成一件会失败的事（那会让**渲染**一个包含
    /// 异常条目的响应变成错误，而正确的做法是把它照原样显示出来）。
    public init(path: String) {
        let cleaned = path.hasPrefix("/") ? String(path.dropFirst()) : path
        self.raw = cleaned
        self.components = cleaned.isEmpty ? [] : cleaned.split(separator: "/").map(String.init)
    }

    private init(raw: String, components: [String]) {
        self.raw = raw
        self.components = components
    }

    // MARK: - 拼接

    /// 拼下一级。**这是用户点击产生的路径唯一该走的路**。
    ///
    /// - Returns: 拼好的路径；`component` 不合法时为 `nil`。
    ///
    /// 返回 `nil` 而不是抛错：调用方（目录行的点击回调）本来就必须处理
    /// "这一项不可进入"的情形，而用 `try?` 把它吞掉会让"没进去"看起来像"点了没反应"。
    public func appending(_ component: String) -> RepoPath? {
        guard Self.isValidComponent(component) else { return nil }
        return RepoPath(
            raw: components.isEmpty ? component : "\(raw)/\(component)",
            components: components + [component]
        )
    }

    /// 回到上一级（面包屑点前一层）。根再往上还是根。
    public func deletingLastComponent() -> RepoPath {
        guard !components.isEmpty else { return self }
        return RepoPath(path: components.dropLast().joined(separator: "/"))
    }

    /// 一层合法的路径段。
    ///
    /// 规则（全部来自"这一段会被拼进 URL 路径"这一件事，而不是浏览器的语义）：
    /// - 非空（空段会拼出 `//`）；
    /// - 不含 `/`（否则一次点击跨两级）；
    /// - 不等于 `.` 或 `..`（相对跳转的记号，不是真实条目名）。
    ///
    /// ⚠️ **不禁**以 `.` 开头 —— `.gitignore` / `.github` 是真实且常见的条目，
    /// 拦掉它们等于让一类文件在 App 里彻底不可见。
    public static func isValidComponent(_ component: String) -> Bool {
        guard !component.isEmpty else { return false }
        guard !component.contains("/") else { return false }
        guard component != ".", component != ".." else { return false }
        return true
    }
}
