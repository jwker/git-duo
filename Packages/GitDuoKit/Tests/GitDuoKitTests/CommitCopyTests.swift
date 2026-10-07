import Foundation
import Testing

@testable import GitDuoKit

/// 提交详情 / Markdown 视图的**可见文案**（切片 6.3）。
///
/// ## 为什么这几句值得单独测
///
/// 它们都是"**必须分开说**"的句子 —— 而"分开"这件事恰恰是最容易被一次
/// 图省事的复用抹掉的：把 `oversizedDiffNotice` 拿去当二进制的说明，
/// 代码照样编译、卡片照样显示，只是那个 50 行的文本改动被说成了"二进制文件"。
/// 断言"两两不同"正是钉住这条规则的唯一办法（`grep` 查不出"复用"）。
///
/// 与 `CommitMessageTests` 里 `firstLineRuleIsShared` 那条不变量断言同一个思路：
/// **不预先假设某一种输入，只钉"几处之间必须成立的关系"**。
@Suite("提交与 Markdown 的可见文案 · 必须分开/必须随状态变")
struct CommitCopyTests {

    // MARK: - Diff 卡片的三句说明

    @Test("⚠️ `patch` 缺席的**两种**原因各有各的说法，`additions` 的那种**必须**有第三种")
    func diffNoticesArePairwiseDistinct() {
        // 三句说的是三件不同的事：
        // ① 二进制（去网页端也看不到 diff）；② 太大（去网页端能看到）；
        // ③ 压根没有 hunk（去网页端同样看不到 —— 因为本就没有改动内容）。
        let notices = [
            CommitCopy.binaryDiffNotice,
            CommitCopy.oversizedDiffNotice,
            CommitCopy.noHunksNotice,
        ]
        for (index, lhs) in notices.enumerated() {
            for rhs in notices[(index + 1)...] {
                #expect(lhs != rhs)
            }
        }
    }

    @Test("三句都非空 —— 空串会让卡片里出现一片空白，看起来像加载失败")
    func diffNoticesAreNotEmpty() {
        #expect(!CommitCopy.binaryDiffNotice.isEmpty)
        #expect(!CommitCopy.oversizedDiffNotice.isEmpty)
        #expect(!CommitCopy.noHunksNotice.isEmpty)
    }

    // MARK: - 折叠按钮的读屏提示

    @Test("折叠提示随状态变，且带着文件名（否则一屏 N 张卡片听起来一模一样）")
    func toggleLabelDependsOnState() {
        let expanded = CommitCopy.diffToggleAccessibilityLabel(file: "a/b.swift", isExpanded: true)
        let collapsed = CommitCopy.diffToggleAccessibilityLabel(file: "a/b.swift", isExpanded: false)

        #expect(expanded != collapsed)
        #expect(expanded.contains("收起"))
        #expect(collapsed.contains("展开"))
        // 两种状态都必须带上文件名 —— 只差"展开/收起"两个字的话，
        // 读屏用户在一屏多张卡片里分不出说话的是哪一张。
        #expect(expanded.contains("a/b.swift"))
        #expect(collapsed.contains("a/b.swift"))
    }

    // MARK: - 任务列表的勾选框

    @Test("勾选框的读屏标签随状态变 —— 不变就等于图标白画了")
    func checkboxLabelDependsOnState() {
        let checked = MarkdownCopy.checkboxLabel(checked: true)
        let unchecked = MarkdownCopy.checkboxLabel(checked: false)

        #expect(checked != unchecked)
        #expect(!checked.isEmpty)
        #expect(!unchecked.isEmpty)
    }
}
