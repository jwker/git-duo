import Foundation
import Testing

@testable import GitDuoKit

/// 分支名校验（TECH_SPEC §9.7.1、PRD §4.8）。
///
/// ## 为什么这一套断言必须存在
///
/// 这八条规则是**照 git 的 `check_refname_format` 抄的**。抄漏一条不会报错：
/// 客户端放行 → 发请求 → 服务端 422 → 用户看到"服务器验证失败"，
/// 第一反应是"GitHub 坏了"。而那个 422 的文案**解释不了是哪条规则**，
/// 所以"漏抄"与"服务端拒绝"在用户眼里是同一件事。
@Suite("分支名校验 · 八条规则与提示文案")
struct BranchNameTests {

    // MARK: - 合法

    @Test("常见分支名一律放行（别把正常的名字拦掉）")
    func acceptsCommonNames() {
        let valid = [
            "main", "master", "develop", "feature/repo-hub", "fix/issue-42",
            "release/2.0", "gh-pages", "HEAD-fix", "head", "a", "v1.2.3",
            "user/name/topic", "中文分支", "dependabot/npm_and_yarn/lodash-4.17.21",
        ]

        for name in valid {
            #expect(BranchName.validate(name) == nil, "「\(name)」应当是合法分支名")
        }
    }

    // MARK: - 八条规则

    @Test("① 不能为空")
    func rejectsEmpty() {
        #expect(BranchName.validate("") == .empty)
        #expect(BranchNameCopy.message(for: .empty) == "请输入分支名")
    }

    @Test("② 不能含空格（首尾空格也算 —— 校验**不做 trim**）")
    func rejectsWhitespace() {
        #expect(BranchName.validate("my branch") == .containsForbiddenCharacter(" "))
        // ⚠️ 这一条是"为什么不先 trim"的实锤：`feature ` 与 `feature` 是两个不同的 ref，
        //    静默 trim 会让用户以为建的是后者。
        #expect(BranchName.validate("feature ") == .containsForbiddenCharacter(" "))
        #expect(BranchName.validate(" feature") == .containsForbiddenCharacter(" "))
    }

    @Test("③ 不能含 ~ ^ : ? * [ \\ 这七个字符")
    func rejectsForbiddenCharacters() {
        for character in BranchName.forbiddenCharacters.subtracting([" "]) {
            let name = "a\(character)b"
            #expect(
                BranchName.validate(name) == .containsForbiddenCharacter(character),
                "「\(character)」应当被拒"
            )
        }
    }

    @Test("④ 不能含控制字符（`< 0x20` 与 `0x7F`）")
    func rejectsControlCharacters() {
        #expect(BranchName.validate("a\u{01}b") == .containsControlCharacter)
        #expect(BranchName.validate("a\u{7F}b") == .containsControlCharacter)
        #expect(BranchName.validate("a\tb") == .containsControlCharacter)
    }

    @Test("⑤ 不能以 / 或 . 开头 / 结尾")
    func rejectsLeadingAndTrailingSeparators() {
        #expect(BranchName.validate("/feature") == .beginsOrEndsWithSlash)
        #expect(BranchName.validate("feature/") == .beginsOrEndsWithSlash)
        #expect(BranchName.validate(".feature") == .beginsOrEndsWithDot)
        #expect(BranchName.validate("feature.") == .beginsOrEndsWithDot)
        // 中间的点是合法的（`v1.2.3` 已经在上面的"合法"表里）。
        #expect(BranchName.validate("v1.2.3") == nil)
    }

    @Test("⑥ 不能含 // 或 ..")
    func rejectsConsecutiveSeparators() {
        #expect(BranchName.validate("feature//x") == .containsDoubleSlash)
        #expect(BranchName.validate("feature..x") == .containsDoubleDot)
        // ⚠️ `..` 同时违反"以点开头 / 结尾"与"含 `..`"两条 —— 按判定顺序报**排在前面的**那条。
        //    这正是上面「报根因」那条测试要守的次序：不写清顺序，两处报哪条就说不准。
        #expect(BranchName.validate("..") == .beginsOrEndsWithDot)
        #expect(BranchName.validate("./x") == .beginsOrEndsWithDot)
    }

    @Test("⑦ 不能以 .lock 结尾")
    func rejectsLockSuffix() {
        #expect(BranchName.validate("feature.lock") == .endsWithLock)
        // ⚠️ 只有**结尾**才是问题 —— 中间叫 `lock` 是正常的。
        #expect(BranchName.validate("lock/feature") == nil)
        #expect(BranchName.validate("feature.lockfile") == nil)
    }

    @Test("⑧ 保留名 HEAD 被拒，但小写 `head` 是合法分支名")
    func rejectsReservedName() {
        #expect(BranchName.validate("HEAD") == .reservedName)
        #expect(BranchName.validate("head") == nil)
        #expect(BranchName.validate("HEADS") == nil)
    }

    // MARK: - 顺序与文案

    @Test("⚠️ 多条规则同时不满足时，报的是**更根本**的那条（顺序不是随意的）")
    func reportsTheRootCause() {
        // `a b..c` 同时含空格与 `..`，用户一次改一个 ⇒ 报 `..` 更省事。
        #expect(BranchName.validate("a b..c") == .containsDoubleDot)
        // `.a b` 同时以点开头且含空格 ⇒ 报"以点开头"。
        #expect(BranchName.validate(".a b") == .beginsOrEndsWithDot)
        // 控制字符排在禁字符之前（它可能看不见，排在后面会给出解释不了的提示）。
        #expect(BranchName.validate("\u{01} x") == .containsControlCharacter)
    }

    @Test("每条原因都有一句中文提示，且**说清怎么改**")
    func everyIssueHasAVisibleMessage() {
        let issues: [BranchName.Issue] = [
            .empty,
            .containsControlCharacter,
            .containsForbiddenCharacter("~"),
            .containsForbiddenCharacter(" "),
            .beginsOrEndsWithSlash,
            .beginsOrEndsWithDot,
            .containsDoubleSlash,
            .containsDoubleDot,
            .endsWithLock,
            .reservedName,
        ]

        for issue in issues {
            let message = BranchNameCopy.message(for: issue)
            #expect(!message.isEmpty)
            // 只写"不合法"的句子对用户没用 —— 他手上是一个输入框。
            #expect(message.contains("分支名") || message.contains("请输入"), "「\(message)」应当指名对象")
        }

        // 空格单说一句：否则会拼出"不能包含  与空格…"（那个字符看不见）。
        #expect(BranchNameCopy.message(for: .containsForbiddenCharacter(" ")) == "分支名不能包含空格")
        #expect(BranchNameCopy.message(for: .containsForbiddenCharacter("~")).contains("~"))
        // 反斜杠在提示里要能显示出来（誊写时最容易漏的就是它）。
        #expect(BranchNameCopy.message(for: .containsForbiddenCharacter("\\")).contains("\\"))
    }
}
