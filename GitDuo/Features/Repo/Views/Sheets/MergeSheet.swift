import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 合并分支弹层（PRD §4.8 第 4 条、**决策 #52**）。
///
/// 结构：标题 → 源分支（**可选**）→ 目标分支（当前分支，只读）→ 提交信息（可选）
/// → 合并按钮 → 冲突引导。
///
/// ## ⚠️ 为什么它是一张**自己的**弹层，不复用「提交更改」弹层
///
/// PRD 与原型原先都写"打开提交更改弹层（标题 `合并 {源} → {当前}`）"。
/// 2026-10-07 拍板改掉（决策 #52），两条理由都是硬的：
/// 1. 那张弹层的内容是「提交信息 + **提交到当前分支 / 新分支 + PR**」，
///    而「新分支 + PR」这一项**对合并没有语义** —— 合并的结果只能落在目标分支上；
/// 2. 原型的源分支是**自动挑第一个非当前分支**，用户选不了 ——
///    而"哪条分支合进哪条"恰是这个操作**唯一的关键输入**。
///
/// ## 目标恒为当前分支
///
/// `POST /repos/{o}/{r}/merges` 的 `base` 是当前分支、`head` 是用户选的源分支
/// （§9.7.1）。所以目标那一栏是**只读**的：让它可选就要处理"合并到一条我没在看的
/// 分支"这种界面无从表达的状态（本页的"当前分支"是全局的那一条）。
///
/// ## 三种结局的文案都不在这里
///
/// `MergeBranch.run` 回 `MergeOutcome`（`.merged` / `.nothingToMerge`），
/// 文案在 `BranchCopy`。本件只负责**把失败的那句话显示在原地** ——
/// 合并失败（409 冲突）要留着弹层，用户可能想换个源分支再来一次。
struct MergeSheet: View {

    /// 可选的源分支（调用方已排除当前分支本身）。
    let candidates: [String]

    /// 目标分支（= 当前分支）。
    let target: String

    let isWorking: Bool

    /// 执行合并。**返回失败时给用户看的那句话**；成功为 `nil`（成功有 toast）。
    ///
    /// ⚠️ 成败都**不**由本件关弹层 —— 关与不关由调用方在成功路径上做
    /// （它也同时要刷新列表与写记忆）。
    let onMerge: (String, String) async -> String?

    @State private var source: String?
    @State private var message = ""
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(BranchCopy.mergeSheetTitle(target: target))

            sourceSection
            targetSection

            SheetField(BranchCopy.mergeMessagePlaceholder, text: $message)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.top, Theme.Spacing.m)

            if let failure {
                Text(failure)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.destructive)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.top, Theme.Spacing.s)
            }

            ActionButton(
                title: BranchCopy.mergeConfirmAction,
                style: .primary,
                // 原型 `.browser-body .btn{width:100%;padding:12px}` 那一族 ——
                // 弹层底部的确认按钮统一 12。
                isWorking: isWorking
            ) {
                Task { await submit() }
            }
            // 没有源分支可选 ⇒ 不可点。
            // ⚠️ 这里用 `.disabled` 是**对的**（`allowsHitTesting(false)` 留给
            //    决策 #51 那类"画出来但这一版就不做"的按钮）：这一档是**真的**
            //    "暂时不可用"，只是恰好在当前仓库里没有可选项。
            .disabled(candidates.isEmpty)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.m)

            SheetHint(BranchCopy.mergeConflictHint)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.surface)
        // 源分支的默认选中：进入弹层时先挑第一条（用户不改就是它）。
        .onAppear { if source == nil { source = candidates.first } }
    }

    // MARK: - 源分支

    @ViewBuilder
    private var sourceSection: some View {
        subLabel(BranchCopy.mergeSourceLabel)

        if candidates.isEmpty {
            Text(BranchCopy.mergeNoSourceHint)
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, Theme.Spacing.s)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(candidates, id: \.self) { name in
                        SheetRow(systemImage: GitHubIcon.branch, title: name) {
                            source = name
                        } trailing: {
                            if name == source {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Theme.Palette.accentStrong)
                            }
                        }
                    }
                }
            }
            .scrollDisabled(candidates.count <= 5)
            .frame(maxHeight: 190)
        }
    }

    // MARK: - 目标分支

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            subLabel(BranchCopy.mergeTargetLabel)

            HStack(spacing: 10) {
                Image(systemName: GitHubIcon.branch)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text(target)
                    .font(Theme.Font.rowTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Spacing.m)
            .padding(.horizontal, 10)

            Text(BranchCopy.mergeTargetHint)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.horizontal, 10)
        }
    }

    // MARK: - 提交

    private func submit() async {
        guard let source, !source.isEmpty else { return }
        failure = await onMerge(source, message)
    }

    /// 小节标题。
    ///
    /// ⚠️ **样式是「规格未给」**：原型没有合并弹层（决策 #52 才有的），
    /// 而 PRD 只给了两个名字。取"编号选色的小号灰字 + 与 `SheetHint` 同档缩进"——
    /// 不与 `SheetTitle`（大写、更重）争夺注意力，也不引入新字号。
    private func subLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.top, Theme.Spacing.m)
    }
}

#Preview {
    MergeSheet(
        candidates: ["feature/auth-refresh", "release/2.0", "hotfix/409"],
        target: "main",
        isWorking: false
    ) { _, _ in nil }
    .background(Theme.Palette.background)
}
