import Foundation
import GitHubAPI

/// 一个仓库标签（PRD §3.8 / §5.2、决策 #56）。
///
/// ## 为什么字段名是 `colorHex` 而 DTO 是 `color`
///
/// `LabelDTO.color` 是**六位十六进制、不带 `#`**（`"d73a4a"`）——
/// 这个事实在数据层是靠注释记住的，而到了领域层、到了要把它变成
/// SwiftUI `Color` 的那一行，它就变成了**必须知道**的东西。
/// 名字里带上 `Hex` 是把这个约束写在类型里：看到 `colorHex` 的人不会
/// 顺手把它当 CSS 色值拼进 `#\(color)` 之外的什么地方。
///
/// ⚠️ **仍然不带 `#`**（两个方向都不带：读回来的、以及发出去的）。
public struct Label: Sendable, Hashable, Identifiable {

    /// 标签名。**同一仓库内唯一** —— 它是去重与选中的键（§5.2 的「已存在则自动选中」）。
    public let name: String

    /// 六位十六进制，**不带 `#`**。
    public let colorHex: String

    /// 描述。**可以是 `nil`**（早期创建的标签没有它）。本片不渲染（§5.2 只有色点 + 名字）。
    public let description: String?

    public var id: String { name }

    public init(name: String, colorHex: String, description: String? = nil) {
        self.name = name
        self.colorHex = colorHex
        self.description = description
    }
}

/// 新建标签用的 **10 色色板**（PRD §3.8「新建标签提供 10 色色板」、§5.2）。
///
/// ## 色值取自原型，但**去掉了 `#`**
///
/// 原型 `scripts/07-issues.js` 的 `LBL_COLORS` 是 **CSS** 色值，所以带 `#`；
/// 而 `POST /labels` 要求**不带 `#`**（`LabelDTO` 的说明里写了两个方向都不带）
/// ⇒ 在这里存**不带 `#`** 的那一版。
///
/// ⚠️ **反过来存（存带 `#` 的、发请求时剥掉）是更坏的做法**：
/// 那让"发出去的到底是什么"取决于某个转换函数写得对不对，
/// 而那一次请求失败时回给你的是一句机器话术的 422 —— 用户读成"服务器坏了"。
///
/// ## ⚠️ 十档里有四档**不是**原型最初的值（2026-10-08 换过一轮）
///
/// 起因：`.lbl-tag` 是**白字压色块**，而色板里有四档太浅，白字压上去读不出来
/// （按 WCAG 2.1 算白字对比度：橙 3.23 · 黄 1.55 · 粉 3.36 · 灰 2.75，门槛 4.5）。
/// 用户裁定「保留白字、把色板里的浅色换成同族深色」：
///
/// | 族 | 原值 | 现值 | 白字对比度 |
/// |---|---|---|---|
/// | 橙 | `e16f24` | **`bc4c00`** | 3.23 → 5.03 |
/// | 黄 | `fbca04` | **`9a6700`** | 1.55 → 4.87 |
/// | 粉 | `db61a2` | **`bf3989`** | 3.36 → 5.05 |
/// | 灰 | `959da5` | **`6a737d`** | 2.75 → 4.82 |
///
/// 其余六档原值不动。**原型 `07-issues.js` 已同步改成同一份**
/// （`RepoLabelsTests` 逐字钉住两边一致 —— 改一处而不改另一处会立刻失败）。
///
/// ⚠️ **这条只治"新建标签"**：仓库里**已存在**的标签颜色是服务端给的，
/// 里面照样会有浅色（GitHub 默认的 `enhancement` 就是 `#a2eeef`，白字只有 1.31:1）。
/// 要连那些一起治好，得让 `LabelPill` 按底色亮度自动选黑/白字 ——
/// 那偏离原型，已登记为开放项（`TECH_SPEC §10.7` 切片 7 段）。
///
/// 顺序**就是**色板上的顺序（原型用 `LBL_COLORS.map` 渲染，没有重排）。
public enum LabelPalette {

    /// 10 个色值，**不带 `#`**。十档的白字对比度都 ≥ 4.5:1（最紧的一档是绿 `0e8a16`，4.50）。
    public static let hexes: [String] = [
        "d73a4a", // 红
        "bc4c00", // 橙（原 e16f24，太浅）
        "9a6700", // 黄（原 fbca04，太浅）
        "0e8a16", // 绿
        "0075ca", // 蓝
        "5319e7", // 靛
        "8250df", // 紫
        "bf3989", // 粉（原 db61a2，太浅）
        "6a737d", // 灰（原 959da5，太浅）
        "1f2328"  // 近黑
    ]

    /// 默认选中项 —— **第一个**（原型 `let pickedClr = LBL_COLORS[0]`）。
    ///
    /// ⚠️ 它不是"推荐色"，只是"打开弹层时哪个已经亮着"。
    /// 原型没有"记住上次选的色"这一说（`pickedClr` 是模块级变量，
    /// 但每次 `openLabelSheet` 都照 `LBL_COLORS[0]` 渲染高亮 ——
    /// 那个变量只在同一次弹层会话里被 `pickClr` 改过）。
    public static var initial: String { hexes[0] }

    /// 色板上的色值个数。**写成一个常量而不是 `hexes.count` 的调用点**：
    /// §3.8 与 §5.2 都写的是"10 色"，那个数字是产品承诺，
    /// 改色板时应当有一次"我改了承诺"的自觉（`LabelPaletteTests` 正面钉住它是 10）。
    public static let count = 10
}

/// 仓库标签库的接缝 —— 声明在领域层、由 `GitHubAPI` 的 `GitHubRepoLabelsEndpoint` 空扩展体满足。
///
/// ⚠️ 参数用 `String` 而不是领域层类型，是接缝的硬约束（同 `RepoIssuesDataSource` 的说明）。
public protocol RepoLabelsDataSource: Sendable {

    /// `GET /repos/{o}/{r}/labels` 的一页（服务端按名字升序）。
    func labels(owner: String, repo: String, cursor: URL?) async throws -> Page<LabelDTO>

    /// `POST /repos/{o}/{r}/labels`。
    ///
    /// - Parameter color: **六位十六进制、不带 `#`**。本方法**不做美化也不做剥除** ——
    ///   静默改写参数会把调用方的 bug 藏起来（`LabelDTO` 的说明写了理由）。
    func createLabel(
        owner: String,
        repo: String,
        name: String,
        color: String
    ) async throws -> LabelDTO
}

/// 让真实端点满足上面的接缝。空扩展体能成立，靠的是**方法签名逐字一致**。
extension GitHubRepoLabelsEndpoint: RepoLabelsDataSource {}

/// 点「创建并选中」之后的三种结局（PRD §5.2 的校验两行 + 成功一路）。
///
/// ⚠️ **`emptyName` 与 `alreadyExists` 都不是错误**：它们是两条正常的产品路径
/// （提示一句、并顺手把已有标签选上）。做成 `throw` 会让调用方在 `catch` 里
/// 区分"哪种错误要弹提示、哪种要报错"，而错误的分类信息在抛出那一刻就丢了 ——
/// 这正是把它们留在返回值里的原因。
public enum LabelCreation: Sendable, Hashable {

    /// 服务端建成功，返回它**回给我们的那一条**。
    ///
    /// ⚠️ 用服务端回的 `LabelDTO` 而不是拿本地输入造一条：名字的裁剪规则
    /// （前后空格、大小写）到底以谁为准，只有服务端说了算 ——
    /// 自造的那条会在"输入了带空格的标签名"时与服务端分叉，
    /// 而分叉的表现是本地列表里多一个点不中的标签。
    case created(Label)

    /// 本地就有同名标签 ⇒ 提示「标签已存在，已为你选中」，**一个请求都没发**。
    case alreadyExists(Label)

    /// 名字为空 / 只有空白 ⇒ 提示「请先填写标签名称」，**一个请求都没发**。
    case emptyName
}

/// 仓库标签库的用例：**取全部标签** + **新建并选中**（PRD §5.2、TECH_SPEC §9.8、决策 #56）。
///
/// ## 为什么"重名"要在这里挡掉，而不是让服务端回 422 再说
///
/// §9.8 写明了：重名时 GitHub 回 **422**，而那条 422 的文案是机器话术
/// （用户读成"服务器坏了，等等再试"）。所以客户端**提前本地去重**、
/// 并且把"已存在"这个结局顺手变成"帮你选中它" —— 用户想要的本来就是"用这个标签"，
/// 而不是"创建一个叫这个的标签"。
///
/// ⚠️ **本地去重挡不住的一种情形**（登记为已知局限）：两个客户端同时建同名标签，
/// 后到的那次会真的收到 422。那种情况下本片按**失败**处理（错误照常上抛），
/// 不自动重取标签库再选中 —— 规格没给这条路径（§9.8 只说了"提前本地去重"），
/// 而"悄悄多发一个请求去救一个竞态"是一个没人要求过的行为。
public struct LabelCatalog: Sendable {

    /// 取标签库时最多翻几页（× 100 = 1000 个标签）。
    ///
    /// 它是**给病态仓库设的防火墙**，不是产品约束：一个仓库有 1000 个以上标签时，
    /// 用户打开这个弹层不该把配额烧在这里。达到上限时 `LabelLibrary.hasMore` 为真，
    /// 界面据此知道"这不是全部"。
    public static let maxPages = 10

    private let source: any RepoLabelsDataSource

    public init(source: any RepoLabelsDataSource) {
        self.source = source
    }

    /// 取完整份标签库（自动续页）。
    ///
    /// - Throws: 任何一页的错误。⚠️ **失败不降级成空数组**：
    ///   "标签库取不到"与"这个仓库没有标签"在界面上必须分开 ——
    ///   前者要说"没加载出来，重试"，后者才是"还没有标签"。折成空数组
    ///   会让一次网络抖动看起来像"我的标签全没了"。
    public func all(fullName: String) async throws -> LabelLibrary {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)

        var collected: [Label] = []
        // ⚠️ 按 id 去重：翻页期间有人新建/改名会让同一页边界上出现重复条目，
        //    而重复的键会在 picker 里画成两行同名（点哪一行都只选中一个）。
        var seen = Set<String>()
        var cursor: URL?
        var pages = 0
        var hasMore = false

        repeat {
            let page = try await source.labels(owner: owner, repo: repo, cursor: cursor)
            // 过滤放在 append 之前：`collected` 里的顺序于是天然是"服务端给的顺序、
            // 去掉重复"，不需要额外的稳定去重算法。
            for dto in page.items where !seen.contains(dto.name) {
                seen.insert(dto.name)
                collected.append(Self.label(from: dto))
            }
            cursor = page.nextCursor
            pages += 1
            if pages >= Self.maxPages, cursor != nil {
                hasMore = true
                break
            }
        } while cursor != nil

        return LabelLibrary(labels: collected, hasMore: hasMore)
    }

    /// 新建标签并（由调用方）选中 —— §5.2 下段那个按钮。
    ///
    /// - Parameters:
    ///   - name: 用户输入的名字，**内部会 trim**（原型 `createLabel` 就是这么做的）。
    ///   - colorHex: 色板上选中的色值，**不带 `#`**。**原样发出**，不做任何转换。
    ///   - existing: 调用方手上的那份标签库（通常是 `all` 的结果 + 本次会话里已建成的）。
    ///
    /// - Returns: 三种结局，见 `LabelCreation`。**空名与重名都不会发请求。**
    /// - Throws: 只有真的发了 `POST /labels` 并且失败时才会抛。
    public func create(
        fullName: String,
        name: String,
        colorHex: String,
        existing: [Label]
    ) async throws -> LabelCreation {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyName }

        // ⚠️ 比较用**去空白之后**的名字，但**大小写敏感** —— 与服务端一致：
        //    GitHub 的标签名区分大小写（`Bug` 与 `bug` 是两个标签）。
        //    这里如果自作聪明地不区分，就会出现"本地以为重名、服务端其实是两个"，
        //    于是用户点了"创建并选中"却什么都没建 —— 而没有任何报错。
        if let hit = existing.first(where: { $0.name == trimmed }) {
            return .alreadyExists(hit)
        }

        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let dto = try await source.createLabel(
            owner: owner,
            repo: repo,
            name: trimmed,
            color: colorHex
        )
        return .created(Self.label(from: dto))
    }

    // MARK: - 私有

    private static func label(from dto: LabelDTO) -> Label {
        Label(name: dto.name, colorHex: dto.color, description: dto.description)
    }
}

/// 一份标签库 + "它完不完整"。
///
/// ⚠️ `hasMore` 的含义与 `BranchList.hasMore` 一致：服务端还有下一页
/// （本片只在**翻到页数上限**时才会是 `true`，见 `LabelCatalog.maxPages`）
/// ⇒ `count` 在那种情况下只是下界。
public struct LabelLibrary: Sendable, Hashable {

    public let labels: [Label]

    /// 达到翻页上限、后面还有。
    public let hasMore: Bool

    public init(labels: [Label], hasMore: Bool) {
        self.labels = labels
        self.hasMore = hasMore
    }

    public var count: Int { labels.count }

    /// 按名字取一条（精确匹配）。
    ///
    /// ⚠️ 与 `LabelCatalog.create` 里那次去重**同一套比较规则**（trim 后精确匹配、
    /// 大小写敏感）—— 两处若不一致，"自动选中"会选中一个和判断依据不同的标签。
    public func label(named name: String) -> Label? {
        labels.first { $0.name == name }
    }
}
