// Issue 列表的领域层：行模型 · 说明行文案 · 取数用例。
//
// ⚠️ 本文件切片 7 起**从 `Explore/` 移到了 `Repo/`**（决策 #61）：它服务两个页面 ——
// 探索 Issues 列表（§4.14）与仓库详情 Issues 段（§4.4 分区二）。
// 留在 `Explore/` 会让"这是探索页专属"变成一个**目录名说的谎**，
// 而下一个要动它的人会先相信目录名。
// ⚠️ 移动是纯整理（同一个 Swift 模块，路径不进编译单元）—— 没有一行行为因它改变。

import Foundation
import GitHubAPI
import GitDuoCore

/// 探索 Issues 列表的一行（PRD §4.14、TECH_SPEC §4.6.2、决策 #38）。
///
/// ## 状态为什么用 `isOpen` 而不是 `String`
///
/// `IssueDTO.state` 是 `String`（见它的类型说明：GitHub 还在演进 `state_reason`，
/// 枚举化一个仍在变的取值集合会让"某天多一个取值"表现为整页解码失败）。
/// 但**到了领域层**，这个列表的场景是确定的：只有"开放"与"已关闭"两档
/// ⇒ 一个布尔值就是全部所需。多留一个 `String` 只会让视图有机会去 `== "closed"` 地猜。
public struct IssueRow: Sendable, Hashable, Identifiable {

    /// 仓库内唯一编号 —— 卡片上的 `#42`，也是跳详情页的键。
    public let number: Int

    public let title: String

    /// 是否开放。
    ///
    /// ⚠️ 探索 Issues 列表里**只会是 `true`**（决策 #38：那一页只取 `.open`）；
    /// 而仓库详情 Issues 段的「已关闭」档（决策 #61）会取到 `false` ——
    /// 同一个行模型服务两处，值由**请求的那一档**决定。
    public let isOpen: Bool

    /// 评论条数（本列表的说明行**不显示它**，但卡片上显示 `3 条评论`）。
    public let comments: Int

    /// 创建时刻（卡片上的 `由 {作者} 创建` 对应的时间）。
    public let createdAt: Date

    /// 作者登录名。**可以是 `nil`** —— 账号被删除后 GitHub 把整段 `user` 置为 `null`。
    public let authorLogin: String?

    /// 标签（切片 7 新增 —— §4.4 分区二的卡片要画**真实标签色**）。
    ///
    /// ## ⚠️ 两处卡片对它的用法不同，而这是有意的（2026-10-08 拍板）
    ///
    /// | 页面 | 卡片上的标签 |
    /// |---|---|
    /// | 探索 Issues 列表（§4.14） | **不显示**（原型的卡片上没有这一行） |
    /// | 仓库详情 Issues 段（§4.4 分区二） | 显示（PRD 结构行明写「标签胶囊」） |
    ///
    /// ⚠️ 原型 §4.4 的卡片上**确实有一枚胶囊，但它不是标签**：是评论数，
    /// 而且用的是绿色 `StatusPill(.open)` 那一种（`05-repo.js:243` 的 `i.c`）——
    /// 照抄会得到"一枚看起来像状态胶囊的东西里写着 3"。
    /// 用户裁定：按 PRD 的「标签胶囊」画**真实标签**（`LabelPill` + 标签自己的颜色），
    /// 不照原型的形状。已登记为**有意偏差**（原型 ↔ PRD 冲突，取 PRD）。
    ///
    /// ⚠️ 因此"要不要渲染"由**调用方**决定（`IssueCard(showsLabels:)`），
    /// 不在这里判断 —— "这一页不画标签"与"这条 Issue 没有标签"是两件不同的事，
    /// 而模型里那个空的 `labels` 两种情况长得一模一样。
    ///
    /// ⚠️ 顺序 = 服务端给的顺序（**不排序**）：标签在 GitHub 网页端是人工排过的，
    /// 按名字重排会让同一张卡片在两端显示成两个样子。
    public let labels: [Label]

    /// 去重与 `ForEach` 的键（仓库内编号唯一）。
    public var id: Int { number }

    public init(
        number: Int,
        title: String,
        isOpen: Bool,
        comments: Int,
        createdAt: Date,
        authorLogin: String? = nil,
        labels: [Label] = []
    ) {
        self.number = number
        self.title = title
        self.isOpen = isOpen
        self.comments = comments
        self.createdAt = createdAt
        self.authorLogin = authorLogin
        self.labels = labels
    }

    /// 卡片副标题：`#42 · 2 小时前 · 3 条评论 · 由 reviewer-a 创建`。
    ///
    /// 逐字对齐原型（`10-explore-repo.js:106` 的 `#${i.n} · ${i.d} · 由 ${i.u} 创建`，
    /// 其中 `i.d` 是 `'2 小时前 · 3 条评论'` 这样一个**已拼好的串**）。
    /// 两处与原型不同，都是"遇到原型没覆盖的情形时不要编"：
    /// - **0 条评论不写那一段**（原型的数据里 0 评论就只写时间），
    /// - **作者为 `nil` 时整段去掉** —— 原型那处会拼出 `由 undefined 创建`。
    public func metaLabel(now: Date) -> String {
        var parts = ["#\(number)", RelativeTime.string(from: createdAt, now: now)]
        if comments > 0 { parts.append("\(comments) 条评论") }
        if let authorLogin, !authorLogin.isEmpty { parts.append("由 \(authorLogin) 创建") }
        return parts.joined(separator: " · ")
    }

    /// 读屏用的状态词（图标本身不能只靠形状传达状态）。
    public var stateLabel: String { isOpen ? "开放" : "已关闭" }
}

/// 探索 Issues 列表的说明行与页脚文案（PRD §4.14、决策 #38）。
///
/// 放在领域层是因为**计数口径本身就是一条业务规则**（`{N}` 是"已加载的非 PR 条目数"，
/// 还有下一页时才加 `+`），而不是排版选择。散进视图就没人守得住。
public enum OpenIssueIndicator {

    /// 列表标题下的说明行：`{仓库} · 开放 {N} 个`。
    ///
    /// ⚠️ 原型这句后面还缀着 `· 只读演示数据` —— 那是原型的**演示标记**，不是产品文案，
    /// 不照抄（PRD §4.14 的说明行也没有它）。
    public static func summaryLine(fullName: String, loadedCount: Int, hasMore: Bool) -> String {
        "\(fullName) · 开放 \(countLabel(loadedCount: loadedCount, hasMore: hasMore)) 个"
    }

    /// 计数值本身：还有下一页时是 **`30+`**（下界，不是确数）。
    ///
    /// ## 为什么不用接口里那个"开放 Issue 数"
    ///
    /// `open_issues_count` **把 PR 也算作 Issue**（官方文档明确）⇒ 它会比屏幕上
    /// 实际看到的条数多，而"数字对不上"会被读成"这个 App 数不准"。
    /// 所以取值是**屏幕上真实的、已加载的非 PR 条目数** —— 零额外请求，且逐条对得上
    /// （2026-10-06 用户拍板，`RepositoryDetailDTO` 里为此**有意不解码**那个字段）。
    public static func countLabel(loadedCount: Int, hasMore: Bool) -> String {
        "\(max(0, loadedCount))\(hasMore ? "+" : "")"
    }

    /// 页脚（PRD §4.14 结构一行）。
    ///
    /// ⚠️ **空态时不渲染它**（2026-10-07 拍板）：页脚讲的是"能对这个列表做什么"，
    /// 而列表为空时它无所指。判据在视图侧（`rows.isEmpty`），本常量只给文案。
    ///
    /// ⚠️ **Issue 详情页操作区那一行不是这一句**（`IssueCopy.readOnlyHint`，2026-10-09）：
    /// 本句说"这个列表能做什么"，那句说"这一页为什么没有按钮"，两者只差一个分隔符
    /// —— 越像越容易在清理时被合并，所以两边都写了反向说明（同 `PullCopy.readOnlyHint`）。
    public static let footer = "他人仓库：可评论参与讨论，关闭 Issue 需维护者权限"

    /// 空态标题（PRD §4.14「空态」段 · §7）。
    public static let emptyTitle = "暂无开放的 Issue"

    /// 空态引导行（PRD §4.14「空态」段 · §7）。
    ///
    /// ⚠️ 与说明行说的**不是同一件事**：说明行是计数结论（`开放 0 个`），
    /// 这一句是状态本身。所以空态时**两行都要在**，不能只留一个。
    public static let emptyHint = "这个仓库当前没有开放中的 Issue"
}

/// Issue 列表的数据来源 —— 领域层与网络层之间的接缝。
public protocol RepoIssuesDataSource: Sendable {

    /// `GET /repos/{owner}/{repo}/issues?state=…&labels=…` 的一页。
    ///
    /// ⚠️ **返回里混着 PR**（GitHub 把 PR 当作一种 Issue），过滤是**领域层的活**
    /// （见 `LoadRepoIssues`）—— 数据层原样返回，才能让"这一页 30 条里怎么只有 9 条"
    /// 这个问题有据可查。
    ///
    /// ⚠️ 参数用 `String` 而**不是**领域层的 `RepoListState`，这是接缝的硬约束：
    /// 本协议由 `GitDuoKit` 声明、由 `GitHubAPI` 的 `GitHubRepoIssuesEndpoint`
    /// **空扩展体**满足（那边看不见领域层的类型 —— 依赖是单向的）。
    /// 词汇转换在 `LoadRepoIssues` 里做一次，别在两处各转一遍。
    /// 服务端取值：`open` / `closed` / `all`。
    ///
    /// ⚠️ `labels` 为空数组 ⇒ 数据层**不带**该参数（不筛）；
    /// 非空 ⇒ 逗号分隔、服务端按 **AND** 语义（要同时带上这些标签）。
    func issues(
        owner: String,
        repo: String,
        state: String,
        labels: [String],
        cursor: URL?
    ) async throws -> Page<IssueDTO>
}

/// 让真实端点满足上面的接缝（协议是我们自己声明的，不是追溯适配）。
///
/// ⚠️ **空扩展体能成立，靠的是方法签名逐字一致** —— 数据层那边改了名字或参数顺序，
/// 这里不会报"少实现一个方法"（那会），但如果两边"看起来都实现了"却对不上，
/// 编译器只会在别处抛一句难懂的错。签名对齐是这套接缝唯一的纪律。
extension GitHubRepoIssuesEndpoint: RepoIssuesDataSource {}

/// 取 Issues 列表的一页（PRD §4.14 / §4.4 分区二、TECH_SPEC §9.8、决策 #38 / #56 / #61）。
///
/// ## 它同时服务两个页面（决策 #61）
///
/// | 调用方 | `state` | `labels` |
/// |---|---|---|
/// | 探索 Issues 列表（§4.14） | `.open` | 不筛 |
/// | 仓库详情 Issues 段（§4.4 分区二） | `.open` / `.closed` | 可有（标签筛选） |
///
/// 两处的**取数规则完全相同**（滤掉混进来的 PR），差别只在"向服务端要哪一批" ⇒
/// 用一个用例 + 参数表达，而不是复制一份。
public struct LoadRepoIssues: Sendable {

    private let source: any RepoIssuesDataSource

    public init(source: any RepoIssuesDataSource) {
        self.source = source
    }

    /// - Parameters:
    ///   - state: 向服务端要哪一档。**没有默认值** —— 四个调用方的意图各不相同，
    ///     给默认值等于让"忘了传"静默地选错一批数据，而结果看起来完全正常。
    ///   - labels: 标签筛选（**走服务端**，决策 #56）。空数组 ⇒ 不筛。
    ///   - cursor: 上一页的 `nextCursor`；`nil` 取第一页。
    /// - Returns: **已滤掉 PR** 的一页。
    ///
    /// ## 为什么过滤放在这一层（而不是数据层或视图层）
    ///
    /// - **不能放数据层**：那样"哪些算 Issue"这条产品口径就沉进了 `GitHubAPI`。
    /// - **不能放视图层**：视图拿到的条目会被分页状态机计数，而
    ///   `{N}` 的语义正是"已加载的**非 PR** 条目数"（决策 #38）——
    ///   过滤晚一步，计数就把 PR 也算进去了，而那个数会与屏幕上看到的条数对不上。
    ///
    /// ⚠️ **分页步长因此不是"每页 30 个 Issue"**：一页 30 条里可能只有 9 个 Issue。
    /// 这不是 bug，是 `GET /issues` 的固有行为 —— 也正因如此，
    /// 用完一页不代表"看完了 30 个 Issue"，`hasMore` 必须原样带走。
    ///
    /// ⚠️ **标签筛选也走服务端**（决策 #56）—— 不做本地过滤：
    /// 本地只能筛**已加载的那一页**（30 条，其中还混着 PR），结果显著偏少，
    /// 而说明行的计数会与"实际有多少"对不上（决策 #38 被否掉的是同一个形状）。
    public func load(
        fullName: String,
        state: RepoListState,
        labels: [String] = [],
        cursor: URL? = nil
    ) async throws -> Page<IssueRow> {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let page = try await source.issues(
            owner: owner,
            repo: repo,
            state: state.rawValue,
            labels: labels,
            cursor: cursor
        )

        return Page(
            items: page.items.filter { !$0.isPullRequest }.map(Self.row(from:)),
            // 游标与响应头原样带走：`nextCursor` 是服务端给的续页地址（§4.4），
            // 丢掉它就等于让"加载更多"永远拿不到下一页。
            nextCursor: page.nextCursor,
            headers: page.headers
        )
    }

    private static func row(from dto: IssueDTO) -> IssueRow {
        IssueRow(
            number: dto.number,
            title: dto.title,
            // ⚠️ 读一次 `state` 而不是按"我们请求的是 open"写死 `true`：
            // 现在这个用例已经能取 `.closed` 了（决策 #61），写死的那一处会
            // 静默把已关闭的 Issue 说成"开放"。
            isOpen: dto.state == "open",
            comments: dto.comments,
            // 用 `created_at` 而不是 `updated_at`：卡片文案说的是"创建"。
            createdAt: dto.createdAt,
            authorLogin: dto.user?.login,
            // ⚠️ `labels` 在 `IssueDTO` 上是可空的（官方 schema 里 nullable），
            //    而"没给标签"与"给了一个空数组"在这一层的处理完全相同（都是没有标签）
            //    ⇒ `?? []` 是对的。这一点与上面 `authorLogin` 不同：
            //    那里 `nil` 表示"作者账号没了"，是一个**独立的事实**，不能折成空串。
            labels: (dto.labels ?? []).map(Label.init(dto:))
        )
    }
}

/// 仓库详情「Issues」分段（PRD §4.4 分区二、决策 #61）的可见文案。
///
/// ## 与 `OpenIssueIndicator` 的分工
///
/// 两者都在本文件里、都讲 Issues 列表，但是**两个页面**：
///
/// | | `OpenIssueIndicator` | `RepoIssuesSectionCopy`（本类型） |
/// |---|---|---|
/// | 页面 | 探索 Issues 列表（§4.14） | 仓库详情 Issues 段（§4.4 分区二） |
/// | 档位 | 只有「开放」 | 「开放」+「已关闭」 |
/// | 筛选 | 无 | 标签多选 |
/// | 新建入口 | 无 | 有 |
///
/// 所以下面**空态那一对是复用的**（两页说同一件事），其余各归各的 ——
/// 把整块并成一个类型会让"探索页多出一个它不该有的『新建 Issue』常量"。
///
/// ## ⚠️ 分段条为什么是「两段 + 一个按钮」（2026-10-08 拍板）
///
/// PRD §4.4 分区二把三格写成 `开放 (N)` / `已关闭` / `筛选`（原型亦然）。
/// 用户裁定这三格**不是同一种东西**：
/// - `开放 (N)` 与 `已关闭` 是**真分段**（互斥、选中态在它们身上、切换即重新加载）；
/// - `筛选` 是**打开标签多选弹层的按钮**（可与其他元素正交叠加，不会被"选中"）。
///
/// ⚠️ 这与 PRD 写的「已选标签在分段条**上**以标签胶囊呈现」有**半行偏差**：
/// 已选标签排在分段条**下方一行**。理由是分段条本身是等分宽度的（`SegmentedBar`），
/// 往里塞任意多个标签会把它撑变形，而"筛选"的选中态也就无处安放了。
/// 已登记为**有意偏差**（偏 PRD 的分段语义、偏原型的排版）。
public enum RepoIssuesSectionCopy {

    // MARK: - 分段条

    /// 第一格：`开放 (N)`（原型 `05-repo.js:234` 逐字，含括号前的空格）。
    ///
    /// ## ⚠️ `loadedCount` 是**可空**的，而这不是多此一举
    ///
    /// `nil` 表示**这一档还没加载过**。此时**不能**写成 `开放 (0)` ——
    /// "还没加载出来"与"确实一条都没有"是两件完全不同的事（§8.5 末条），
    /// 而 `开放 (0)` 会让用户以为这个仓库没有开放的 Issue。
    /// 于是这一格有三种写法：`开放`（不知道）/ `开放 (0)`（确实是 0）/
    /// `开放 (30+)`（下界，还没翻完）。
    ///
    /// ⚠️ 处置与 §4.14 同源：那一页在骨架态**整行不显示**说明行
    /// （`ExploreIssueListView.showsSummaryLine`）—— 而这里"格子必须画"
    /// （少一格会让分段条看起来少了个选项），所以改成"不写那半个括号"。
    ///
    /// ⚠️ `N` 的口径**与 §4.14 完全一致**（PRD §4.4 分区二末条写明"口径同 §4.14"）：
    /// 是**已加载的非 PR 条目数**，还有下一页时缀 `+`（`30+`，是下界不是确数）。
    /// 所以这里收 `loadedCount` / `hasMore` 两个参数、内部转发到
    /// `OpenIssueIndicator.countLabel` —— **不在本类型里再算一次那个规则**：
    /// 两处各算一次的话，哪天口径改成"精确数"就只会改到一处，
    /// 而两个页面的数字对不上时没人知道该信哪个。
    public static func openSegment(loadedCount: Int?, hasMore: Bool) -> String {
        guard let loadedCount else { return openSegmentTitle }
        let label = OpenIssueIndicator.countLabel(loadedCount: loadedCount, hasMore: hasMore)
        return "\(openSegmentTitle) (\(label))"
    }

    /// 第一格在"还不知道有几个"时的写法 —— **只有标题，没有那半个括号**。
    public static let openSegmentTitle = "开放"

    /// 第二格：`已关闭`。⚠️ **原型这一格没有计数**（只有「开放」那格有），照抄。
    ///
    /// 它不是"忘了加"：`已关闭` 是一个可以无限增长的堆积（三年前的也算），
    /// 而用户在这一格里要的是"翻一翻有没有漏掉的事"，不是"一共关了多少"。
    /// 给它计数会让两格在视觉上等重，而它们的信息价值并不对等。
    public static let closedSegment = "已关闭"

    /// 第三格：`筛选`（**一个按钮**，见类型说明）。
    ///
    /// ⚠️ 与分段条上另外两格的差别不只是行为 —— 它在**排版上也不该带选中态**。
    /// 视图侧用 `allowsHitTesting(false)` 之外的东西表达"这是一个按钮"时，
    /// 应当优先看 `SegmentedBar` 有没有现成的档位，而不是给它硬塞一个 `on`。
    public static let filterAction = "筛选"

    // MARK: - 入口

    /// 列表底部的「＋ 新建 Issue」（原型 `05-repo.js:245` 逐字，**全角 `＋`**）。
    ///
    /// ⚠️ 图标（`svg(I.plus)`）**不在这个常量里** —— 它是一枚图形而不是一个字，
    /// 由视图与文案一起排（同 `PullCopy.mergeAction` 的处置）。
    public static let newIssueAction = "新建 Issue"

    // MARK: - 已选标签行（§4.4 分区二的筛选胶囊）

    /// 点一颗**已选筛选标签**会做什么（**读屏用**）。
    ///
    /// ⚠️ **规格未给**（原型只有视觉：`07-issues.js` 的 `.lbl-tag` 是一枚静态胶囊）。
    /// 这一句存在的原因是那条**已知的可用性缺口**：胶囊看起来与别处的静态标签
    /// 一模一样，视力用户看不出它可点 ⇒ 读屏那一句是它唯一的可发现性来源。
    ///
    /// ⚠️ 它与 `IssueCopy.removeLabelHint` (`双击移除这个标签`)**必须不是同一句** ——
    /// 一处在取消**筛选条件**，一处在从"这条 Issue 要带的标签"里去掉一颗。
    /// 两处用的是同一个视图组件（`SelectedLabelRow`），所以这一对极容易被写反，
    /// 而写反了**屏幕上完全看不出来**（只有读屏用户听到一个反的动作）。
    /// 判据钉在 `NewIssueTests.hintIsNotTheFilterOne`。
    public static let cancelFilterHint = "双击取消这个标签筛选"

    // MARK: - 空态

    /// 「开放」档空态 —— **复用探索页那一对**（两页说的是同一件事）。
    public static var emptyOpenTitle: String { OpenIssueIndicator.emptyTitle }
    public static var emptyOpenHint: String { OpenIssueIndicator.emptyHint }

    /// 「已关闭」档空态标题。
    ///
    /// ⚠️ **自拟（规格未给）**：PRD §4.4 分区二与 §7 都没有给这一档的空态
    /// （原型的数据里永远有已关闭的 Issue，也给不出）。
    /// 措辞对齐 `OpenIssueIndicator.emptyTitle` 的形状（`暂无{状态}的 {对象}`）。
    public static let emptyClosedTitle = "暂无已关闭的 Issue"

    /// 「已关闭」档空态引导行。
    ///
    /// ⚠️ **自拟（规格未给）**，同上。与标题的差别沿用全项目那条既有分工：
    /// 标题说**状态**（`暂无…`），引导行说的是"这个仓库的情况"。
    /// ⚠️ 用"还没有"而不是"当前没有"：已关闭是一个**只增不减**的集合，
    /// "当前"暗示它会变（像是筛选的结果），而这一档为空只可能是"从来没关过"。
    public static let emptyClosedHint = "这个仓库还没有已关闭的 Issue"
}
