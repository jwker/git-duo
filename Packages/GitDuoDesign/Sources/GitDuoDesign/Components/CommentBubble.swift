import SwiftUI

/// 评论气泡 —— 原型 `styles/04-screens.css` 第 32–37 行的 `.comment`（PRD §4.9 / §4.11 对话分区）。
///
/// ```css
/// .comment{display:flex;gap:9px;margin-bottom:12px}
/// .comment .bubble{flex:1;background:var(--card);border:1px solid var(--border-soft);
///                  border-radius:12px;overflow:hidden}
/// .comment .bhead{display:flex;align-items:center;gap:6px;padding:8px 12px;
///                 background:#f9fafb;border-bottom:1px solid var(--border-soft);font-size:12px}
/// .comment .bhead .author{font-weight:700}
/// .comment .bbody{padding:11px 13px;font-size:13.5px;line-height:1.6}
/// ```
///
/// ## 结构：**左头像 + 右气泡**，而气泡自己是上下两段
///
/// ```text
/// ●  ┌──────────────────────────────┐
///    │ 作者  时间          〔已批准〕│  ← bhead（浅灰底 + 下分隔线）
///    ├──────────────────────────────┤
///    │ 正文…                        │  ← bbody
///    └──────────────────────────────┘
/// ```
///
/// 头像**在气泡外**（`gap:9px` 那一栏），不在气泡的头里 —— 这条结构决定了
/// 头部的左内边距是 `12`（`padding:8px 12px`）而不是"头像宽 + 间距"。
///
/// ## 正文是**注入**的，不是这个组件画的
///
/// 原型 `.bbody` 里是 `<p>` 与 `<code>`（真 Markdown）。而 Markdown 渲染在本仓
/// 是 `MarkdownBody`，它吃的是领域模型 `[MarkdownBlock]` ⇒ 按决策 #43 **留在 Feature 层**，
/// 设计包看不到它。所以这里收一个 `@ViewBuilder`：
///
/// - 设计包不认识 Markdown，只负责"正文那一块的框与内边距"；
/// - 调用方（§4.9 / §4.11）塞 `MarkdownBody` 进来。
///
/// ⚠️ 因此**字号与行距不在这里**：原型 `.bbody{font-size:13.5px;line-height:1.6}` 那一档
/// 对应 `Font.footnote`，而 Markdown 正文另有自己的层级（`.markdown{font-size:14px}`）。
/// 由注入的内容自己决定，本组件只给 `padding:11px 13px`。
///
/// ## 头部那颗状态胶囊是可选的，且**只有一档颜色**
///
/// 原型里它是 `<span class="pill merged">{已批准}</span>` 配 `margin-left:auto`。
/// 领域层 `PullReviewState.pillTitle` **只在 `.approved` 时给文案**（其他状态给 `nil`）
/// ⇒ 这里收 `approvalTitle: String?`，`nil` 就不画，颜色恒走紫族 `.merged`。
///
/// ⚠️ 原型只画过"已批准"这一颗（`PullReviewState` 那侧也是这么定的），
/// 所以**不暴露 `tone` 参数** —— 暴露了就是在邀请别人给"请求变更"配一颗红胶囊，
/// 而那是产品还没定的口径（`TECH_SPEC §9.9`）。
///
/// ## 判据 #43：它进设计包
///
/// 收的全是基础类型（`String?` / `String`）+ 一个 `@ViewBuilder`，不认识 `IssueComment`。
/// "作者是谁、什么时间、要不要挂胶囊"是领域层 `PullTimelineItem` 算好的。
///
/// ## 底边距不在组件里
///
/// 原型 `.comment{margin-bottom:12px}` —— 那是**列表**的节奏，不是气泡自己的形状
/// （同 `CardBox` 不带 `margin-bottom` 的取舍）。调用方用 `VStack(spacing: Theme.Spacing.m)` 表达。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct CommentBubble<Body: View>: View {

    /// 登录名 —— 只用来画头像（首字母 + 确定性兜底色）。**可空**（匿名 / 已注销）。
    public let login: String?

    /// 头里显示的**作者名**。
    ///
    /// ⚠️ 它和 `login` 不是一回事：`login` 为 `nil` 时要显示的是
    /// 「已注销账号」（领域层 `AuthorName.unknown`）—— 那个词在本包不存在，
    /// 所以由调用方给成型文案，本组件不去拼。
    public let authorName: String

    /// 头里显示的时间（`2 小时前`）。同样由领域层算好。
    ///
    /// ## ⚠️ 为什么是可选（切片 7.4 改）
    ///
    /// PR 的评审**可以没有提交时间** —— `PullReviewDTO.submittedAt` 在官方 schema 里
    /// 是可空的（`PullReviewState.isPartOfConversation` 的说明写了那条判据为什么
    /// 走 `state` 而不是走时间）。那种评审仍然要画（它是讨论的一部分），
    /// 只是头部只剩一个作者名。
    ///
    /// 传空串让调用方去表达"没有时间"是不行的：`HStack(spacing: 6)` 会为那个空
    /// `Text` 多留 6pt 间隙，而"作者名右边多空了一格"看起来像排版瑕疵、
    /// 不像一条真实的缺失。**说不出来的就不说**，与 `IssueCopy.metaLabel`
    /// 那段（作者拿不到就整段去掉）是同一条口径。
    public let timeText: String?

    /// 头右侧那颗胶囊的文案。`nil` = 不画。
    public let approvalTitle: String?

    private let content: Body

    public init(
        login: String?,
        authorName: String,
        timeText: String?,
        approvalTitle: String? = nil,
        @ViewBuilder content: () -> Body
    ) {
        self.login = login
        self.authorName = authorName
        self.timeText = timeText
        self.approvalTitle = approvalTitle
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Self.avatarGap) {
            // 原型 `.avatar` 是 34×34（`UserAvatar.rowDiameter` 的默认值）。
            UserAvatar(login: login)

            VStack(alignment: .leading, spacing: 0) {
                header
                content
                    // 原型 `.bbody{padding:11px 13px}`（11 / 13 都不在 4pt 阶里 ⇒ 写原值）。
                    .padding(.vertical, 11)
                    .padding(.horizontal, 13)
            }
            // 原型 `.bubble{flex:1}` —— 气泡吃掉头像之外的全部宽度。
            .frame(maxWidth: .infinity, alignment: .leading)
            // 方案 D（2026-10-15，走查第 73 条）：白卡 → 浅灰面，边框去掉
            //（原型 `.bubble{background:var(--chip);border:none}`）。
            .background(Theme.Palette.surfaceSunken)
            // 原型 `.bubble{overflow:hidden}` + `border-radius:12px`：
            // 头部的浅灰底必须被**圆角裁掉**，否则它会从气泡的圆角外溢出来。
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.bubble, style: .continuous))
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: Self.headerGap) {
            Text(authorName)
                // 原型 `.bhead{font-size:12px}` + `.author{font-weight:700}`。
                .font(Theme.Font.commentMeta)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Palette.textPrimary)

            // 拿不到时间 ⇒ **整段不画**（不是画一个空 `Text` —— 那会留一个 6pt 的缝，
            // 见 `timeText` 的说明）。
            if let timeText, !timeText.isEmpty {
                Text(timeText)
                    // 原型 `.t3{font-size:11.5px}` —— 与页面里所有次级时间同一档。
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

            // 原型那颗胶囊带 `style="margin-left:auto"`：作者与时间靠左、胶囊靠右。
            // 无脑加一个 `Spacer` 还能让头部在"有没有胶囊"两种情况下宽度一致。
            Spacer(minLength: 0)

            if let approvalTitle {
                // 颜色恒走紫族 —— 理由见类型说明（领域层只给 `.approved` 文案）。
                StatusPill(title: approvalTitle, tone: .merged)
            }
        }
        // 原型 `padding:8px 12px`。
        .padding(.vertical, Theme.Spacing.s)
        .padding(.horizontal, Theme.Spacing.m)
        .background(Theme.Palette.bubbleHeaderSurface)
        // 原型 `border-bottom:1px solid var(--border-soft)`。
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Palette.borderSoft)
                .frame(height: 1)
        }
    }

    /// 原型 `.comment{gap:9px}`（9 不在 4pt 阶里 ⇒ 写原值）。
    public static var avatarGap: CGFloat { 9 }

    /// 原型 `.bhead{gap:6px}`（6 不在 4pt 阶里 ⇒ 写原值）。
    public static var headerGap: CGFloat { 6 }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // 最简：只有作者 + 时间 + 正文。
            CommentBubble(login: "reviewer-a", authorName: "reviewer-a", timeText: "昨天 21:40") {
                Text("真机上 `session.start()` 返回 false 后状态没有回退，按钮一直灰着。")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            // 带状态胶囊（PR 对话里的"已批准"）。
            CommentBubble(
                login: "dev-k",
                authorName: "dev-k",
                timeText: "1 小时前",
                approvalTitle: "已批准"
            ) {
                Text("导航结构 LGTM，等 fileView 的分支切换再合。")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            // 已注销账号：`login` 为 nil（头像画 `?`），作者名走领域层给的兜底文案。
            CommentBubble(login: nil, authorName: "已注销账号", timeText: "3 天前") {
                Text("（这位用户的账号已不存在）")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
