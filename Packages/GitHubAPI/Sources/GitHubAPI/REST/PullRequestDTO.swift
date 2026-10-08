import Foundation

/// PR 的分支引用（`head` / `base`）—— 列表项与详情**共用**这一段。
///
/// ## ⚠️ 只取 `ref`
///
/// 服务端给的对象里还有 `label` / `repo` / `sha` / `user` 一大堆字段，
/// 而界面上一共只用到一个分支名（卡片副标题 `#57 · feature/x → main`）。
/// 少声明一个字段就少一处会因为它的形状变化而炸的地方。
///
/// ## ⚠️ 来自 **Fork 的 PR**，`ref` 只是 fork 里的分支名（不带 fork 的 owner）
///
/// 所以看到 `main → main` 并不意味着"自己合并自己"。原型显示的也是这里的分支名。
public struct PullRefDTO: Sendable, Equatable, Decodable {

    public let ref: String

    public init(ref: String) {
        self.ref = ref
    }
}

/// PR 卡片 —— `GET /repos/{owner}/{repo}/pulls` 的元素（TECH_SPEC §4.6.2、§4.15）。
///
/// ## ⚠️ GitHub **没有**独立的 `merged` 状态
///
/// `state` 只有 `open` / `closed` 两个取值，合并与"关闭但没合并"在它上面**长得一模一样**。
/// 区分只能靠 `merged_at`：
/// - `state == "closed"` 且 `merged_at != null` ⇒ **已合并**
/// - `state == "closed"` 且 `merged_at == null` ⇒ 关闭但未合并
///
/// 这就是 `isMerged` 这个**派生属性**存在的理由：那条规则写在这里、引用了 §4.6.2，
/// 而每个调用点各写一次 `state == "closed" && mergedAt != nil` 的下场是
/// **总有一处漏掉 `mergedAt` 那一半** —— 于是所有被关闭的 PR 都显示成"已合并"，
/// 而这看起来完全正常。
///
/// ## 两处界面共用这一份 DTO，差异留在**消费端**（决策 #61）
///
/// | 字段 | 探索页卡片（§4.15） | 仓库详情卡片（§4.4 分区三） |
/// |---|---|---|
/// | `user` | **不画** | 画 `{作者} 更新于 {时间}` |
/// | `updatedAt` | **不画** | 同上 |
/// | 增删统计 | 无 | 想画也**没有** —— 列表端点不返回（决策 #58） |
///
/// 原型两个位置画的确实不一样（`10-explore-repo.js` 的卡片只有两行，`05-repo.js` 的多一行），
/// 但**不能**因此复制一份 DTO：一张卡片画不画某个字段是展示决定，
/// 而"这一页能不能拿到它"才是数据形状。两处共用一份、由消费端决定画什么。
///
/// ## 为什么**没有** `additions` / `deletions`
///
/// 它们**只在单个 PR 端点**（`GET /pulls/{n}`，见 `PullDetailDTO`）返回，
/// 列表端点不返回 —— 这是 GitHub 的设计，不是遗漏。PRD §4.4 分区三原本写的
/// `{作者} 更新于 {时间} · {增删}` 因此去掉第三项，且**逐条补详情请求**被否
/// （30 行 = 30 次主桶请求，滚一次列表烧一批配额 ⇒ 决策 #58）。
public struct PullRequestDTO: Sendable, Equatable, Decodable {

    /// PR 编号（仓库内唯一）—— 卡片上的 `#57`，也是跳详情页的键。
    public let number: Int

    public let title: String

    /// 原样保留（`open` / `closed`）。**不要**直接拿它判断"已合并"，见类型说明。
    public let state: String

    /// 合并时间。**可以是 `null`**（未合并；PR 仍开着时也是 `null`）。
    public let mergedAt: Date?

    /// 源分支（`head`）与目标分支（`base`）。
    public let head: PullRefDTO
    public let base: PullRefDTO

    /// 作者。**可以是 `null`** —— 账号被删除后 GitHub 把整段 `user` 置为 `null`。
    ///
    /// ⚠️ 探索页的卡片**不画**作者，仓库详情（§4.4 分区三）画 —— 差异在消费端，
    /// 见类型说明里的对照表。
    public let user: AuthorDTO?

    /// 最后更新时刻 —— 仓库详情卡片上「更新于 {时间}」那一项（决策 #61）。
    ///
    /// ⚠️ **可选**：合成的 `init(from:)` 对非可选字段缺 key 就整页解码失败，
    /// 而"少一个时间"不该值这个代价。领域层在它为 `nil` 时**整段不渲染那一截**
    /// （而不是编一句"更新于 刚刚"）。
    public let updatedAt: Date?

    /// **已合并**：`state == "closed"` 且带 `merged_at`（§4.6.2）。
    ///
    /// ⚠️ 领域层有一个**镜像**：`GitDuoKit` 的 `PullRequestState.init(state:mergedAt:)`。
    /// 本包看不见它（数据层不得引用领域层 ⇒ 依赖单向），所以同一条规则必须有两处写法；
    /// **改规则要同时改** —— 只改一处的症状是"列表里已合并、搜索结果里已关闭"。
    public var isMerged: Bool { state == "closed" && mergedAt != nil }

    public init(
        number: Int,
        title: String,
        state: String,
        mergedAt: Date? = nil,
        head: PullRefDTO,
        base: PullRefDTO,
        user: AuthorDTO? = nil,
        updatedAt: Date? = nil
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.mergedAt = mergedAt
        self.head = head
        self.base = base
        self.user = user
        self.updatedAt = updatedAt
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
    }
}
