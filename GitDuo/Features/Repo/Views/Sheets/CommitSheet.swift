import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 一次「提交更改」的尝试结局 —— 弹层据此决定这一屏接下来是什么。
///
/// ⚠️ 它是**视图与 ViewModel 之间的接口**（定义在弹层这一侧，因为它的三个 case
/// 说的都是"弹层接下来该干什么"）。真正的编排在 `EditorViewModel.submit(_:using:)`。
enum CommitAttempt: Sendable {

    /// 提交走完了 —— **含两档"做到一半"**（`FileSaveOutcome` 的四档都在这里）。
    /// 弹层按 `isComplete` 分流：完全成功 ⇒ 交给 `onSettled` + 关掉；
    /// 做到一半 ⇒ 换结果屏（§5.9④）。
    case settled(FileSaveOutcome)

    /// 版本基准过期（409）—— 两个出口换出来（§5.9③ / 决策 #69）。
    case conflict(RemoteLatest)

    /// 留在原地显示这一句（表单校验 / 网络 / 422 / 404 …）。
    case rejected(String)
}

/// 409 之后取回的"远端最新版"（§5.9③）。
struct RemoteLatest: Sendable, Equatable {

    /// 远端那一版现在的 blob SHA —— **两个出口都要拿它当新基准**。
    let sha: String

    /// 远端最新正文；**拿不到时为 `nil`**（它不是文本、或编码不认识）。
    /// 那一档只是"没有东西可看"，仍然可以强制覆盖。
    let text: String?
}

/// 提交更改弹层（PRD §5.9、原型 `scripts/15-sheets.js` 的 `openCommitSheet` / `doCommit`）。
///
/// ## 它比原型多四块（用户 2026-10-08 拍板，见 `AGENTS.md §0` 切片 8 施工图）
///
/// | 补的是什么 | 依据 |
/// |---|---|
/// | 上传来源顶部那行只读的 `将写入 {路径}` | §5.9① / 决策 #70② |
/// | 图片被压过 / 转过时、那行下面的一句（**三种说法**） | §5.8 / 决策 #71⑤ · #72⑤ |
/// | 「新分支 + PR」的两行输入（分支名 / PR 标题） | §5.9② / 决策 #67 |
/// | 409 的两个出口（查看最新版 / 强制覆盖） | §5.9③ / 决策 #69 |
/// | 两档"做到一半"的结果屏 | §5.9④ / 决策 #68① |
///
/// ## ⚠️ 弹层自己**只做呈现 + 分支**，两件事交给调用方
///
/// `onSubmit`（跑 `SaveFile`）与 `onSettled`（发提示 / 决定要不要返回上一页）都由
/// 调用方给 —— 弹层不认识 `ToastCenter`，也不认识"提交完该不该 pop"
/// （同 `LabelPickerSheet` 的既有处置：三条正常路径的提示在宿主）。
///
/// ## ⚠️ 「查看最新版」有一处**规格与实现的落差**（已登记）
///
/// PRD §5.9③ 写的是"取回最新的内容与版本，把**你的改动与新版一起给出来**，你合完再提"。
/// 而这一版的编辑区只有一个文本域，给不出双栏合并。本期落在：
/// **把远端最新版只读地显示出来**，用户看完点「返回」、可以继续改自己那份，
/// 再点「提交」时用的基准是**他刚看过的那一版**（`overrideSHA`）。
///
/// ⇒ 于是它与「强制覆盖」的差别是"用户有没有看一眼 + 有没有二次确认"，**而不是结果**。
/// 这一点如实登记，等有双栏编辑器时再补。
struct CommitSheet: View {

    /// 弹层标题那一段（`CommitSource.title`）。
    let source: CommitSource

    /// 仓库全名（只给"PR 未创建"那一屏的网页端出口拼地址用）。
    let fullName: String

    /// 进弹层时的当前分支 —— 分段的第一个选项、以及 `POST /pulls` 的 `base`。
    let branch: String

    /// 上传来源的落点；`nil` = 不显示那一行（编辑器与"新建文件"都没有这一行）。
    let destinationPath: RepoPath?

    /// 上传的图片**被压过 / 被转过**时的摘要（原字节 → 现在字节、以及换了什么格式）；
    /// `nil` = 一个字节都没动（不显示那一句）。
    ///
    /// ⚠️ 它只对上传那两个出口有意义 ⇒ 与 `destinationPath` 同时为 `nil` 或同时有值。
    /// 编辑器的两条路（新建 / 编辑）传的恒是 `nil`。
    let adjustment: UploadAdjustment?

    /// 「新分支 + PR」的**预填分支名**。
    ///
    /// ⚠️ 由调用方给而不是在这里 `Date()`：`FileWriteTarget.defaultNewBranchName(now:)`
    /// 的 `now` 是必传的，理由正是"预填名是什么"要能被测试钉住。
    let defaultBranchName: String

    /// 执行提交。
    ///
    /// - Parameter overrideSHA: 本次要用的版本基准；`nil` = 用进页面读到的那个。
    ///   两个出口（强制覆盖 / 查看最新版之后重提）传的都是 409 时取回的那个 sha。
    let onSubmit: (CommitDraft, String?) async -> CommitAttempt

    /// **完全成功**之后的收尾 —— 发提示、必要时返回上一页。
    ///
    /// ⚠️ 两档"做到一半"**不**走这里：那时弹层要留在原地把话说完（§5.9④）。
    let onSettled: (FileSaveOutcome, CommitDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var message = ""
    @State private var isNewBranch = false
    @State private var newBranchName = ""
    @State private var prTitle = ""
    @State private var failure: String?
    @State private var isWorking = false
    @State private var isConfirmingOverwrite = false

    /// 409 之后由两个出口设置的新基准（`nil` = 用进页面读到的那个）。
    @State private var overrideSHA: String?

    @State private var phase: Phase = .editing

    /// 这一屏现在是什么。
    private enum Phase: Equatable {
        /// 输入 + 分段 + 提交（默认）。
        case editing
        /// 409 —— 两个出口（§5.9③）。
        case conflict(RemoteLatest)
        /// 「查看最新版」那一屏（只读显示远端最新正文）。
        case latest(RemoteLatest)
        /// 两档"做到一半"（§5.9④）。
        case partial(FileSaveOutcome)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(CommitSheetCopy.sheetTitle(source: source.title))

            switch phase {
            case .editing:
                editingBody
            case let .conflict(latest):
                conflictBody(latest)
            case let .latest(latest):
                latestBody(latest)
            case let .partial(outcome):
                partialBody(outcome)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.surface)
        // 「新分支 + PR」的预填分支名（§5.9②）。放在 `onAppear` 而不是属性初值：
        // `defaultBranchName` 是外部传进来的，而 `@State` 的初值拿不到它。
        .onAppear { if newBranchName.isEmpty { newBranchName = defaultBranchName } }
    }

    // MARK: - ① 输入那一屏（原型 `openCommitSheet` 的骨架）

    private var editingBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 上传来源多一行只读的落点（§5.9①）——"东西存到哪"是这一步里
            // 用户唯一可能搞错的事，而它是 App 决定的（决策 #70②）。
            if let destinationPath {
                destinationRow(destinationPath, adjustment: adjustment)
            }

            SheetField(
                CommitSheetCopy.messagePlaceholder,
                text: $message,
                // ⚠️ 提交信息是一句话 ⇒ 按句首大写、纠错开着。
                //    `SheetField` 的默认档是给分支名 / 标签名定的（不纠错、不大写）。
                disablesAutocorrection: false,
                capitalization: .sentences,
                // 原型 `<textarea class="sheet-input" id="cmsg" rows="2">` ⇒ 保底两行。
                minLines: 2
            )
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.s)

            targetPicker
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.top, Theme.Spacing.m)

            if isNewBranch {
                // 原型 `#newBranchRow`：`background:var(--add-bg);color:var(--add-tx)`。
                NoticeBar(text: CommitSheetCopy.newBranchHint(branch: branch), tone: .add)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.top, Theme.Spacing.s)

                branchInputs
            }

            if let failure {
                failureText(failure)
            }

            ActionButton(
                title: CommitSheetCopy.confirmAction,
                style: .primary,
                verticalPadding: 12,
                isWorking: isWorking
            ) {
                Task { await submit() }
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.m)

            ActionButton(title: FileCopy.cancelAction, style: .ghost, verticalPadding: 12) {
                dismiss()
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.s)

            SheetHint(CommitSheetCopy.footer)
        }
    }

    /// 上传来源那行**只读**的落点（+ 动过时的一句 caption）。
    ///
    /// ⚠️ 形态照 `MergeSheet.targetSection` 的先例（图标 + 值 + 下方一句 caption），
    /// **不是**输入框 —— 改路径请改用「新建文件」（§5.8 明写）。
    /// 这一行刻意不做成第三件设计包组件：两处逐字相同的东西只有"图标 + 一行字"，
    /// 收拢它要么给设计包加一件只服务两个调用点的组件，要么动已验收的切片 7。
    ///
    /// ⚠️ 那句 caption 是**同一条理由的第二个落点**（决策 #71⑤ · #72⑤）：
    /// 落点行说的是"存到哪"、它说的是"存的是什么"—— 两者都是 App 替用户决定、
    /// 而用户在此刻**必须知道**的事（他选的那张图已经被重编码过、格式可能也换了）。
    /// ⚠️ **三种说法由 `CommitSheetCopy.adjustmentNotice` 挑**（压小了 / 压小并转了 / 只转了），
    /// 这里不做判断 —— 那两个数都是实测的，页面上不该有第二处解释。
    /// ⚠️ 没动过时**整句不出现**（不是印一句"未压缩"）：没发生的事不需要占一行。
    private func destinationRow(_ path: RepoPath, adjustment: UploadAdjustment?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: GitHubIcon.file)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text(CommitSheetCopy.destinationNotice(path: path))
                    .font(Theme.Font.rowTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Spacing.m)
            .padding(.horizontal, Theme.Spacing.s)

            if let adjustment {
                Text(CommitSheetCopy.adjustmentNotice(adjustment))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.s)
            }
        }
    }

    /// 目标两档（§5.9 的「提交到 {当前分支}」/「新分支 + PR」，默认第一项）。
    ///
    /// ⚠️ 用 `SegmentedBar` 而不是自绘：原型这里就是 `.segbar` / `.seg`
    /// （`15-sheets.js:44-47`），与仓库 Tab / 探索页是同一套 CSS ⇒ 同一个组件。
    /// `padsHorizontally: false` 且由调用方补 8pt —— 与同屏的 `SheetField` 对齐
    /// （弹层容器自己已经给了 10）。
    private var targetPicker: some View {
        SegmentedBar(
            segments: [
                .init(id: Self.currentTarget, title: CommitSheetCopy.targetCurrent(branch: branch)),
                .init(id: Self.newBranchTarget, title: CommitSheetCopy.targetNewBranch),
            ],
            selectedID: isNewBranch ? Self.newBranchTarget : Self.currentTarget,
            padsHorizontally: false
        ) { picked in
            isNewBranch = picked.id == Self.newBranchTarget
        }
    }

    private static let currentTarget = "current"
    private static let newBranchTarget = "new-branch"

    /// 「新分支 + PR」的两行输入（§5.9② / 决策 #67）。
    private var branchInputs: some View {
        VStack(alignment: .leading, spacing: 0) {
            subLabel(CommitSheetCopy.newBranchNameLabel)
            SheetField(CommitSheetCopy.newBranchNameLabel, text: $newBranchName)
                .padding(.horizontal, Theme.Spacing.s)
                // 预填值看起来像一段"不可改的说明文字"，而决策 #67 存在的全部理由
                // 恰恰是用户对这两个值有控制权 ⇒ 读屏里要说明白。
                .accessibilityHint(CommitSheetCopy.newBranchNameAccessibilityHint)

            subLabel(CommitSheetCopy.prTitleLabel)
            SheetField(CommitSheetCopy.prTitleLabel, text: prTitleBinding)
                .padding(.horizontal, Theme.Spacing.s)
        }
    }

    /// PR 标题的**预填**（§5.9② 表格：预填值 = 提交信息，为空则为默认信息）。
    ///
    /// ⚠️ 用"派生读、写入即固定"的 Binding 而不是把值拷进 `@State`：
    /// 后者要监听 `message` 的每一次变化（用户先改提交信息、再切到新分支那一档时
    /// 拷贝的时机就错了），而这一种形态在任何次序下都成立 ——
    /// 用户没动过它 ⇒ 跟着提交信息走；一动手就固定下来。
    private var prTitleBinding: Binding<String> {
        Binding(
            get: { prTitle.isEmpty ? previewMessage : prTitle },
            set: { prTitle = $0 }
        )
    }

    /// 按 §5.9 的回落规则算出来的提交信息（**复用领域规则，不在这里重写一遍**）。
    private var previewMessage: String {
        CommitDraft(message: message, source: source).effectiveMessage
    }

    // MARK: - ② 409 的两个出口（§5.9③）

    private func conflictBody(_ latest: RemoteLatest) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 那句说明**不断言"是别人改的"** —— 他可能就是同一个人在另一台设备上改的
            //（§9.6.4 末）。文案在 `CommitSheetCopy.conflictHint`。
            NoticeBar(text: CommitSheetCopy.conflictHint)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.top, Theme.Spacing.s)

            // 出口一：看过了再决定（**不自动重提**，§5.9③ 明写）。
            ActionButton(title: CommitSheetCopy.viewLatestAction, style: .primary, verticalPadding: 12) {
                phase = .latest(latest)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.m)

            // 出口二：以我这份为准（危险 + 二次确认，§9.6.4 要求）。
            ActionButton(
                title: CommitSheetCopy.forceOverwriteAction,
                style: .destructive,
                verticalPadding: 12
            ) {
                isConfirmingOverwrite = true
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.s)

            ActionButton(title: FileCopy.cancelAction, style: .ghost, verticalPadding: 12) {
                dismiss()
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.s)

            Spacer(minLength: 0)
        }
        // ⚠️ 二次确认用系统的 `confirmationDialog` 而不是再加一层自绘弹层：
        //    它是"危险动作"这一类交互的标准形态，读屏 / 动态字体 / 取消手势都由系统管。
        .confirmationDialog(
            CommitSheetCopy.forceOverwriteConfirmTitle,
            isPresented: $isConfirmingOverwrite,
            titleVisibility: .visible
        ) {
            Button(CommitSheetCopy.forceOverwriteAction, role: .destructive) {
                Task { await resubmit(using: latest.sha) }
            }
            Button(FileCopy.cancelAction, role: .cancel) {}
        } message: {
            Text(CommitSheetCopy.forceOverwriteConfirmHint)
        }
    }

    // MARK: - ③ 「查看最新版」那一屏

    private func latestBody(_ latest: RemoteLatest) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHint(CommitSheetCopy.viewLatestHint)

            if let text = latest.text {
                ScrollView {
                    CodeSurface(text: text)
                }
                // 与文件查看页的正文同一个量级：弹层里给一段能滚的区域，
                // 而不是让它把整张弹层撑到屏幕外。
                .frame(maxHeight: 260)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.top, Theme.Spacing.s)
            } else {
                // 远端那一版不是能显示的文本（图片 / 编码不认识）——
                // 仍然可以强制覆盖，只是"看"这件事做不到。
                NoticeBar(text: CommitSheetCopy.conflictHint)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.top, Theme.Spacing.s)
            }

            ActionButton(title: CommitSheetCopy.backToSheetAction, style: .ghost, verticalPadding: 12) {
                // ⚠️ 返回之后基准换成**刚看过的那一版**（`overrideSHA`）——
                //    用户此刻的处境是"我知道远端长什么样了，仍然要用我这份内容"。
                //    这一步正是本屏与「强制覆盖」唯一的形式差别（见类型说明的落差那条）。
                overrideSHA = latest.sha
                failure = nil
                phase = .editing
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.m)

            Spacer(minLength: 0)
        }
    }

    // MARK: - ④ 两档"做到一半"（§5.9④）

    private func partialBody(_ outcome: FileSaveOutcome) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // ⚠️ 这句话**必须说出来**：那一刻仓库里确实已经有了东西
            //（一条分支 / 一次提交），而用户再点一次会撞上"分支已存在"。
            NoticeBar(text: CommitSheetCopy.toast(
                for: outcome,
                currentBranch: branch,
                message: previewMessage
            ))
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.s)

            // 「PR 未创建」那一档配一个去网页端建 PR 的出口（§5.9④ 明写要"给网页端出口"）。
            if case let .committedButPullCreationFailed(head, _, _) = outcome {
                ActionButton(
                    title: CommitSheetCopy.openCompareInBrowserAction,
                    style: .primary,
                    verticalPadding: 12
                ) {
                    if let url = RepoWebLinks.compare(fullName: fullName, base: branch, head: head) {
                        openURL(url)
                    }
                }
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.top, Theme.Spacing.m)
            }

            ActionButton(
                title: CommitSheetCopy.partialDoneAction,
                style: .ghost,
                verticalPadding: 12
            ) {
                dismiss()
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.s)

            Spacer(minLength: 0)
        }
    }

    // MARK: - 提交

    /// 当前输入构成的草稿。
    private var draft: CommitDraft {
        CommitDraft(
            message: message,
            target: isNewBranch
                // ⚠️ PR 标题传**框里显示的那个**（已含 §5.9② 的回落），
                //    于是它与用户看到的完全一致（`effectivePRTitle` 还会再兜一次底）。
                ? .newBranch(name: newBranchName, prTitle: prTitleBinding.wrappedValue)
                : .currentBranch,
            source: source
        )
    }

    private func submit() async {
        await run(using: overrideSHA)
    }

    /// 409 之后的重提（两个出口都走这里）。
    private func resubmit(using sha: String) async {
        overrideSHA = sha
        phase = .editing
        await run(using: sha)
    }

    private func run(using sha: String?) async {
        isWorking = true
        failure = nil
        let attempt = await onSubmit(draft, sha)
        isWorking = false

        switch attempt {
        case let .settled(outcome):
            if outcome.isComplete {
                onSettled(outcome, draft)
                dismiss()
            } else {
                // §5.9④：**留在弹层把话说清**（那一屏上有"再去网页端建 PR"的出口）。
                phase = .partial(outcome)
            }

        case let .conflict(latest):
            phase = .conflict(latest)

        case let .rejected(message):
            failure = message
        }
    }

    // MARK: - 零件

    /// 输入框上方的小节标题。
    ///
    /// ⚠️ 样式「**规格未给**」（§5.9② 只给了"分支名 / PR 标题"两个名字），
    /// 取与 `MergeSheet.subLabel` **逐字相同**的一档（小号灰字 + 与 `SheetHint` 同档缩进）。
    /// 两处各有一份是**已登记的欠账**：收拢它要么给设计包加一件只服务两个调用点的组件，
    /// 要么动已验收的切片 7 —— 与 `PageFailure` 当初那条同一种取舍。
    private func subLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.m)
    }

    /// 留在原地的那句话（表单校验 / 网络 / 422 / 404）。
    private func failureText(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.destructive)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.s)
    }
}

#Preview {
    CommitSheet(
        source: .edit(fileName: "AppTabs.swift"),
        fullName: "my-git/gitduo",
        branch: "main",
        destinationPath: nil,
        adjustment: nil,
        defaultBranchName: "gitduo/20261008-120000"
    ) { _, _ in
        .rejected("预览用：提交不接后端")
    } onSettled: { _, _ in }
    .background(Theme.Palette.background)
}
