import Foundation

/// PR 详情 —— `GET /repos/{owner}/{repo}/pulls/{n}`（TECH_SPEC §9.9、PRD §4.11）。
///
/// ## 为什么它比列表项多这么多字段：**服务端只在详情里给**
///
/// `additions` / `deletions` / `changed_files` **只有单个 PR 端点返回** ——
/// 列表端点不给（决策 #58 就是被这条外部事实逼出来的）。所以
/// "卡片上顺手画个 `+842 −156`"这件事**做不到**；而详情页的「文件 {增删}」
/// 与 `{N} 个文件` 则完全拿得到。同一份数据在两个端点上的可得性不同，
/// 这也正是列表项与详情**分成两个类型**的实质理由。
///
/// ## 状态说明要的三样东西
///
/// PRD §4.11 的三句文案（`{作者} 请求合并到 {目标分支}` / `已由 {作者} 合并进 {目标分支}` /
/// `已关闭，未合并`）只用三样：`user.login`、`base.ref`、`state`（+ `mergedAt`）。
/// 判定交给 `PullRequestState.init(state:mergedAt:)` —— 那个初始化器是**唯一**判据。
///
/// ## 为什么**不收** `mergeable` / `draft` / `merged_by`
///
/// - `mergeable`：§5.3 的合并弹层**不据它禁用按钮**（原型也不）—— 合并失败的三种结局
///   由服务端的 200 / 405 / 409 回来说（§9.9），那比一个可能已经过期的布尔值可靠。
/// - `draft`：PRD 与原型都没有草稿态的任何呈现。
/// - `merged_by`：原型那句 `已由 ${pr.u} 合并进 …` 用的就是 **PR 作者**（`08-pr.js:25`），
///   不是"谁点的合并" ⇒ 没有消费端。
public struct PullDetailDTO: Sendable, Equatable, Decodable {

    /// PR 编号（仓库内唯一）。
    public let number: Int

    public let title: String

    /// 原样保留（`open` / `closed`）。**不要**直接用，走 `PullRequestState.init(state:mergedAt:)`。
    public let state: String

    /// 合并时间。**可以是 `null`**（未合并）。
    public let mergedAt: Date?

    /// 源分支（`head`）与目标分支（`base`）—— 头部那句 `feature/x → main`。
    public let head: PullRefDTO
    public let base: PullRefDTO

    /// 作者。**可以是 `null`**（账号已删除）。
    public let user: AuthorDTO?

    /// 最后更新时刻 —— 头部那句 `更新于 {时间}`。
    ///
    /// ⚠️ **可选**，理由同 `PullRequestDTO.updatedAt`：少一个时间不该让整页打不开。
    public let updatedAt: Date?

    /// 正文（Markdown 源文）。**可以是 `null`**。
    ///
    /// 与 Issue 详情同理（`IssueDetailDTO.body`）：原型把 PR 正文画成**作者发的第一条评论**，
    /// 而"空正文要不要出气泡"是领域层的判断。
    public let body: String?

    /// 改动统计 —— 「文件 {增删}」那一档与「{N} 个文件」那句提示。
    ///
    /// ⚠️ 三个都声明成**必需**：它们在详情端点上恒存在（官方 schema 里是 required）。
    /// 需要"取不到就不显示"的是**列表**那一侧（决策 #58），这里不存在那种情形。
    public let additions: Int
    public let deletions: Int

    /// 改动的文件**个数**。
    ///
    /// ⚠️ 与 `GET …/pulls/{n}/files` 那一页的 `items.count` **不是一回事**：
    /// 那个端点分页（`per_page` 默认 30），大 PR 的第一页装不下全部文件。
    /// 「{N} 个文件」这句提示要用**本字段**，不能用数组长度 —— 两者在 PR 超过一页时
    /// 都是数字、都是"文件数"，读错不会报错，只会显示一个偏小的数。
    public let changedFiles: Int

    public init(
        number: Int,
        title: String,
        state: String,
        mergedAt: Date? = nil,
        head: PullRefDTO,
        base: PullRefDTO,
        user: AuthorDTO? = nil,
        updatedAt: Date? = nil,
        body: String? = nil,
        additions: Int,
        deletions: Int,
        changedFiles: Int
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.mergedAt = mergedAt
        self.head = head
        self.base = base
        self.user = user
        self.updatedAt = updatedAt
        self.body = body
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
    }

    private enum CodingKeys: String, CodingKey {
        case number
        case title
        case state
        case mergedAt = "merged_at"
        case head
        case base
        case user
        case updatedAt = "updated_at"
        case body
        case additions
        case deletions
        case changedFiles = "changed_files"
    }
}
