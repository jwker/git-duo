import GitHubAPI
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 编辑器页（PRD §4.6、原型 `SCR.editor`、TECH_SPEC §9.6）。
///
/// ## 结构（原型 `06-files.js` 的 `SCR.editor`：五行、一个纵向流）
///
/// 说明行 →（新建模式）路径输入框 → 代码编辑区 →「提交更改…」→ 页脚。
/// 外层间距就是原型那个 `gap:10px`（10 不在 4pt 阶里 ⇒ 写原值，同本项目对
/// 「原型原值不在阶里」的既有做法）。
///
/// ## ⚠️ 编辑区是 `CodeTextArea("", minLines: 13)`
///
/// 原型那一屏的编辑区是 `class="code-editor"`，而 `CodeTextArea` 就是那份 CSS
/// —— 它的 `minLines` 注释里点名了"切片 8 的编辑器用 13"。
/// 占位文案给**空串**：新建模式的初值本来就是空的，而原型那里也没有 `placeholder`
/// （填一个"在这里写代码…"会是一句**凭空发明**的用户可见文案）。
///
/// ## ⚠️ 提交成功后**自动返回上一页**（§4.6）
///
/// 原型 `doCommit` 的最后一段 `if(top.id==='editor') pop()`。
/// 本页对应的动作在 `onSettled` 里 —— 而弹层**只在 `outcome.isComplete` 时**才调它，
/// 所以这里不需要再判一次（两档"做到一半"已经换成结果屏了，用户还有下一步）。
///
/// ⚠️ 用 `@State shouldPop` + `.onChange` 而不是在闭包里直接 `dismiss()`：
/// 那一刻弹层也正在关自己，两个 presentation 同时关会让
/// "页面已经走了、弹层还挂着一瞬"的中间态真的可见。
struct EditorView: View {

    /// 轻提示通道（提交的四种结局各有一句话 —— `CommitSheetCopy.toast(for:…)`）。
    let toast: ToastCenter

    @State private var model: EditorViewModel

    /// 提交弹层开没开。
    @State private var isCommitting = false

    /// 提交**整个**完成后要返回上一页（见类型说明）。
    @State private var shouldPop = false

    /// 退出这一页。
    ///
    /// ⚠️ 用 `@Environment(\.dismiss)` 而不是 `Router.pop()`：后者作用在**当前选中的 Tab**
    /// 上，在这一层用它等于假设"这一页在哪条栈里"；而 `dismiss()` 只做一件事 ——
    /// 弹掉我自己（同 `NewIssueView` 的选择）。
    @Environment(\.dismiss) private var dismiss

    init(
        fullName: String,
        mode: EditorMode,
        path: RepoPath?,
        loader: LoadFileContent,
        detail: LoadRepoDetail,
        memory: any BranchMemoryStore,
        saver: SaveFile,
        toast: ToastCenter
    ) {
        self.toast = toast
        _model = State(initialValue: EditorViewModel(
            fullName: fullName,
            mode: mode,
            path: path,
            loader: loader,
            detail: detail,
            memory: memory,
            saver: saver
        ))
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.Spacing.page)
                // 原型 `.screen.pushed .content{padding-top:16px}`；与 `NewIssueView` /
                // `IssueDetailView` 取同一档（本仓既有做法）。
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        .navigationTitle(
            EditorCopy.navigationTitle(mode: model.mode, fileName: model.navigationFileName)
        )
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.start() }
        .sheet(isPresented: $isCommitting) { commitSheet }
        .onChange(of: shouldPop) { _, newValue in
            if newValue { dismiss() }
        }
    }

    // MARK: - 主区域

    @ViewBuilder
    private var content: some View {
        switch model.load.presentation {
        case .skeleton:
            skeleton

        case .content:
            editorBody

        case let .failure(error):
            failureState(error)
        }
    }

    private var editorBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 原型 `.t3` + `· 分支 ${curBranch()}`（`EditorCopy.instructions` 逐字）。
            Text(EditorCopy.instructions(mode: model.mode, branch: model.branch ?? ""))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)

            // 路径框**只有新建模式有**（§4.6 那张表：编辑模式的路径就是进来的那个文件）。
            if model.mode == .create {
                pathField
            }

            CodeTextArea("", text: $model.text, minLines: 13)

            submitButton

            Text(EditorCopy.footer)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    /// 新建模式的路径输入框（预填 `EditorCopy.defaultNewFilePath`，**可改、含目录**）。
    ///
    /// ⚠️ 它与提交弹层里那一行只读的「将写入 `{path}`」**是两件事**：
    /// 这一行用户可以改；那一行是 App 已经定下来的落点（§5.8 的两个上传出口）。
    /// 所以这里用 `SheetField`（可编辑），那一处用一行只读。
    private var pathField: some View {
        SheetField("", text: $model.newFilePath)
    }

    private var submitButton: some View {
        ActionButton(title: EditorCopy.submitAction, style: .primary, verticalPadding: 12) {
            // ⚠️ 按钮**任何时候都可点**（原型与 §4.6 都没有"空内容则禁用"这一档）：
            //    "路径没填 / 该分支上已有同名文件"都要走到提交那一步才说得清，
            //    而一颗点不动的按钮不会告诉用户为什么。
            isCommitting = true
        }
    }

    // MARK: - 提交弹层（§5.9）

    private var commitSheet: some View {
        CommitSheet(
            source: commitSource,
            fullName: model.fullName,
            branch: model.branch ?? "",
            // ⚠️ 编辑器这条路**不显示**「将写入 `{path}`」那一行 ——
            //    它只在 §5.8 的两个上传出口上出现（那时路径是 App 定的、用户看不见）。
            destinationPath: nil,
            // 编辑器的两条路都不经过上传 ⇒ 没有"已压缩"那一句（决策 #71⑤）。
            compression: nil,
            // 预填分支名：调用方算（`now` 必传，理由见 `defaultNewBranchName`）。
            defaultBranchName: FileWriteTarget.defaultNewBranchName(now: Date()),
            // ⚠️ `sha` 一路透传：它是 409 之后两个出口用的**新基准**（`nil` = 用进页面读到的那个）。
            onSubmit: { draft, sha in await model.submit(draft, using: sha) },
            onSettled: { outcome, draft in
                toast.show(CommitSheetCopy.toast(
                    for: outcome,
                    currentBranch: model.branch ?? "",
                    message: draft.effectiveMessage
                ))
                // 走到这里就是"整个完成了"（弹层只在 `isComplete` 时调 `onSettled`）——
                // 两档"做到一半"留在弹层的结果屏上，用户还有下一步要处理（§5.9④）。
                shouldPop = true
            }
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// 弹层标题那一段的来源（§5.9 首行）。
    private var commitSource: CommitSource {
        switch model.mode {
        case .create: .newFile
        case .edit: .edit(fileName: model.navigationFileName)
        }
    }

    // MARK: - 骨架 / 失败

    /// 编辑模式在读既有内容（那一次读同时给编辑区初值与乐观锁基准）。
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBar(height: 13, width: 240)

            // 与 `CodeTextArea(minLines: 13)` 的形状对得上，否则内容到位那一刻整块会跳。
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(0..<13, id: \.self) { _ in
                    SkeletonBar(height: 13, width: 210)
                }
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .fill(Theme.Palette.surface)
            )

            SkeletonBar(height: 42)
        }
        .accessibilityHidden(true)
    }

    /// 首屏失败 —— 必须留一个出口（PRD §1 设计原则 4）。
    private func failureState(_ error: GitHubError) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(Theme.Palette.textTertiary)

            Text("加载失败")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)

            Button("重试") {
                Task { await model.retry() }
            }
            .font(Theme.Font.bodyStrong)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Self.failureHint(error))
    }

    private static func failureHint(_ error: GitHubError) -> String {
        switch error {
        case .transport: "网络不可用"
        case .rateLimited: "请求过于频繁"
        case .unauthorized: "登录状态已失效"
        default: "服务暂时不可用"
        }
    }
}

#Preview {
    @Previewable @State var environment = AppEnvironment()
    NavigationStack {
        EditorView(
            fullName: "my-git/gitduo",
            mode: .create,
            path: nil,
            loader: environment.fileContent,
            detail: environment.repoDetail,
            memory: environment.branchMemory,
            saver: environment.saveFile,
            toast: environment.toast
        )
    }
    .environment(environment)
}
