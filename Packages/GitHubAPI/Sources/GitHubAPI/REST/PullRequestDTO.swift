import Foundation

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
/// ## 只声明卡片真正用到的字段
///
/// PRD §4.15 的卡片是：状态图标 + 标题 + `#N · {head} → {base}`。所以**没有**作者、
/// 没有 diff 统计、没有 `draft`。特别地：
/// - **作者不取**：原型卡片上没有作者（与 Issue 卡片不同，那个有）。
/// - **`+842 −156` 取不到**：`additions` / `deletions` 只在**单个 PR** 端点
///   （`GET /pulls/{n}`）返回，列表端点不返回 —— 这是 GitHub 的设计，不是遗漏。
public struct PullRequestDTO: Sendable, Equatable, Decodable {

    /// PR 编号（仓库内唯一）—— 卡片上的 `#57`，也是跳详情页的键。
    public let number: Int

    public let title: String

    /// 原样保留（`open` / `closed`）。**不要**直接拿它判断"已合并"，见类型说明。
    public let state: String

    /// 合并时间。**可以是 `null`**（未合并；PR 仍开着时也是 `null`）。
    public let mergedAt: Date?

    /// 源分支（`head`）与目标分支（`base`）。
    ///
    /// 只取 `ref`：那个对象里还有 `label` / `repo` / `sha` / `user` 一大堆字段，
    /// 而卡片上只需要分支名。
    ///
    /// ⚠️ 来自 **Fork 的 PR**，`head.ref` 只是 fork 里的分支名（不带 fork 的 owner）——
    /// 所以看到 `main → main` 并不意味着"自己合并自己"。原型显示的也是这里的分支名。
    public let head: Ref
    public let base: Ref

    /// **已合并**：`state == "closed"` 且带 `merged_at`（§4.6.2）。
    public var isMerged: Bool { state == "closed" && mergedAt != nil }

    public struct Ref: Sendable, Equatable, Decodable {
        public let ref: String

        public init(ref: String) {
            self.ref = ref
        }
    }

    public init(
        number: Int,
        title: String,
        state: String,
        mergedAt: Date? = nil,
        head: Ref,
        base: Ref
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.mergedAt = mergedAt
        self.head = head
        self.base = base
    }

    private enum CodingKeys: String, CodingKey {
        case number
        case title
        case state
        case mergedAt = "merged_at"
        case head
        case base
    }
}
