import Foundation
import GitDuoCore

/// 占位数据 —— 官方骨架方案 `.redacted(reason: .placeholder)` 的配套（NATIVE-MIGRATION P1）。
///
/// ## 为什么要有这一份
///
/// SwiftUI 的官方占位方案**不是**"画一堆灰条"，而是**拿真实布局渲染一遍、再把内容遮成灰块**：
///
/// ```swift
/// RepoCard(repository: .placeholder).redacted(reason: .placeholder)
/// ```
///
/// 它的好处正是自绘骨架屏做不到的那一条：**尺寸永远与真实布局一致**（§8.5 第 1 条
/// 那条"改了真实卡片忘了改骨架 ⇒ 数据到达时整屏跳一下"的问题从此消失，因为根本
/// 没有第二份布局可写）。代价是需要一份假数据来喂真实布局 —— 就是本文件。
///
/// ## 三条纪律
///
/// 1. **只允许出现在 `.redacted` 之下** —— 这些字符串是"凑出合适宽度的填料"，
///    不是文案，任何一处让它露出来都是 bug（红act 之后读屏也读不到它：
///    SwiftUI 会把 redacted 视图当作占位，读屏念的是"正在加载"那类系统话术）。
/// 2. **填料长度挑的是"一行放得下、看起来像一行字"**，不是随便写 ——
///    块宽就是文字宽，写太短会看到一排小方块，写太长会顶到边界。
/// 3. ⚠️ **不要给它加本地化 / 不要进文案层**（`*Copy` 那一族）—— 它永远不该被看见，
///    一旦进了可译资源，就等于承认它会出现在屏幕上。
public enum Placeholders {

    /// 一条"看起来像一句话"的填料。
    ///
    /// ⚠️ 不用真实词（"正在加载…"那种）—— 有人的第一反应是"这句是不是该翻译"，
    /// 而它根本不该被读。用重复字是为了让宽度稳定、且一眼看出它是填料。
    public static let line = "占位占位占位占位占位"

    /// 一条短一些的（副标题 / 第二行）。
    public static let shortLine = "占位占位占位"

    /// 一个固定时刻。**不要在这里取 `Date()`** —— 占位数据是值，每次渲染都变会让
    /// 相对时间（`#42 · 3 天前`）在 redacted 下也跟着变，且无从稳定。
    public static let date = Date(timeIntervalSince1970: 0)

    /// 一份"看起来像一篇文档"的 Markdown 源文 —— README / 正文 / 版本说明那一族的占位。
    ///
    /// ⚠️ 它会被 `MarkdownDocument` 真解析一遍（`MarkdownBody` 吃的是块），
    /// 所以这里要是**合法 Markdown**，否则解析出来是空块、占位区什么都不画。
    public static let document = """
        # 占位占位占位

        占位占位占位占位占位占位占位占位占位占位

        占位占位占位占位占位占位占位
        """

    /// 文件名 / 路径那一类占位（文件页、编辑器、diff 卡的文件名行）。
    public static let fileName = "Placeholder.swift"

    /// 热力图骨架用的占位矩阵：`columns` 列 × 7 行、全是**最浅档**（`0`）。
    ///
    /// ⚠️ 行数取 `ContributionGrid.rowCount`（领域层常量），不在这里再写一个 7。
    /// 列数写 53 是**"一整年"这件事本身**（`ContributionHeatmap` 的说明里那串
    /// `53 × 11 + 52 × 2.5`），不是抄某个像素值。
    public static func heatmapLevels(columns: Int = 53) -> [[Int?]] {
        Array(repeating: Array(repeating: 0, count: ContributionGrid.rowCount), count: columns)
    }
}

extension Repository {

    /// 仓库列表（`RepoCard`）与「我的 Star」（`StarRow`）的占位。
    public static let placeholder = Repository(
        owner: "placeholder",
        name: "placeholder",
        description: Placeholders.line,
        isPrivate: false,
        language: "Placeholder",
        starCount: 0,
        forkCount: 0
    )
}

extension RepoSummary {

    /// 首页置顶（`PinRow`）与探索榜（`TrendCard`）的占位。
    public static let placeholder = RepoSummary(
        fullName: "placeholder/placeholder",
        description: Placeholders.line,
        language: "Placeholder",
        starCount: 0
    )
}

extension RepositoryHit {

    /// 搜索结果行的占位（四种结果行里最宽的那种 —— 骨架只铺一种，见 `SearchResultsSkeleton`）。
    public static let placeholder = RepositoryHit(
        fullName: "placeholder/placeholder",
        description: Placeholders.shortLine,
        language: "Placeholder",
        starCount: 0
    )
}

extension IssueRow {

    /// Issue / PR 列表卡片（`IssueCard` / `PullCard`）的占位。
    public static let placeholder = IssueRow(
        number: 0,
        title: Placeholders.line,
        isOpen: true,
        comments: 0,
        createdAt: Placeholders.date,
        authorLogin: "placeholder"
    )
}

extension TreeEntry {

    /// 文件树一行的占位（`RepoFileRow`）。
    ///
    /// ⚠️ `path` 用 `RepoPath(path:)`（那条**不校验**的通道）：占位不来自用户输入，
    /// 也没必要为了它去走一遍 `appending(_:)` 的合法性检查。
    public static let placeholder = TreeEntry(
        name: Placeholders.shortLine,
        path: RepoPath(path: "placeholder"),
        kind: .directory,
        size: 0,
        sha: ""
    )
}

extension RepositoryDetail {

    /// 仓库详情页头部（`RepoDetailHero`）的占位。
    ///
    /// ⚠️ `starCount` / `forkCount` / `watcherCount` / `defaultBranch` **必须显式给**
    /// （见 `RepositoryDetail.init` 的说明）：给它们编默认值会让"忘了传"编译通过。
    /// 这里给 0 是"骨架期的形状"，redacted 之下读不到这些数。
    public static let placeholder = RepositoryDetail(
        fullName: "placeholder/placeholder",
        description: Placeholders.line,
        defaultBranch: "main",
        starCount: 0,
        forkCount: 0,
        watcherCount: 0,
        pushedAt: Placeholders.date
    )
}

extension BranchSummary {

    /// 分支行（`BranchRow` / `SheetRow`）的占位。
    ///
    /// ⚠️ 名字**带序号**：`BranchSummary.id` 就是分支名，`ForEach(list.branches)`
    /// 用的正是它 —— 几条占位同名会撞键（表现是"骨架只有一行"）。
    public static func placeholder(index: Int = 0) -> BranchSummary {
        BranchSummary(name: "placeholder-\(index)", commitSHA: "", isProtected: false)
    }
}

extension BranchList {

    /// 分支页与切换分支弹层的占位列表。
    ///
    /// 直接喂给真实的 `loaded(_:)` / `rows(_:)` ⇒ 骨架连"分组标题 + 两个按钮"都
    /// 不是第二份写法，与真实布局**同源**。
    public static func placeholder(count: Int = 5) -> BranchList {
        BranchList(branches: (0..<count).map { BranchSummary.placeholder(index: $0) }, hasMore: false)
    }
}

extension CommitSummary {

    /// 提交行（`RepoCommitRow`）的占位。
    public static let placeholder = CommitSummary(
        sha: "0000000",
        message: Placeholders.line,
        authorLogin: "placeholder",
        authoredAt: Placeholders.date
    )
}

extension Label {

    /// 标签行（`LabelPickerSheet` 的 `SheetRow`）的占位。
    ///
    /// ⚠️ 同 `BranchSummary`：`Label.id` 就是名字，几条占位同名会撞 `ForEach` 的键。
    public static func placeholder(index: Int = 0) -> Label {
        Label(name: "placeholder-\(index)", colorHex: "D0D7DE")
    }
}

extension StarState {

    /// 「我的 Star」那一行的状态占位。
    ///
    /// `baselineConfirmed: false` —— 占位不该声称"已确认已 Star"，
    /// 而 redacted 之下这个区别本来就看不见；取 `false` 是保守那一侧。
    public static func placeholder(fullName: String = "placeholder/placeholder") -> StarState {
        StarState(fullName: fullName, isStarred: false, starCount: 0, baselineConfirmed: false)
    }
}

extension IssueDetail {

    /// Issue 详情页整页骨架的占位（`IssueDetailView` 直接把真实的 `loaded(_:)` 喂给它）。
    ///
    /// ⚠️ `body` **必须有内容** —— `hasBody` 为假时正文气泡整块不渲染，
    /// 占位区就会比真实内容少一截。
    public static let placeholder = IssueDetail(
        number: 0,
        title: Placeholders.line,
        isOpen: true,
        body: Placeholders.document,
        authorLogin: "placeholder",
        createdAt: Placeholders.date
    )
}

extension IssueComment {

    /// 评语气泡（`CommentRow`）的占位。
    public static func placeholder(index: Int = 0) -> IssueComment {
        IssueComment(
            id: index,
            body: Placeholders.line,
            authorLogin: "placeholder",
            createdAt: Placeholders.date
        )
    }
}

extension PullDetail {

    /// PR 详情页骨架的占位。
    public static let placeholder = PullDetail(
        number: 0,
        title: Placeholders.line,
        state: .open,
        headRef: "placeholder",
        baseRef: "placeholder",
        authorLogin: "placeholder",
        createdAt: Placeholders.date,
        updatedAt: Placeholders.date,
        body: Placeholders.document,
        additions: 0,
        deletions: 0,
        changedFiles: 0
    )
}

extension CommitDetail {

    /// 提交详情页骨架的占位。
    ///
    /// ⚠️ `files` 给一条**占位改动**（不是空数组）：空数组会让 `files(_:)` 落到
    /// 「这个提交没有文件改动」那一块，占位区与真实内容差出两张 diff 卡。
    public static let placeholder = CommitDetail(
        sha: "0000000",
        message: Placeholders.line,
        authorLogin: "placeholder",
        authoredAt: Placeholders.date,
        stats: Stats(additions: 0, deletions: 0, total: 1),
        files: [FileChange.placeholder]
    )
}

extension FileChange {

    /// 一张 diff 卡的占位。
    ///
    /// ⚠️ `patch` 给一段**真的 unified diff**：`DiffCard` 是按行解析它来画的，
    /// 给 `nil` 会落到"二进制 / 无 diff"那一档，占位区就只剩文件名一行。
    public static let placeholder = FileChange(
        filename: Placeholders.fileName,
        additions: 0,
        deletions: 0,
        status: .modified,
        patch: """
            @@ -1,3 +1,3 @@
             占位占位占位
            -占位占位占位
            +占位占位占位
            """
    )
}

extension FileContent {

    /// 文件页与编辑器整页骨架的占位。
    ///
    /// ⚠️ `markdown: nil` ⇒ 占位画的是**代码块**（`CodeSurface`）那一档。
    /// 真实内容若是 `.md`，到位时会换成文档卡 —— 骨架与内容在这一档上形状不同，
    /// 是有意的取舍：占位只可能选一档，而"多数文件是代码"更常见。
    public static let placeholder = FileContent(
        path: RepoPath(path: Placeholders.fileName),
        blobSHA: "",
        size: 0,
        body: .text(Array(repeating: Placeholders.line, count: 8).joined(separator: "\n")),
        preview: .text,
        markdown: nil
    )
}

extension RepoInsights {

    /// 他人仓库详情页（`ExploreRepoDetailView`）整页骨架的占位。
    ///
    /// ⚠️ 四个分区各给一条最少但**非空**的数据：语言构成、最新版本、贡献者
    /// 在"空"时各会退化成一行灰字（`emptyLine`），占位区就少三张卡。
    public static let placeholder = RepoInsights(
        detail: .placeholder,
        languages: [LanguageShare(language: "Placeholder", bytes: 1, percent: 100)],
        release: LatestRelease(tagName: "placeholder", publishedAt: Placeholders.date),
        contributors: ContributorRoster(contributors: [Contributor(login: "placeholder")])
    )
}
