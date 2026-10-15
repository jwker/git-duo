import GitHubAPI
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// Issue 详情页（PRD §4.9、TECH_SPEC §9.8、决策 #57 / #59 / #62）。
///
/// 结构：头部卡（状态胶囊 + 说明 + 标题 + 元信息）→ 正文气泡 → 评论流 →
/// 发送失败提示条 → 评论输入区。
///
/// ## ⚠️ 正文是**第一条气泡**，不是另一块卡片
///
/// 原型 `06-files.js:122-128` 把 Issue 的正文画成作者发的第一条 `.comment`
/// （头像 + 作者 + 时间 + 正文），而不是一个独立的"正文卡"。
/// 所以这一页的气泡流是 `[正文气泡?] + [评论列表]` —— 而"要不要出正文气泡"
/// 走 `IssueDetail.hasBody`（那条判断在领域层，理由写在那里）。
///
/// 两者在版式上**完全一样**（同一个 `CommentRow`），所以它们之间没有任何分隔线或
/// 分组标题 —— 这也正是原型的样子。
///
/// ## ⚠️ 提示条在输入区**下方**（原型与 PRD 的结构列表一致）
///
/// PRD §4.9 内部有一处自相矛盾：「交互」那一段写"在输入区**上方**显示红色提示条"，
/// 而它自己的「结构」列表（第 4 条）与原型 `06-files.js:140`（`#sendErr` 排在
/// `.composer` 之后、还带一个 `margin-top:8px`）都指向**下方**。
///
/// 按 `AGENTS.md §1` 的优先级（**原型 > TECH_SPEC > PRD**）取下方，
/// 已登记为有意偏差。
///
/// ## ⚠️ 评论为空时**什么都不画**
///
/// 原型与 PRD 都没有"还没有评论"这一档（原型的演示数据固定两条）⇒ 规格未给。
/// 这里不新造文案：正文气泡下面直接是输入区，读起来很自然
/// （一个只有正文、还没人回复的 Issue 本来就该长这样）。已登记。
///
/// ## ⚠️ 操作区在评论流**下方**、提示条**上方**（PRD §4.9 结构第 5 条）
///
/// 位置与 `PullDetailView` 那一处逐字对齐：正文气泡 → 评论流 → **操作区** → 提示条 → 输入区。
///
/// 三档判据**只有一处**（`IssueOperationAvailability.decide`，经
/// `IssueDetail.operationAvailability(readOnly:viewerLogin:)` 进来）—— 本件只画，
/// 不在这边再写一次 `if readOnly`。
///
/// ⚠️ **`readOnly` 不等于"整页只读"**（决策 #79）：它只是入口那半个条件，
/// 另外半个来自详情自己（"这条 Issue 是不是我提的"）。「我的 Issue」那一屏里
/// 每条都是我提的 ⇒ 哪怕入口传的是 `readOnly: true`，这一页照样给得出「关闭 Issue」。
///
/// ### 那颗按钮的**样式**照 PR 详情页逐档对齐（规格未给）
///
/// PRD §4.9 只写了有哪两颗按钮，没写用什么样式；原型连操作区都没有。
/// 于是取同一族里已经在做同一件事的那一页（`PullDetailView.operations`）：
/// **关闭 = `.ghost`、重新打开 = `.primary`**。
/// 理由不只是"照抄"：`.primary` 在本项目里是**推荐的主操作**（合并 PR、
/// 提交表单那一类），而关闭一条 Issue 不是 —— 它甚至不是破坏性的
/// （§5.18 特意不用红底），只是把这条从活跃列表里移开。
/// 同一族的两页在做同一件事时长得不一样，比"少一条规格"更糟。
///
/// ## 它是内容层
///
/// 全部实色，**不加 Liquid Glass**（§10.2）。
struct IssueDetailView: View {

    let fullName: String
    let number: Int

    /// 入口给的**保守可写性**（铁律 #7）。⚠️ 它的含义见 `Route.issueDetail` 的说明：
    /// 只表示"这个入口假定我没有仓库写权限"，**不是**"整页只读" ——
    /// 最终判据还要并上"我是不是这条 Issue 的作者"（决策 #79）。
    let readOnly: Bool

    /// 当前登录名，用来判"这条 Issue 是不是我提的"。
    ///
    /// ⚠️ 由 `RouteView` 从 `authState` 取（**不再打一次 `/user`**，同 §9.15 那条口径）。
    /// `nil` 时判不出作者身份 ⇒ 取保守侧（少给一颗按钮，不给一颗点下去必 403 的）。
    let viewerLogin: String?

    @State private var model: IssueDetailViewModel

    /// 「现在」只在**进页与刷新时**取一次（同 `CommitDetailView`）——
    /// 在 `body` 里取 `Date()` 会让"相对时间"变成渲染时机的一部分。
    @State private var now = Date()

    init(
        fullName: String,
        number: Int,
        readOnly: Bool,
        viewerLogin: String?,
        loader: LoadIssueDetail,
        sender: PostIssueComment,
        actions: IssueAction,
        drafts: any CommentDraftStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.number = number
        self.readOnly = readOnly
        self.viewerLogin = viewerLogin
        _model = State(initialValue: IssueDetailViewModel(
            fullName: fullName,
            number: number,
            loader: loader,
            sender: sender,
            actions: actions,
            drafts: drafts,
            toast: toast
        ))
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        // 原型 `SCR.issueDetail` 的 `inline:p=>'#${p.n}'`。
        .navigationTitle("#\(number)")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            now = Date()
            await model.refresh()
            now = Date()
        }
        .task {
            now = Date()
            await model.start()
            // 取完之后再对一次表：网速慢时"2 天前"可能已经跨过了一个整点。
            now = Date()
        }
        .sheet(item: $model.sheet) { route in
            switch route {
            case .closeConfirm:
                CloseIssueSheet {
                    // ⚠️ **先关弹层、再发请求**（同 `MergePRSheet` 与设置页那张）：
                    //    提示条挂在根容器上，弹层盖着时弹出的提示用户看不见。
                    //    在途状态由操作区那颗按钮表达（`model.isWorking`）。
                    model.sheet = nil
                    Task { await model.close() }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - 主区域

    @ViewBuilder
    private var content: some View {
        switch model.detail.presentation {
        case .skeleton:
            skeleton

        case .content:
            if let detail = model.detail.value {
                // 原型各块之间是 `margin-bottom:12px` ⇒ `Spacing.m`。
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ConversationHeader(
                        stateTitle: detail.pillTitle,
                        stateTone: StateTone.tone(isOpen: detail.isOpen),
                        note: detail.headNote(now: now),
                        title: detail.title,
                        meta: detail.metaLabel(fullName: fullName, now: now)
                    )

                    if detail.hasBody {
                        bodyBubble(detail)
                    }

                    commentsSection

                    operations(detail)

                    if let notice = model.sendNotice {
                        NoticeBar(text: notice)
                    }

                    composer
                }
            }

        case let .failure(error):
            PageFailure(error: error) { Task { await model.refresh() } }
        }
    }

    // MARK: - 正文气泡

    private func bodyBubble(_ detail: IssueDetail) -> some View {
        CommentRow(
            login: detail.authorLogin,
            authorName: detail.displayAuthor,
            timeText: detail.bodyTimeLabel(now: now),
            blocks: detail.bodyBlocks
        )
    }

    // MARK: - 评论流

    @ViewBuilder
    private var commentsSection: some View {
        switch model.comments {
        case .idle, .loading:
            // ⚠️ 只有在**详情已经出来之后**才会走到这里（详情没出来时整页是骨架）。
            //    评论慢一步到 ⇒ 这一块单独转圈，而不是把已经画好的头部擦掉重来。
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(0..<2, id: \.self) { _ in bubbleSkeleton }
            }
            .accessibilityHidden(true)

        case .loaded:
            // ⚠️ 空数组**什么都不画**（规格未给，见类型说明）——
            //    这里不能落进一个 `if isEmpty` 分支去画空态。
            ForEach(model.commentItems) { comment in
                CommentRow(
                    login: comment.authorLogin,
                    authorName: comment.displayAuthor,
                    timeText: comment.timeLabel(now: now),
                    blocks: comment.bodyBlocks
                )
            }

        case let .failed(error):
            // **降级**：正文与头部照常显示，只有这一块是失败态（决策 #57）。
            SectionFailure(error: error) { Task { await model.retryComments() } }
        }
    }

    // MARK: - 操作区

    /// 三档（`IssueOperationAvailability`）。判据只有一处，本件只画。
    ///
    /// ⚠️ 那一行只读提示**不是**探索 Issues 列表的页脚（两句只差一个分隔符，
    /// 说的却不是一件事）—— 取舍写在 `IssueCopy.readOnlyHint` 的文档里。
    @ViewBuilder
    private func operations(_ detail: IssueDetail) -> some View {
        // 判据只算一次（`decide` 是纯函数，算两遍不会不一致，但读起来像有两处判据）。
        let availability = detail.operationAvailability(readOnly: readOnly, viewerLogin: viewerLogin)

        switch availability {
        case .readOnly:
            // 原型 `08-pr.js:50` 那个 `t3` + `text-align:center;padding:10px 0 0`
            // —— 与 PR 详情页那一处取同一档（`PullDetailView.operations` 的 `.readOnly`）。
            Text(IssueCopy.readOnlyHint)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

        case .close, .reopen:
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                // PR 详情页操作区那个 `.section-label` 自带 16/2/8 外边距 ⇒ 用默认档。
                // ⚠️ 标题复用 PR 那一串（`PullCopy.operationsSectionTitle`）：同一块东西、
                //    同一个词，再写一个 `IssueCopy` 的副本只会多一处将来要同步的字。
                SectionHeader(title: PullCopy.operationsSectionTitle)

                if availability == .close {
                    ActionButton(
                        title: IssueCopy.closeAction,
                        style: .ghost,
                        // 那两颗满宽按钮在原型的 PR 页上都是 `padding:12px` ⇒ 取同一档。
                        verticalPadding: 12,
                        // 在途（确认之后请求还在飞）⇒ 按钮内联转圈 + 防重复提交。
                        isWorking: model.isWorking
                    ) {
                        model.sheet = .closeConfirm
                    }
                } else {
                    ActionButton(
                        title: IssueCopy.reopenAction,
                        style: .primary,
                        verticalPadding: 12,
                        isWorking: model.isWorking
                    ) {
                        // ⚠️ **不弹确认**，直接发（PRD §4.9 操作区末条）。
                        Task { await model.reopen() }
                    }
                }
            }
        }
    }

    // MARK: - 输入区

    private var composer: some View {
        // ⚠️ 按定义留一份，不放 Spacer：`Sendable` 的闭包不能直接捕获 `model`
        //    （它是 `@MainActor` 隔离的），起一个 `Task` 才是对的。
        CommentComposer(
            text: $model.draft,
            placeholder: IssueCopy.commentPlaceholder,
            sendTitle: ConversationCopy.sendAction,
            isSending: model.isSending
        ) {
            Task { await model.send() }
        }
    }

    // MARK: - 骨架

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // 头部卡：胶囊 + 说明那一行、标题、元信息行 —— 三行，与 `ConversationHeader`
            // 的三行一一对应（骨架的用处就是让"东西来了之后"不发生跳动）。
            CardBox() {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SkeletonBar(height: 11, width: 120)
                    SkeletonBar(height: 17, width: 260)
                    SkeletonBar(height: 11, width: 200)
                }
            }

            ForEach(0..<2, id: \.self) { _ in bubbleSkeleton }

            // 输入区。
            SkeletonBar(height: 58, width: nil)
        }
        .accessibilityHidden(true)
    }

    /// 一条评论 / 正文气泡的骨架。
    ///
    /// ⚠️ 它**不画头像** —— 骨架的作用是占位与定高，不是把成品预先画一遍。
    /// 形状（圆角 `Radius.bubble` + 1pt 浅边 + 内边距 `m`）与 `CommentBubble` 的
    /// 气泡那一半对齐，所以真内容到来时整块的位置不会跳。
    private var bubbleSkeleton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SkeletonBar(height: 11, width: 120)
            SkeletonBar(height: 13, width: nil)
            SkeletonBar(height: 13, width: 180)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 方案 A：气泡是**白卡**（与 `CommentBubble` 一致：圆角 18、无边框）。
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous)
                .fill(Theme.Palette.surface)
        )
    }
}

#Preview {
    @Previewable @State var environment = AppEnvironment()
    NavigationStack {
        IssueDetailView(
            fullName: "my-git/gitduo",
            number: 42,
            // 自己的仓库 ⇒ 操作区会出「关闭 Issue」（换成 `true` 且 `viewerLogin` 换个名字，
            // 就能看到底那一行只读提示）。
            readOnly: false,
            viewerLogin: "jiangjiang",
            loader: environment.issueDetail,
            sender: environment.postIssueComment,
            actions: environment.issueAction,
            drafts: environment.commentDrafts,
            toast: environment.toast
        )
    }
    .environment(environment)
}
