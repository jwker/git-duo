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

    /// 禁字符的 `Character` 形态（去掉空格）。
    ///
    /// 实现里的正本是 `BranchName.forbiddenScalars`（`Unicode.Scalar` 的有序数组 —— 判据必须按标量），
    /// 而这里的断言要**拼名字**、要跟 `Issue` 里带的那个 `Character` 比，所以现还原一次。
    private static var forbiddenChars: [Character] {
        BranchName.forbiddenScalars.map { Character($0) }.filter { $0 != " " }
    }

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
        for character in Self.forbiddenChars {
            let name = "a\(character)b"
            #expect(
                BranchName.validate(name) == .containsForbiddenCharacter(character),
                "「\(character)」应当被拒"
            )
        }
    }

    @Test("③b ⚠️ 禁用字符**后面粘一个组合记号**照样要拦（判据必须按 Unicode 标量，不能按字素簇）")
    func rejectsForbiddenCharacterFollowedByCombiningMark() {
        // `"~\u{0301}"` 在 Swift 里是**一个**字素簇（`count == 1`），但 URL 编码出来是 `~%CC%81`
        // —— ASCII `~` **原封不动**进了请求 ⇒ `git check-ref-format` 拒、服务端 422。
        // 这正是本函数文档里写明它存在的那条理由（"某个名字在客户端放行、到服务端吃 422"）：
        // 按 `Character`（字素簇）比会整族漏掉，按 `Unicode.Scalar` 比才拦得住。
        // ⚠️ 用户看不出差别 —— `~\u{0301}` 与 `~` 在屏幕上几乎一样（组合记号无声地依附在前一个字符上）。
        for character in Self.forbiddenChars + [" "] {
            #expect(
                BranchName.validate("a\(character)\u{0301}b") == .containsForbiddenCharacter(character),
                "「\(character)」后面粘一个组合记号后应当仍被拒（否则会到服务端吃 422）"
            )
        }

        // 反向：组合记号在**前面**时原本就能拦下（那时是两个独立字素簇）。
        // 这条守的是"换个写法也得拦住" —— 拦不拦不该取决于组合记号写在哪一侧。
        #expect(BranchName.validate("a\u{0301}~b") == .containsForbiddenCharacter("~"))
    }

    @Test("③c 全角同形字 / 中文 / emoji 一律放行（本片**不新增规则**，git 也收）")
    func stillAcceptsFullWidthLookalikes() {
        // 判据从"字素簇"换成"标量"**只堵漏、不加规则** ⇒ 下面是"没有误伤"的反证。
        // ⚠️ 中文输入法下打 `~` / `?` 默认出全角（U+FF5E / U+FF1F），而 git 禁的是**半角**
        //    （实测：半角八个全拒、全角同形字全收）⇒ 这条对中文用户是**默认手感**，不是边角案例。
        // ⚠️ 想要"分支名只许英文"是**另一个产品口径**，做法是反过来只放行 ASCII（白名单），
        //    不是拉黑同形字 —— 同形码位有几十个，永远拉不完。
        let accepted = [
            "～", "〜", "？", "＊", "：", "＾", "［", "＼", "｜",  // 全角同形字（U+FF5E / U+301C …）
            "～\u{0301}",          // 全角 + 组合记号（`git check-ref-format` 实测接受）
            "a\u{00A0}b",          // 不间断空格
            "a\u{3000}b",          // 全角空格
            "e\u{0301}",           // 分解形式的 é（合法字符的分解，不该被误伤）
            "功能/修复", "修复-🚀", "中文分支",
        ]
        for name in accepted {
            #expect(BranchName.validate(name) == nil, "「\(name)」应当放行")
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

    @Test("⚠️ 提示语里那个字符**只印一遍**，且八条禁字符一个都不能少")
    func forbiddenCharacterMessageIsCompleteAndDeduplicated() {
        // 病根：句子是"不能包含 \(character)、空格，以及 ~ ^ : ? * [ \ 这些字符" ——
        // `~` 那一次会印成「不能包含 ~、空格，以及 ~ ^ : ? * [ \ 这些字符」。
        // ⚠️ 用**不变量**断言（"出现次数 == 1"），不是逐条对期望值：这样以后加禁字符也不用改测试。
        for character in Self.forbiddenChars {
            let message = BranchNameCopy.message(for: .containsForbiddenCharacter(character))
            let occurrences = message.components(separatedBy: String(character)).count - 1
            #expect(occurrences == 1, "「\(character)」在「\(message)」里应只出现一次（实际 \(occurrences) 次）")
        }

        // 完整性：不管报的是哪一个，其余禁字符都得在提示里露脸 —— 提示是用户一次看全规则的地方。
        // （空格走"分支名不能包含空格"那一句，只有五个字，不列字符表。）
        for character in Self.forbiddenChars {
            let message = BranchNameCopy.message(for: .containsForbiddenCharacter(character))
            for other in Self.forbiddenChars {
                #expect(
                    message.contains(String(other)),
                    "「\(other)」应当出现在「\(message)」里"
                )
            }
        }
        #expect(BranchNameCopy.message(for: .containsForbiddenCharacter(" ")) == "分支名不能包含空格")
    }
}
