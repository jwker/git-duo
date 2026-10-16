import GitHubAPI
import GitDuoCore
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// PR 详情页（PRD §4.11、TECH_SPEC §9.9、决策 #57 / #59 / #60）。
///
/// 结构：头部卡（状态胶囊 + 说明 + 标题 + 元信息）→ 三分区条
/// （对话 / Commits / 文件 +842 −156）→ 当前分区的内容。
///
/// ## ⚠️ 骨架期是**整页**骨架（含分段条）
///
/// 第三格的标题带着增删统计（`文件 +842 −156`），而那个数**只有详情端点给**
/// （决策 #58）⇒ 详情还没到手时那三个字拼不出来。先画一条只写"文件"的分段条、
/// 等数据到了再把统计补上去，会让那几格在眼前跳一下。
/// 仓库详情那边分段条能先画，是因为它的四格标题不依赖任何数据
/// （`PullSection` 的类型说明写了这一段）。
///
/// ## ⚠️ 三个分区各有各的取数节奏
///
/// 首屏只取**详情 + 对话**；Commits 与文件**进那一格才取**（§9.9：
/// 一个数百文件的 PR 一开页就把 100 段 diff 全拉回来是不可接受的）。
/// 三条路径画的东西也各自独立 —— 对话失败不影响头部，文件失败不影响对话。
///
/// ## ⚠️ 正文是**第一条气泡**（与 §4.9 同一处置）
///
/// 原型 `08-pr.js:30-34` 把 PR 正文画成作者发的第一条 `.comment`，
/// 所以这里的对话区是 `[正文气泡?] + [评论与评审合成的时间线]`。
/// 走 `PullDetail.hasBody` 判断要不要出那一条，版式用的是同一个 `CommentRow`。
///
/// ## ⚠️ 一处**有意偏离原型**：文件分区的 diff 卡片默认**收起**
///
/// 原型的三个卡片都带 `open` 类（默认展开）—— 但那三个是演示数据，
/// 它一次都没渲染过收起态。而 PRD §4.11 的分区提示逐字是
/// 「`{N} 个文件 · 点击文件卡片展开 diff`」，`TECH_SPEC §9.9` 更直接写明
/// 「即**折叠态按需渲染** —— 正好配合 diff 解析的惰性化（大 PR 只解析可见文件）」。
/// 展开态进这一格会让 100 个文件的 `patch` 在 `onAppear` 里**同时**解析一遍，
/// 那正是 §11.2 要避免的。已登记在 `REVIEW-CHECKLIST §6`。
///
/// ## 它是内容层
///
/// 全部实色，**不加 Liquid Glass**（§10.2）。
struct PullDetailView: View {

    let fullName: String
    let number: Int

    /// 只读态（他人仓库）—— **由路由给**（铁律 #7）。
    let readOnly: Bool

    /// ★ 拼提交详情的路由要用它（分区二的行点进去是提交详情，**透传只读态**）。
    @Environment(AppEnvironment.self) private var env

    @State private var model: PullDetailViewModel

    /// 「现在」只在**进页与刷新时**取一次（同 `IssueDetailView`）——
    /// 在 `body` 里取 `Date()` 会让"相对时间"变成渲染时机的一部分。
    @State private var now = Date()

    /// 合并弹层开没开。
    ///
    /// ⚠️ 只此一张，所以用 `isPresented`；出现第二张时就该换成
    /// `Identifiable` 枚举驱动（`RepoDetailView` 的说明写了为什么）。
    @State private var isMerging = false

    init(
        fullName: String,
        number: Int,
        readOnly: Bool,
        loader: LoadPullDetail,
        actions: PullAction,
        sender: PostIssueComment,
        drafts: any CommentDraftStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.number = number
        self.readOnly = readOnly
        _model = State(initialValue: PullDetailViewModel(
            fullName: fullName,
            number: number,
            readOnly: readOnly,
            loader: loader,
            actions: actions,
            sender: sender,
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
        // 原型 `SCR.prDetail` 的 `inline:p=>'#${p.n}'`。
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
        .sheet(isPresented: $isMerging) { mergeSheet }
    }

    // MARK: - 主区域

    @ViewBuilder
    private var content: some View {
        switch model.detail.presentation {
        case .skeleton:
            skeleton

        case .content:
            if let detail = model.detail.value {
                loaded(detail)
            }

        case let .failure(error):
            PageFailure(error: error) { Task { await model.refresh() } }
        }
    }

    /// 有内容那一档 —— 抽成函数是为了让**骨架与内容走同一份布局**
    /// （NATIVE-MIGRATION P1：骨架 = 这份布局 + 占位数据 + `.redacted`）。
    private func loaded(_ detail: PullDetail) -> some View {
        // 原型各块之间是 `margin-bottom:12px` ⇒ `Spacing.m`。
        VStack(alignment: .leading, spacing: 0) {
            ConversationHeader(
                stateTitle: detail.state.pillTitle,
                stateTone: StateTone.tone(for: detail.state),
                note: detail.headNote(now: now),
                title: detail.title,
                meta: detail.metaLabel(now: now)
            )

            sectionTabs(detail)
                .padding(.top, Theme.Spacing.m)

            sectionBody(detail)
        }
    }

    // MARK: - 三分区条

    /// ⚠️ 第三格的标题**要数据**（`文件 +842 −156`）⇒ 走 `title(stats:)`（必传）。
    ///
    /// ⚠️ 2026-10-16（P2）：这里从 `SectionTabs`（本仓自绘的等分切换条）换成了
    /// `SegmentedBar` —— 两者在 P2 之后内胆都是官方的 `Picker(.segmented)`，
    /// **形状已经完全没有差别**，留着两份实现只会让"改一处忘了另一处"迟早发生。
    /// `SectionTabs` 已删除（它生前只有这一个调用点）。
    private func sectionTabs(_ detail: PullDetail) -> some View {
        SegmentedBar(
            // 顺序走 `allCases`，不写数组（`PullSection` 的说明）。
            segments: PullSection.allCases.map {
                SegmentedBar.Segment(id: $0.rawValue, title: $0.title(stats: detail.statsLabel))
            },
            selectedID: model.segment.rawValue,
            // 本件在已经内缩的内容区里（同 §4.4 两段）。
            padsHorizontally: false
        ) { picked in
            guard let section = PullSection(rawValue: picked.id) else { return }
            Task { await model.select(segment: section) }
        }
        // 原型 `.prtabs{margin-bottom:12px}`。
        .padding(.bottom, Theme.Spacing.m)
    }

    @ViewBuilder
    private func sectionBody(_ detail: PullDetail) -> some View {
        switch model.segment {
        case .conversation:
            conversation(detail)
        case .commits:
            commits
        case .files:
            files(detail)
        }
    }

    // MARK: - 分区一：对话

    private func conversation(_ detail: PullDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // 已合并时顶部那条信息条（未合并 ⇒ 不画）。
            if let banner = model.mergedBanner(now: now) {
                lockedBanner(banner)
            }

            // 正文 = 作者发的第一条评论（见类型说明）。
            if detail.hasBody {
                CommentRow(
                    login: detail.authorLogin,
                    authorName: detail.displayAuthor,
                    timeText: detail.bodyTimeLabel(now: now),
                    blocks: detail.bodyBlocks
                )
            }

            conversationList

            operations(detail)

            // ⚠️ **已合并 ⇒ 整个输入区不显示**（讨论已锁定，§4.11 表格最后一行）。
            //    判据走 `PullDetail.canComment` —— 它在领域层由状态派生，
            //    这里不再写一次 `state != .merged`。
            if detail.canComment {
                if let notice = model.sendNotice {
                    NoticeBar(text: notice)
                }
                composer
            }
        }
    }

    /// 「已由 X 于 {时间} 合并进 main · 讨论已锁定」。
    ///
    /// ⚠️ 它是**原型那种一行实色块**（`08-pr.js:48`：`background:var(--chip)`、
    /// 圆角 9、`padding:9px 12px`、12.5px `--text2`），不是 `NoticeBar` ——
    /// 后者借的是 diff 删除那一对**红**色，含义是"出问题了"。
    /// 这一条说的是"这件事已经结束了"，用红底会在屏幕上说反话。
    private func lockedBanner(_ text: String) -> some View {
        Text(text)
            // 原型 12.5px ⇒ 与 `NoticeBar` 取同一档（那处的说明写了为什么不取 `caption`：
            // 12.5 在本项目有两处先例，`footnote` 是语义最近的一档）。
            .font(Theme.Font.footnote)
            .foregroundStyle(Theme.Palette.textSecondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 原型 `padding:9px 12px` ⇒ 垂直最近一档 `s`(8)、水平正好 `m`(12)。
            .padding(.vertical, Theme.Spacing.s)
            .padding(.horizontal, Theme.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.Palette.surfaceSunken)
            )
    }

    @ViewBuilder
    private var conversationList: some View {
        switch model.conversation {
        case .idle, .loading:
            // ⚠️ 只有在**详情已经出来之后**才会走到这里（详情没出来时整页是骨架）。
            //    对话慢一步到 ⇒ 这一块单独转圈，而不是把已经画好的头部擦掉重来。
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(0..<2, id: \.self) { _ in bubbleSkeleton }
            }
            .accessibilityHidden(true)

        case .loaded:
            // ⚠️ 空数组**什么都不画**（规格未给：原型的数据固定两条）——
            //    下面直接就是操作区与输入区，读起来很自然。
            ForEach(model.timelineItems) { item in
                // ⚠️ 「已批准」胶囊来自**评审**、不是评论本身（决策 #60）——
                //    它由 `PullTimelineItem.approvalPill` 给，本件不判断来源。
                CommentRow(
                    login: item.authorLogin,
                    authorName: item.displayAuthor,
                    timeText: item.timeLabel(now: now),
                    approvalTitle: item.approvalPill,
                    blocks: item.bodyBlocks
                )
            }

        case let .failed(error):
            // **降级**：头部、正文与操作区照常显示，只有这一块是失败态（决策 #57）。
            SectionFailure(error: error) { Task { await model.retryConversation() } }
        }
    }

    // MARK: - 操作区

    /// 四档（`PullOperationAvailability`）。
    ///
    /// ⚠️ 判据**只有一处**（`PullOperationAvailability.decide`），本件只画。
    /// 它同时管着"评论输入区在不在"（已合并 ⇒ 锁上），所以那一处也走同一个枚举 ——
    /// 两处各写一遍 `if` 的下场是"他人仓库里一个已合并的 PR"只落到其中一种表现上。
    @ViewBuilder
    private func operations(_ detail: PullDetail) -> some View {
        // 判据只算一次（`decide` 是纯函数，算两遍不会不一致，但读起来像有两处判据）。
        let availability = detail.operationAvailability(readOnly: readOnly)

        switch availability {
        case .readOnly:
            // 原型 `style="text-align:center;padding:10px 0 0"`。
            Text(PullCopy.readOnlyHint)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

        case .mergeAndClose, .reopen:
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                // 原型这里也是一个 `.section-label`（自带的 16/2/8 外边距）⇒ 用默认档。
                SectionHeader(title: PullCopy.operationsSectionTitle)

                if availability == .mergeAndClose {
                    ActionButton(
                        title: PullCopy.mergeAction,
                        style: .primary,
                        // 原型 `style="width:100%;padding:12px"`。
                        // 在途（点完确认之后请求还在飞）⇒ 按钮内联转圈 + 防重复提交。
                        isWorking: model.isWorking
                    ) {
                        isMerging = true
                    }

                    ActionButton(
                        title: PullCopy.closeAction,
                        style: .ghost,
                        // 原型 `style="width:100%;padding:12px;margin-top:8px"` ⇒
                        // 那个 8 由外层 `spacing: Spacing.s` 给。
                        isWorking: model.isWorking
                    ) {
                        Task { await model.close() }
                    }
                } else {
                    ActionButton(
                        title: PullCopy.reopenAction,
                        style: .primary,
                        isWorking: model.isWorking
                    ) {
                        Task { await model.reopen() }
                    }
                }
            }

        case .noOperations:
            // 自己的仓库 + 已合并：**什么按钮都没有**，也**没有**那句 readOnly 提示
            // （两者的区别在屏幕上就是"有没有那句话"）。
            EmptyView()
        }
    }

    // MARK: - 输入区

    private var composer: some View {
        // ⚠️ 按定义留一份，不放 Spacer：`Sendable` 的闭包不能直接捕获 `model`
        //    （它是 `@MainActor` 隔离的），起一个 `Task` 才是对的。
        CommentComposer(
            text: $model.draft,
            placeholder: PullCopy.commentPlaceholder,
            sendTitle: ConversationCopy.sendAction,
            isSending: model.isSending
        ) {
            Task { await model.send() }
        }
    }

    // MARK: - 分区二：Commits

    @ViewBuilder
    private var commits: some View {
        switch model.commits {
        case .idle, .loading:
            // ⚠️ 与 `RepoSectionListView.commitsSkeleton` 同款（NATIVE-MIGRATION P1）：
            //    画**真实的提交行** + 占位 + `.redacted`，不再手抄"头像 28 + 两行字 + 徽章"。
            CardBox() {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<4, id: \.self) { index in
                        RepoCommitRow(
                            commit: .placeholder,
                            now: now,
                            showsSeparator: index < 3,
                            action: {}
                        )
                    }
                }
            }
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

        case .loaded:
            // ⚠️ 空数组什么都不画（一个 PR 必然至少有一个提交；规格未给空态）。
            if !model.commitRows.isEmpty {
                CardBox() {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.commitRows.enumerated()), id: \.element.id) { index, commit in
                            RepoCommitRow(
                                commit: commit,
                                now: now,
                                // 最后一行不画下边线（原型 `.commit-row:last-child`）。
                                showsSeparator: index < model.commitRows.count - 1
                            ) {
                                // ⚠️ `readOnly` **透传**（PRD §4.11 分区二、铁律 #7）：
                                //    从他人仓库的 PR 点进提交详情，那一页也不该长出写入口。
                                env.router.push(
                                    .commitDetail(fullName: fullName, sha: commit.sha, readOnly: readOnly)
                                )
                            }
                        }
                    }
                }
            }

        case let .failed(error):
            SectionFailure(error: error) { Task { await model.retryCommits() } }
        }
    }

    // MARK: - 分区三：文件

    @ViewBuilder
    private func files(_ detail: PullDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // ⚠️ 那个数**必须用 `detail.changedFiles`**，不能用这一页的条数 ——
            //    文件端点分页（`per_page=100`），大 PR 的第一页装不下全部。
            //    两者都是"文件数"，读错不会报错、只会显示一个偏小的数。
            Text(PullCopy.filesHint(count: detail.changedFiles))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                // 原型 `style="margin:0 2px 10px"`。
                .padding(.horizontal, Theme.Spacing.xxs)
                .padding(.bottom, 10)

            switch model.files {
            case .idle, .loading:
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ForEach(0..<2, id: \.self) { _ in diffSkeleton }
                }
                .accessibilityHidden(true)

            case .loaded:
                // ⚠️ 顺序即 `model.fileRows` 的顺序（= 服务端的 `files[]`），本页不重排。
                ForEach(model.fileRows) { file in
                    // ⚠️ `initiallyExpanded: false` —— **有意偏离原型**，见类型说明
                    //    （PRD 的分区提示与 §9.9 都指向折叠态按需解析）。
                    DiffCard(file: file, initiallyExpanded: false)
                }

            case let .failed(error):
                SectionFailure(error: error) { Task { await model.retryFiles() } }
            }
        }
    }

    // MARK: - 合并弹层（§5.3）

    @ViewBuilder
    private var mergeSheet: some View {
        // ⚠️ 走 `if let` 而不是给两个空串兜底：这张弹层只可能在
        //    `.mergeAndClose` 那一档被打开，而那一档要求详情已经在手。
        //    兜底成 `""` 会造出标题 `合并 · ` 与按钮 `确认合并进 `——看起来像排版问题。
        if let detail = model.detail.value {
            MergePRSheet(
                branchFlow: detail.branchFlow,
                base: detail.baseRef
            ) { method in
                // ⚠️ 先关弹层再发请求（原型 `doMerge()` 就是这个顺序），
                //    理由是提示条挂在 Tab 那一层 —— 弹层盖着时弹出的提示用户看不见。
                //    请求在途的状态由操作区那个按钮表达（`isWorking`）。
                isMerging = false
                Task { await model.merge(method: method) }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 骨架

    /// 整页骨架 —— 含分段条（见类型说明）。
    ///
    /// ## ⚠️ 2026-10-16 起不再手抄几何（NATIVE-MIGRATION P1）
    ///
    /// 头部与分段条都画**真件**（`ConversationHeader` / `sectionTabs`）+ 占位详情
    /// + `.redacted` —— "三行与头部一一对应"、"三格等分 + 3pt 内边距"这些手抄的
    /// 约定都不用再守着。
    ///
    /// ⚠️ 对话那两口气泡仍走 `bubbleSkeleton`（`model.conversation` 还在 loading，
    /// 由 `conversationList` 自己画）。⚠️ `allowsHitTesting(false)`：
    /// `.redacted` **不拦截点击**，被遮住的分段条与操作区按钮都还点得动。
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            ConversationHeader(
                stateTitle: PullRequestState.open.pillTitle,
                stateTone: StateTone.tone(for: .open),
                note: Placeholders.shortLine,
                title: Placeholders.line,
                meta: Placeholders.shortLine
            )

            sectionTabs(.placeholder)
                .padding(.top, Theme.Spacing.m)

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(0..<2, id: \.self) { _ in bubbleSkeleton }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 一条评论 / 正文气泡的骨架（与 `IssueDetailView` 同形状）。
    ///
    /// ⚠️ 画的是**真实的 `CommentRow`** + 占位评论（NATIVE-MIGRATION P1）：
    /// 圆角、内边距、头像那一列的位置都自动与真气泡一致。
    private var bubbleSkeleton: some View {
        CommentRow(
            login: "placeholder",
            authorName: AuthorName.display("placeholder"),
            timeText: RelativeTime.string(from: Placeholders.date, now: now),
            blocks: MarkdownDocument(Placeholders.line).blocks
        )
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }

    /// 一张 diff 卡片的骨架（折叠态的样子：只有头部那一行）。
    ///
    /// ⚠️ 画的是**真实的 `DiffCard`** + 占位改动 + `.redacted`（NATIVE-MIGRATION P1），
    /// 与下面 `fileRows` 那一支同款（`initiallyExpanded: false`）——
    /// 折叠态那行"文件名 + `+a −d`"的几何从此不用手守。
    private var diffSkeleton: some View {
        DiffCard(file: .placeholder, initiallyExpanded: false)
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
    }
}

#Preview {
    @Previewable @State var environment = AppEnvironment()
    NavigationStack {
        PullDetailView(
            fullName: "my-git/gitduo",
            number: 57,
            readOnly: false,
            loader: environment.pullDetail,
            actions: environment.pullAction,
            sender: environment.postIssueComment,
            drafts: environment.commentDrafts,
            toast: environment.toast
        )
    }
    .environment(environment)
}
