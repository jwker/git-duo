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

    // MARK: - 重命名的目标路径（§9.6.5、PRD §5.16）

    /// 把用户在「重命名」弹层里输入的那串字解析成目标路径；不合法时说清是哪一条。
    ///
    /// ## 为什么必须在客户端拦（服务端会拦，但话说不清）
    ///
    /// 目标路径上已有文件 ⇒ `PUT` 回 **422**；那一档的文案是
    /// `{"message": ..., "errors": [...]}`（§9.6.5），用户读到的是"服务器验证失败" ——
    /// 而他手上做的是"改个名字"，两件事对不上。
    ///
    /// ⚠️ **它的判据与 `BranchName.validate` 是同一种东西**：客户端先给的
    /// 不是"更严的规则"，而是"同一条规则 + 一句能照着改的话"。
    ///
    /// - Parameters:
    ///   - source: 当前路径 —— `.unchanged` 那一档要拿它比。
    ///   - input: **原始输入**（本函数自己 trim，理由见下）。
    ///
    /// ## ⚠️ trim 在这里做，而 `isValidComponent` 不做
    ///
    /// 与 `CreateBranch.run` 同一层次的分工：判定函数不收 trim（空格是它的判据之一），
    /// 而"用户手误多打了一个空格"确实该被宽容。所以这里先 trim 一次、**并且用 trim 后的值**
    /// （不像分支名那里 trim 只用于校验）—— 因为这一串会**成为一个真实文件名**，
    /// 留一个尾随空格进去，用户下次在网页端会看到一个"名字后面有个看不见的空格"的文件。
    public static func resolveRenameDestination(
        from source: RepoPath,
        input: String
    ) -> RenameDestination {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return .rejected(.empty) }

        // ⚠️ 前导 `/` 剥掉**一次** —— 与 `RepoPath.init(path:)` 同一条宽容。
        //    不剥的话它会在下面 split 出一个空的首段、被当成"非法的一级"，
        //    而用户只是照着网页端那个路径（`/docs/a.md`）抄了一遍。
        let body = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        guard !body.isEmpty else { return .rejected(.empty) }

        // ⚠️ `omittingEmptySubsequences: false` —— 默认会**丢掉空段**，
        //    于是 `a//b` 被静默当成 `a/b`（一次"完全合法"的改名，
        //    而用户以为自己在建两级目录）。这里把空段留下来当错误。
        let components = body.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if let bad = components.first(where: { !isValidComponent($0) }) {
            return .rejected(.invalidComponent(bad))
        }

        let destination = RepoPath(path: body)
        guard destination != source else { return .rejected(.unchanged) }

        return .acceptable(destination)
    }
}

/// 重命名目标路径的校验结果。
///
/// ⚠️ **不是 `Result`**：`.unchanged` 与 `.empty` 都是"没通过"，但对用户的处置完全不同 ——
/// 前者要**直接关掉弹层、什么都不说**（PRD §5.16，同 §5.13 的做法：用户没做错什么），
/// 后者要给一句提示。合成一个 `Error` 之后，那两档就只能靠 `if case` 再分一次，
/// 而"直接关闭"这条最容易在重构里被漏成"弹一句不存在的错误"。
public enum RenameDestination: Sendable, Equatable {

    /// 可以用。带上解析好的目标路径（**已经 trim**）。
    case acceptable(RepoPath)

    case rejected(RenameDestinationIssue)
}

/// 目标路径不合法的那三档 —— 一一对应 `FileCopy` 里一句可显示的话。
public enum RenameDestinationIssue: Sendable, Equatable {

    /// 空（或全空白）⇒ 提示 `先输入文件路径`（PRD §5.16 逐字）。
    case empty

    /// 与当前路径相同 ⇒ **直接关闭，不提示**（PRD §5.16 逐字，同 §5.13 的做法）。
    case unchanged

    /// 某一级不合法（空段 / `.` / `..`）—— 带上那一级，提示里要指名道姓。
    ///
    /// ⚠️ 这一档是**规格未给**（PRD §5.16 只列了空 / 相同 / 已存在）。
    /// 加它是因为 `.` 与 `..` 拼出来的路径在服务端是一条**完全不同的路径**
    /// （可能 404、也可能真的命中某个奇怪条目），而界面上那串字看起来只是想改个名 ——
    /// 属于"界面看起来正常、行为不对"那一类，与 `isValidComponent` 拦的是同一件事。
    case invalidComponent(String)
}
