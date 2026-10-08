import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 讨论流里的**一条**：`CommentBubble` + 注入的紧凑版 Markdown 正文。
///
/// ## 为什么要有这一件（§4.9 与 §4.11 两处共用）
///
/// 两个详情页的评论区是**同一件事**：同一种气泡、同一档正文版式、同一个"正文由
/// `MarkdownBody` 渲染"的接法。各写一遍的下场不是多几行 ——
/// 是"评论正文字号改一档"只落到其中一页，而另一页看起来也没错。
///
/// 与 `IssueCard` / `PullCard` 搬迁（决策 #61）是同一条判据、同一种做法。
///
/// ## ⚠️ 两处正文的差异是**零**，不是"差不多"
///
/// | | §4.9 Issue 评论 | §4.11 PR 对话 |
/// |---|---|---|
/// | 气泡 | `CommentBubble` | 同 |
/// | 正文版式 | `MarkdownBody(.compact)` | 同 |
/// | 时间 | `IssueComment.timeLabel(now:)` | `PullTimelineItem.timeLabel(now:)` |
/// | 「已批准」胶囊 | 无（Issue 没有评审） | 有（`approvalTitle`） |
///
/// 差别只在最后一行，而它是**参数**（`approvalTitle`）而不是另一种版式。
///
/// ## 判据 #43：它留 Feature
///
/// 入参里有 `[MarkdownBlock]`（领域模型）⇒ 它认识业务。
/// `MarkdownBody` 本身也在这一层（设计包看不见 Markdown 模型），
/// 所以"气泡 + 正文"这个组合只能在这里出现 —— `CommentBubble` 的注入接口
/// 正是为这件事留的。
///
/// ## 五段文字全部由调用方给
///
/// 本件**一个中文字都不产生**：作者名走 `displayAuthor`、时间走 `timeLabel(now:)`、
/// 胶囊走 `approvalPill`，都是领域层算好的可测数据（同 `ConversationHeader`）。
struct CommentRow: View {

    /// 登录名 —— 只用来画头像（首字母 + 派生底色）。**可空**（账号已删除）。
    let login: String?

    /// 头部显示的**作者名**（不是 `login`：账号删了要写 `AuthorName.unknown`）。
    let authorName: String

    /// 头部显示的时间。**`nil` = 不画**（评审可能没有提交时间）。
    let timeText: String?

    /// 头部右侧那颗「已批准」胶囊。`nil` = 不画。
    let approvalTitle: String?

    /// 正文（已经解析好的块）。
    let blocks: [MarkdownBlock]

    /// ⚠️ **必须手写**，不能用自动的 memberwise init。
    ///
    /// 自动那一个**不会**给 `let approvalTitle: String?` 一个 `nil` 默认值
    /// （只有 `var` 可选属性才会被隐式初始化）⇒ 每一处 Issue 侧的调用
    /// （那里根本没有评审）都必须显式写 `approvalTitle: nil`。
    /// 那不是"多写一个词"，那是一处**随时会被漏掉、而漏掉之后编译不过**的噪声。
    ///
    /// 同 `CommentBubble.init` 收 `approvalTitle: String? = nil` 的理由。
    init(
        login: String?,
        authorName: String,
        timeText: String? = nil,
        approvalTitle: String? = nil,
        blocks: [MarkdownBlock]
    ) {
        self.login = login
        self.authorName = authorName
        self.timeText = timeText
        self.approvalTitle = approvalTitle
        self.blocks = blocks
    }

    var body: some View {
        CommentBubble(
            login: login,
            authorName: authorName,
            timeText: timeText,
            approvalTitle: approvalTitle
        ) {
            // `.compact` 档：无卡片框、13pt、**零内边距** ——
            // 内边距由 `CommentBubble` 的注入槽给（原型 `.bbody{padding:11px 13px}`
            // 只有这一处出处，见 `MarkdownBody.Style` 的说明）。
            MarkdownBody(blocks: blocks, style: .compact)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
        CommentRow(
            login: "reviewer-a",
            authorName: "reviewer-a",
            timeText: "昨天",
            blocks: MarkdownParser.blocks(from: """
            真机上 `session.start()` 返回 false 后状态没有回退，按钮一直灰着。建议补上返回值检查。
            """)
        )
        // PR 侧那一档：多一颗「已批准」胶囊。
        CommentRow(
            login: "dev-k",
            authorName: "dev-k",
            timeText: "1 小时前",
            approvalTitle: "已批准",
            blocks: MarkdownParser.blocks(from: """
            导航结构 LGTM，等 `fileView` 的分支切换再合。
            """)
        )
        // 两条**都会遇到**的缺一半：
        // ① 评审没有提交时间（`submitted_at` 可空）；
        // ② 账号已删除（`login` 与 `authorLogin` 都为 nil）。
        CommentRow(
            login: nil,
            authorName: "已注销账号",
            timeText: nil,
            blocks: MarkdownParser.blocks(from: "（这位用户的账号已不存在）")
        )
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
