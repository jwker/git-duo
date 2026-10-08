import Foundation
import GitHubAPI

/// 新建 Issue 页（PRD §4.10）的那份**草稿态**。
///
/// ## 为什么它不是"三个 `@State` 字符串"
///
/// 有三条规则必须只有一个落点：
///
/// 1. **标题为空时用占位标题**（§4.10）—— 那是**发出去的内容**，
///    不是界面上的话：GitHub 上那条 Issue 的标题就是它。
/// 2. **正文的"空"与"非空"** —— 一个只写了换行的正文在用户眼里就是没写，
///    而 `!body.isEmpty` 会把它发出去（讨论里多一段空白）。
/// 3. **已选标签的增删** —— 原型 `toggleLabel` 的语义是"有就去掉、没有就追加"，
///    而顺序是**选中的先后顺序**（不是字母序）：
///    标签行上那几枚胶囊的顺序换了不会报错，只会让人以为"它自己重排了"。
///
/// 散进视图就会变成三处各自实现，而三处都"看起来正常"。
///
/// ⚠️ **正文不做 trim**（与标题不同）：前导缩进在 Markdown 里是有意义的，
/// 裁掉会把一段代码块变成一个普通段落 —— 那是一次**悄悄改用户内容**的错误。
/// 标题是单行，前后空格是噪声，trim 是对的（原型也 trim）。
public struct NewIssueDraft: Sendable, Hashable {

    /// 用户输入的标题（原样保存，含前后空格）。
    public var title: String

    /// 用户输入的正文（原样保存，**不 trim**）。
    public var body: String

    /// 已选标签，**顺序 = 选中的先后顺序**（原型 `niLabels` 的 push 顺序）。
    public var labels: [Label]

    public init(title: String = "", body: String = "", labels: [Label] = []) {
        self.title = title
        self.body = body
        self.labels = labels
    }

    /// 进页面时的空草稿（§4.10「进入页面时重置已选标签并渲染标签行」）。
    ///
    /// 写成工厂而不是让调用方 `NewIssueDraft()`：将来多一个字段时，
    /// 想要"重置"的地方会漏掉它，而漏掉的表现是**上一次填的内容留在新页面上**。
    public static var empty: NewIssueDraft { NewIssueDraft() }

    /// 真正发出去的标题 —— 空（或只有空白）时用占位标题（§4.10）。
    public var effectiveTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? IssueCopy.placeholderTitle : trimmed
    }

    /// 真正发出去的正文。
    ///
    /// - 去掉首尾空白后为空 ⇒ `nil`（**不带这个字段**，而不是发一个空串）。
    /// - 否则 ⇒ **原样的 `body`**（不 trim，见类型说明）。
    public var effectiveBody: String? {
        let probe = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return probe.isEmpty ? nil : body
    }

    /// 真正发出去的标签名列表（顺序即胶囊顺序）。
    public var effectiveLabelNames: [String] {
        labels.map(\.name)
    }

    /// 已选 / 取消一个标签（原型 `toggleLabel` 的语义）。
    public mutating func toggle(_ label: Label) {
        if let index = labels.firstIndex(where: { $0.name == label.name }) {
            labels.remove(at: index)
        } else {
            labels.append(label)
        }
    }

    /// 这个标签当前选中没有（弹层里那枚 `✓` 的判据）。
    public func isSelected(_ label: Label) -> Bool {
        labels.contains { $0.name == label.name }
    }
}

/// 新建 Issue 的接缝 —— 由 `GitHubAPI` 的 `GitHubRepoIssuesEndpoint` 空扩展体满足。
///
/// ⚠️ 为什么不并进 `RepoIssuesDataSource`：见 `IssueCommentPosting` 的说明。
public protocol IssueComposerDataSource: Sendable {

    /// `POST /repos/{o}/{r}/issues`。
    ///
    /// ⚠️ 传进来的 `title` / `body` / `labels` 都是**已经决定好的值**：
    /// "标题为空用占位标题"那条规则在 `NewIssueDraft.effectiveTitle`，
    /// 数据层不该有产品文案。
    func createIssue(
        owner: String,
        repo: String,
        title: String,
        body: String?,
        labels: [String]
    ) async throws -> IssueDetailDTO
}

/// 让真实端点满足上面的接缝。空扩展体能成立，靠的是**方法签名逐字一致**。
extension GitHubRepoIssuesEndpoint: IssueComposerDataSource {}

/// 建成的那条 Issue（给提示条用）。
public struct CreatedIssue: Sendable, Hashable {

    /// 服务端分配的编号 —— 提示里的 `#43`，也是"要不要跳进它"的键。
    public let number: Int

    /// **服务端回的那个标题**。
    ///
    /// ⚠️ 不是本地那份 `effectiveTitle`：两者正常时相同，而不同的那一次
    /// （服务端有它自己的规范化）才正是我们想看见的 —— 提示条说"已创建
    /// 「A」"、而 GitHub 上叫 B，是用户发现问题的唯一线索。
    public let title: String

    /// 带上去的标签个数。
    ///
    /// ⚠️ 来自**本地已选集合**，不是响应体 —— `IssueDetailDTO` 里**没有** `labels`
    /// （它的类型说明写了为什么）。代价是：万一服务端丢掉了某个标签
    /// （比如那个标签在别处被删了），这个数会多算一个。这一处的取舍是照原型
    /// （`niLabels.length`），而"多算一个"比"为了一个数再去拉一次详情"轻得多。
    public let labelCount: Int

    public init(number: Int, title: String, labelCount: Int) {
        self.number = number
        self.title = title
        self.labelCount = labelCount
    }

    /// 成功提示：`已创建 Issue #43 · “标题” · 标签 3 个`。
    public var toastMessage: String {
        IssueCopy.createdToast(number: number, title: title, labelCount: labelCount)
    }
}

/// 提交新建 Issue（PRD §4.10、TECH_SPEC §9.8）。
public struct CreateIssue: Sendable {

    private let source: any IssueComposerDataSource

    public init(source: any IssueComposerDataSource) {
        self.source = source
    }

    /// - Parameters:
    ///   - draft: 页面上那份草稿。取 `effectiveTitle` / `effectiveBody` /
    ///     `effectiveLabelNames` 发出 —— 三条规则都在草稿里，本用例不再判一次
    ///     （判两次的下场是两处总有一天不一致）。
    ///
    /// - Returns: 服务端回的那条 Issue。⚠️ **返回编号是真去跳详情 / 显示提示用的**，
    ///   所以它必须来自响应体，不能靠"本地计数 +1"猜。
    public func submit(fullName: String, draft: NewIssueDraft) async throws -> CreatedIssue {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let dto = try await source.createIssue(
            owner: owner,
            repo: repo,
            title: draft.effectiveTitle,
            body: draft.effectiveBody,
            labels: draft.effectiveLabelNames
        )
        return CreatedIssue(
            number: dto.number,
            title: dto.title,
            labelCount: draft.labels.count
        )
    }
}
