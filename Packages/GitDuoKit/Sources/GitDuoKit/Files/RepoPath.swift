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
        guard let parsed = normalizeUserInput(input) else { return .rejected(.empty) }
        if let bad = parsed.badComponent { return .rejected(.invalidComponent(bad)) }
        // 与当前路径相同 ⇒ 那一档**直接关掉弹层、什么都不说**（`RenameDestination` 的说明）。
        guard parsed.path != source else { return .rejected(.unchanged) }
        return .acceptable(parsed.path)
    }

    // MARK: - 新建文件的路径（§4.6，切片 8.4）

    /// 把编辑器（新建模式）路径框里那串字解析成目标路径；不合法时说清是哪一条。
    ///
    /// ## ⚠️ 与 `resolveRenameDestination` 共用同一套判据
    ///
    /// 两处的差异只有一处：新建模式没有"当前路径"可比，所以少了 `.unchanged`。
    /// 其余（trim / 剥前导 `/` / 空段当错误 / 逐级校验）**只有一份实现** ——
    /// 分开写的那天，"`a//b` 算不算合法"会在两条通道上给出不同答案，
    /// 而那两条路的用户输入框长得一模一样。
    ///
    /// ⚠️ **第三条通道 `resolveUpload`（2026-10-12 加）也走同一份**：它比这里多一条
    /// "必须是单独一段"（那一格是**文件名**，不是路径）。
    ///
    /// ⚠️ 客户端先拦的理由与重命名同源（详见 `resolveRenameDestination`）：
    /// 服务端对不合法的路径只回一个 422，而那句话读起来像"服务器坏了"。
    public static func resolveNewFile(input: String) -> NewFileDestination {
        guard let parsed = normalizeUserInput(input) else { return .rejected(.empty) }
        if let bad = parsed.badComponent { return .rejected(.invalidComponent(bad)) }
        return .acceptable(parsed.path)
    }

    // MARK: - 上传出口的落点（§5.8，2026-10-12）

    /// 把「**当前目录** + 选中的文件名」解析成上传要写的路径（§5.8 的两个上传出口）。
    ///
    /// ## ⚠️ 它取代了原先的"恒落在仓库根"
    ///
    /// PRD §5.8 那张表 2026-10-08 写的是"**落在仓库根**"，而 2026-10-12 用户报回：
    /// 「在添加或者上传文件的时候都是直接上传到了根目录，而不是上传到我打开的对应目录下」
    /// ⇒ 落点改成**打开「＋ 添加」时所在的那一层目录**（`RepoPath.root` 时仍然是仓库根）。
    ///
    /// ## ⚠️ 两格各自校验，都不放松
    ///
    /// | 格 | 规矩 | 为什么 |
    /// |---|---|---|
    /// | `fileName` | trim 后非空、且**必须是单独一段**（`a/b.jpg` 不算文件名） | "文件名"这一格出现 `/` 说明上游给错了；顺着它建出一个多级路径，正是那种**界面看起来正常、路径不对**的错 |
    /// | `directory` | 走 `appending`（它会再校验一次那一段） | 同上一条，两层都不依赖"上游一定对"这句假设 |
    ///
    /// ⚠️ 名字里带 `/` 的那一档**宁可失败**：`文件 App` 那条给的是 `lastPathComponent`、
    /// 相册那条由 `UploadFileName` 生成 ⇒ 正常路上到不了，能到就说明是缺陷，
    /// 而"操作失败 · 请重试"比"悄悄多建了一层目录"要容易发现。
    ///
    /// - Parameters:
    ///   - directory: 当前打开的那一层目录（**可以是根**）。
    ///   - fileName: 选中文件的文件名（**不含目录**）。
    public static func resolveUpload(directory: RepoPath, fileName: String) -> NewFileDestination {
        guard let parsed = normalizeUserInput(fileName) else { return .rejected(.empty) }
        if let bad = parsed.badComponent { return .rejected(.invalidComponent(bad)) }
        // 多段 ⇒ 把**整串**报回去（问题出在"它不是一个名字"这件事上，
        // 而不是其中哪一段非法 —— 报最后一段会让人以为别的段都没事）。
        guard parsed.path.components.count == 1 else {
            return .rejected(.invalidComponent(parsed.path.raw))
        }
        guard let joined = directory.appending(parsed.path.raw) else {
            return .rejected(.invalidComponent(parsed.path.raw))
        }
        return .acceptable(joined)
    }

    /// 用户输入的一串路径 → 规范化结果。**三条通道（新建 / 重命名 / 上传落点）
    /// 唯一的一处解析。**
    ///
    /// - Returns: `nil` = 空（或全空白）。
    ///   `badComponent` 非 `nil` = 某一级不合法，那一段就是它；
    ///   `badComponent` 为 `nil` = 路径可用。
    private static func normalizeUserInput(_ input: String) -> (path: RepoPath, badComponent: String?)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // ⚠️ 前导 `/` 剥掉**一次** —— 与 `RepoPath.init(path:)` 同一条宽容。
        //    不剥的话它会在下面 split 出一个空的首段、被当成"非法的一级"，
        //    而用户只是照着网页端那个路径（`/docs/a.md`）抄了一遍。
        let body = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        guard !body.isEmpty else { return nil }

        // ⚠️ `omittingEmptySubsequences: false` —— 默认会**丢掉空段**，
        //    于是 `a//b` 被静默当成 `a/b`（一次"完全合法"的提交，
        //    而用户以为自己在建两级目录）。这里把空段留下来当错误。
        let components = body.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let bad = components.first { !isValidComponent($0) }
        return (RepoPath(path: body), bad)
    }
}

/// 新建文件的目标路径（§4.6、切片 8.4）。
///
/// ⚠️ 与 `RenameDestination` **有意不合并**：那一档要区分 `.unchanged`（直接关掉不提示），
/// 而新建模式没有"当前路径"可比。合成一个类型就会多出一档永远到不了的 case，
/// 而"这一档到不到得了"正是下一个读代码的人要花时间判断的事。
public enum NewFileDestination: Sendable, Equatable {

    /// 可以用。带上解析好的目标路径（**已经 trim**）。
    case acceptable(RepoPath)

    case rejected(NewFileDestinationIssue)
}

/// 新建文件的路径不合法 —— 两档各对应 `EditorCopy` 里一句可显示的话。
public enum NewFileDestinationIssue: Sendable, Equatable {

    /// 空（或全空白）。
    case empty

    /// 某一级不合法（空段 / `.` / `..`）—— 带上那一级，提示里要指名道姓。
    case invalidComponent(String)
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
