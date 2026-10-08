import Foundation
import Testing

@testable import GitDuoKit

/// 一个确定的 UTC 时刻（避免把"预填的分支名"写成随机器时间变化的断言）。
private func utcDate(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int, _ minute: Int, _ second: Int
) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: components)!
}

private let utc = TimeZone(identifier: "UTC")!

/// 写通道的**目标、草稿、来源**三件纯类型（§5.9、决策 #67）。
///
/// ## 为什么这几条值得单独测
///
/// 它们都是"两个值在某一档里根本不存在"的规则，而这正是最容易在重构里
/// 被"统一成一个字符串 + 一个布尔"抹掉的东西 —— 抹掉之后代码照样编译、
/// 界面照样能用，只是**在没有 PR 的时候也会带着一个空分支名去发请求**。
@Suite("写通道 · 目标 / 草稿 / 来源（切片 8.1）")
struct FileWriteTargetTests {

    // MARK: - 两档的判据

    @Test("`currentBranch` 那一档**没有**分支名与 PR 标题 —— 它们不该存在于不需要的档里")
    func currentBranchCarriesNoBranchFields() {
        let target = FileWriteTarget.currentBranch
        #expect(target.isNewBranch == false)
        #expect(target.newBranchName == nil)
        #expect(target.newBranchPRTitle == nil)
    }

    @Test("`newBranch` 那一档三个值都在")
    func newBranchCarriesAllFields() {
        let target = FileWriteTarget.newBranch(name: "gitduo/x", prTitle: "改点东西")
        #expect(target.isNewBranch)
        #expect(target.newBranchName == "gitduo/x")
        #expect(target.newBranchPRTitle == "改点东西")
    }

    // MARK: - 预填的分支名（决策 #67）

    @Test("预填名是 `gitduo/{yyyyMMdd-HHmmss}`，且**只按给定时刻算**")
    func defaultBranchNameFormat() {
        let name = FileWriteTarget.defaultNewBranchName(
            now: utcDate(2026, 10, 8, 12, 34, 56), timeZone: utc
        )
        #expect(name == "gitduo/20261008-123456")
    }

    @Test("⚠️ 时区参与换算 —— 同一时刻在两个时区下是不同的名字（不是「随便取一个」）")
    func defaultBranchNameRespectsTimeZone() {
        let instant = utcDate(2026, 10, 8, 23, 30, 0)
        let inUTC = FileWriteTarget.defaultNewBranchName(now: instant, timeZone: utc)
        let inBeijing = FileWriteTarget.defaultNewBranchName(
            now: instant, timeZone: TimeZone(identifier: "Asia/Shanghai")!
        )
        // 北京 比 UTC 早 8 小时 ⇒ 23:30Z 是次日 07:30。
        #expect(inUTC == "gitduo/20261008-233000")
        #expect(inBeijing == "gitduo/20261009-073000")
    }

    @Test("⚠️ 预填名必须**自己就是一条合法的分支名** —— 否则用户直接提交会吃 422")
    func defaultBranchNameIsItselfValid() {
        // 这条不变量比格式本身重要：预一个非法名字，等于把"客户端先拦"那条规则
        // 变成"默认值就过不了"。它同时钉住"前缀里那个 `/` 是合法的"
        // （`BranchName` 只禁以 `/` 开头或结尾、以及 `//`）。
        let name = FileWriteTarget.defaultNewBranchName(
            now: utcDate(2026, 1, 2, 3, 4, 5), timeZone: utc
        )
        #expect(BranchName.validate(name) == nil)
        #expect(name.hasPrefix("gitduo/"))
    }

    @Test("秒不同 ⇒ 名字不同（同一秒内重复提交会重名，那是 422 该拦的事）")
    func defaultBranchNameUsesSeconds() {
        let a = FileWriteTarget.defaultNewBranchName(now: utcDate(2026, 10, 8, 0, 0, 1), timeZone: utc)
        let b = FileWriteTarget.defaultNewBranchName(now: utcDate(2026, 10, 8, 0, 0, 2), timeZone: utc)
        #expect(a != b)
    }

    // MARK: - 草稿的两条回落（§5.9）

    @Test("提交信息为空 / 全空白 ⇒ 默认信息（原型 `doCommit` 逐字的那一句）")
    func effectiveMessageFallsBack() {
        let base = CommitSource.newFile
        #expect(CommitDraft(message: "", source: base).effectiveMessage == "update via GitDuo")
        #expect(CommitDraft(message: "   \n ", source: base).effectiveMessage == "update via GitDuo")
    }

    @Test("⚠️ 非空提交信息**只 trim 发出去的那一份**，草稿上原样保留")
    func effectiveMessageTrimsOnlyOnSend() {
        var draft = CommitDraft(message: "  fix: 收口  ", source: .newFile)
        #expect(draft.message == "  fix: 收口  ", "打字过程中不该被吃掉尾随空格")
        #expect(draft.effectiveMessage == "fix: 收口")
        draft.message = "fix: 收口  "
        #expect(draft.message == "fix: 收口  ")
    }

    @Test("⚠️ PR 标题为空 ⇒ 回落到**提交信息**（而不是另一句默认标题）")
    func effectivePRTitleFallsBackToMessage() {
        let target = FileWriteTarget.newBranch(name: "gitduo/x", prTitle: "")
        #expect(
            CommitDraft(message: "改点东西", target: target, source: .newFile).effectivePRTitle
                == "改点东西"
        )
    }

    @Test("⚠️ PR 标题与提交信息**都空** ⇒ 回落到默认信息（官方要求 `title` 必填，不能发空串）")
    func effectivePRTitleFallsBackToDefaultMessage() {
        let target = FileWriteTarget.newBranch(name: "gitduo/x", prTitle: "   ")
        let draft = CommitDraft(message: "", target: target, source: .newFile)
        #expect(draft.effectivePRTitle == "update via GitDuo")
        #expect(draft.effectivePRTitle == draft.effectiveMessage)
    }

    @Test("PR 标题自己写了就用它（两行输入都能改 —— 决策 #67 的要点）")
    func effectivePRTitleUsesTypedValue() {
        let target = FileWriteTarget.newBranch(name: "gitduo/x", prTitle: "  feat: 加个入口 ")
        let draft = CommitDraft(message: "改点东西", target: target, source: .newFile)
        #expect(draft.effectivePRTitle == "feat: 加个入口")
        #expect(draft.effectiveMessage == "改点东西", "两者互不干扰")
    }

    @Test("分支名**原样**带出去（trim 与校验都在 `SaveFile` 里，不在这里做第二遍）")
    func effectiveBranchNameIsRaw() {
        let target = FileWriteTarget.newBranch(name: "  spaced  ", prTitle: "x")
        #expect(CommitDraft(target: target, source: .newFile).effectiveBranchName == "  spaced  ")
    }

    // MARK: - 来源（§5.9 标题那一段）

    @Test("四个来源的取值与 PRD §5.9 逐字一致（含全角括号）")
    func sourceTitlesMatchPRD() {
        #expect(CommitSource.newFile.title == "新建文件")
        #expect(CommitSource.edit(fileName: "main.swift").title == "编辑 main.swift")
        #expect(CommitSource.uploadFile.title == "上传文件（文件 App）")
        #expect(CommitSource.uploadImage.title == "上传图片（相册）")
    }

    @Test("⚠️ 只有两个上传出口的**路径是自动定的** —— 弹层据此画只读的「将写入」行")
    func onlyUploadSourcesHaveAutomaticPath() {
        #expect(CommitSource.uploadFile.pathIsAutomatic)
        #expect(CommitSource.uploadImage.pathIsAutomatic)
        #expect(CommitSource.newFile.pathIsAutomatic == false)
        #expect(CommitSource.edit(fileName: "a.swift").pathIsAutomatic == false)
    }

    @Test("弹层标题由来源拼出来（`提交更改 · {来源}`）")
    func sheetTitleComposes() {
        #expect(
            CommitSheetCopy.sheetTitle(source: CommitSource.edit(fileName: "a.md").title)
                == "提交更改 · 编辑 a.md"
        )
    }
}
