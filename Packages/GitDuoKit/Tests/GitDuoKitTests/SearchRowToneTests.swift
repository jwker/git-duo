import Foundation
import Testing

@testable import GitDuoKit

/// 会话结果行的**状态族**与胶囊文案（PRD §4.2、切片 5.4）。
///
/// ## 为什么这一套断言必须存在
///
/// 「已关闭的状态该画紫还是画红」**取决于它是 Issue 还是 PR**：
///
/// | 情形 | 原型 | 族 |
/// |---|---|---|
/// | 开放的 Issue / PR | `.pill.open` | `open`（绿） |
/// | 已合并的 PR | `.pill.merged` | `completed`（紫） |
/// | 已关闭的 Issue | `.pill.closed-i` | `completed`（紫） |
/// | 已关闭且未合并的 PR | `.pill.closed-p` | `closed`（红） |
///
/// 而 `PullRequestState` 把后两者**都收成了 `.closed`** —— 也就是说，判定必须连 `kind`
/// 一起看。这条规则若写在结果行里（App target，**没有测试 target**），
/// 它错了的表现是"已关闭的 Issue 长着一颗红胶囊"，看起来完全正常。
///
/// 所以判定留在 `ConversationHit.statusTone`（领域层），这里把它钉住。
@Suite("SearchRow · 会话行的状态族与胶囊文案")
struct SearchRowToneTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func hit(
        _ kind: ConversationKind,
        _ state: PullRequestState,
        number: Int = 1
    ) -> ConversationHit {
        ConversationHit(
            kind: kind,
            number: number,
            title: "t",
            repoFullName: "o/r",
            state: state,
            updatedAt: base
        )
    }

    // MARK: - 状态族

    @Test("⚠️ 状态族**必须连 `kind` 一起看**：已关闭的 Issue 是紫族，已关闭未合并的 PR 才是红族")
    func closedToneDependsOnKind() {
        let closedIssue = hit(.issue, .closed)
        let closedPull = hit(.pullRequest, .closed)

        #expect(closedIssue.statusTone == .completed)
        #expect(closedPull.statusTone == .closed)
        // 两者的 `state` **完全相同** —— 这正是"光看 state 分不出来"的实锤。
        #expect(closedIssue.state == closedPull.state)
    }

    @Test("开放 / 已合并两族与 `kind` 无关")
    func openAndMergedTones() {
        #expect(hit(.issue, .open).statusTone == .open)
        #expect(hit(.pullRequest, .open).statusTone == .open)
        #expect(hit(.pullRequest, .merged).statusTone == .completed)
    }

    @Test("三族取值齐备（设计包那边按同一套族给配色，缺一档就会掉进别的分支）")
    func allTonesAreReachable() {
        let tones: Set<ConversationStatusTone> = [
            hit(.issue, .open).statusTone,
            hit(.pullRequest, .closed).statusTone,
            hit(.pullRequest, .merged).statusTone,
        ]

        #expect(tones == Set(ConversationStatusTone.allCases))
    }

    // MARK: - 胶囊文案

    @Test("胶囊上的可见状态词是**英文**（原型 `pillOf` 逐字），与读屏词（中文）刻意分开")
    func pillTitleIsEnglishWhileLabelIsChinese() {
        let merged = hit(.pullRequest, .merged, number: 57)

        #expect(merged.statePillTitle == "Merged")
        #expect(merged.stateLabel == "已合并")
        #expect(merged.statePillTitle != merged.stateLabel)

        #expect(hit(.issue, .open).statePillTitle == "Open")
        #expect(hit(.issue, .closed).statePillTitle == "Closed")
    }
}
