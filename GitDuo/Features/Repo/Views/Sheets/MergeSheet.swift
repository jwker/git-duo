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
        // P4：自绘弹层 → 原生 `Form`（`SheetPrimitives` 五件退休，见 `NATIVE-MIGRATION.md` §P4）。
        // 源分支选择行 → 原生 `Button` 行。
        Form {
            Section {
                if candidates.isEmpty {
                    Text(BranchCopy.mergeNoSourceHint)
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Palette.textTertiary)
                } else {
                    ScrollView {
                        ForEach(candidates, id: \.self) { name in
                            Button { source = name } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: GitHubIcon.branch)
                                        .font(.system(size: 18))
                                        .foregroundStyle(Theme.Palette.textSecondary)
                                    Text(name)
                                        .font(Theme.Font.rowTitle)
                                        .foregroundStyle(Theme.Palette.textPrimary)
                                    Spacer(minLength: 0)
                                    if name == source {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            // 原型 `color:var(--green)` ⇒ `success`（2026-10-17）。
                                            .foregroundStyle(Theme.Palette.success)
                                    }
                                }
                            }
                        }
                    }
                    .scrollDisabled(candidates.count <= 5)
                    .frame(maxHeight: 190)
                }
            } header: {
                Text(BranchCopy.mergeSourceLabel)
            }

            Section {
                HStack(spacing: 10) {
                    Image(systemName: GitHubIcon.branch)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Text(target)
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Spacer(minLength: 0)
                }
                Text(BranchCopy.mergeTargetHint)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            } header: {
                Text(BranchCopy.mergeTargetLabel)
            }

            Section {
                // 提交信息输入框（P4：原生 `TextField`，原 `SheetField`；默认关纠错、不大写）。
                TextField(BranchCopy.mergeMessagePlaceholder, text: $message)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            if let failure {
                Section {
                    Text(failure)
                        .foregroundStyle(Theme.Palette.destructive)
                        .multilineTextAlignment(.leading)
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(BranchCopy.mergeConfirmAction)
                    }
                }
                .buttonStyle(.borderedProminent)
                // 没有源分支可选 ⇒ 不可点。
                // ⚠️ 这里用 `.disabled` 是**对的**（`allowsHitTesting(false)` 留给
                //    决策 #51 那类"画出来但这一版就不做"的按钮）：这一档是**真的**
                //    "暂时不可用"，只是恰好在当前仓库里没有可选项。
                .disabled(candidates.isEmpty)
            }

            Section {
                Text(BranchCopy.mergeConflictHint)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .presentationDetents([.medium, .large])
        // 源分支的默认选中：进入弹层时先挑第一条（用户不改就是它）。
        .onAppear { if source == nil { source = candidates.first } }
    }

    // MARK: - 提交

    private func submit() async {
        guard let source, !source.isEmpty else { return }
        failure = await onMerge(source, message)
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
