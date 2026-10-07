import Foundation
import Testing

@testable import GitDuoKit

/// 提交信息的拆分规则（首行 = 标题 / 其余 = 正文）。
///
/// 这个套件的重头是 **CRLF** —— 它是 6.2 唯一挖出来的**真缺陷**，
/// 而症状是"页面看着有内容、只是内容拼错了"：目录行副标题里标题与正文挤成一段，
/// 详情页正文整块消失，**单看任何一处都不报错**。
///
/// 根因不在逻辑，在 Swift 的 `Character`：
/// **`\r`、`\n`、`\r\n` 是三个互不相同的 `Character`** ⇒ `split(separator: "\n")`
/// 在 CRLF 文本上一刀都切不动（见 `crlfIsOneCharacter`）。
@Suite("提交信息拆分 · 首行 / 正文 / CRLF")
struct CommitMessageTests {

    // MARK: - 这个缺陷的根因（把它本身钉住，别只钉结果）

    @Test("⚠️ 根因：Swift 把 `\\r\\n` 当作**一个** Character，按 `\"\\n\"` 拆一刀都拆不动")
    func crlfIsOneCharacter() {
        // 这一条不是"测试我们的代码"，是把**语言事实**记在测试里：
        // 将来有人看到 `replacingOccurrences(of: "\r\n", with: "\n")` 觉得多余想删，
        // 这两个断言会立刻告诉他为什么不能删。
        #expect("\r\n".count == 1)

        // 裸拆：CRLF 文本一整段都是"首行"
        let naive = "a\r\nb"
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        #expect(naive.count == 1)

        // 归一之后再拆：两行
        let normalized = CommitMessage.normalized("a\r\nb")
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        #expect(normalized.count == 2)
    }

    // MARK: - CRLF（真缺陷的直接回归）

    @Test("⚠️ `a\\r\\nb` 必须拆成两行（6.2 的真缺陷：曾经拆不动）")
    func crlfSplits() {
        #expect(CommitMessage.firstLine("a\r\nb", fallback: "-") == "a")
        #expect(CommitMessage.body("a\r\nb") == "b")
    }

    @Test("⚠️ CRLF 的两段式提交信息：标题与正文各归各的（现实里最常见的那种消息）")
    func crlfTwoParagraphs() {
        let message = "fix: 面包屑跳级\r\n\r\n正文第一行\r\n正文第二行"
        #expect(CommitMessage.firstLine(message, fallback: "-") == "fix: 面包屑跳级")
        // 正文自己内部的 CRLF 同样要被归一（否则界面上正文是一整段不换行）
        #expect(CommitMessage.body(message) == "正文第一行\n正文第二行")
    }

    @Test("⚠️ 标题末尾的 `\\r` 不许留在标题里（它在界面上是一个看不见的空位）")
    func crlfDoesNotLeakCarriageReturn() {
        let headline = CommitMessage.firstLine("feat: x\r\n", fallback: "-")
        #expect(headline == "feat: x")
        #expect(headline.contains("\r") == false)
    }

    @Test("归一只认 `\\r\\n`：单独的 `\\r` 不是行尾（与 git 的 `%s` 一致）")
    func loneCarriageReturnIsContent() {
        // git 只把 `\r\n` 当行尾；单独一个 `\r` 属于**内容**。
        // 这里跟随 git —— 我们不是在发明换行规则。
        #expect(CommitMessage.firstLine("a\rb", fallback: "-") == "a\rb")
        #expect(CommitMessage.body("a\rb") == nil)
    }

    // MARK: - LF（本来就没坏的路径，钉住别被"顺手改坏"）

    @Test("LF：两段式")
    func lfTwoParagraphs() {
        #expect(CommitMessage.firstLine("a\n\nb", fallback: "-") == "a")
        #expect(CommitMessage.body("a\n\nb") == "b")
    }

    @Test("正文保留内部空行（不是只取第二行）")
    func bodyKeepsInternalBlankLines() {
        #expect(CommitMessage.body("a\n\nb\n\nc") == "b\n\nc")
    }

    @Test("正文首尾空白被吃掉；只有空白 ⇒ `nil`（详情页据此整块不渲染）")
    func bodyTrimsAndCollapses() {
        #expect(CommitMessage.body("a\n\n  \n b \n") == "b")
        #expect(CommitMessage.body("a\n\n   \n") == nil)
        #expect(CommitMessage.body("a") == nil)
        #expect(CommitMessage.body("a\n") == nil)
    }

    // MARK: - 空信息回落

    @Test("空信息 / 只有空白 ⇒ 回落到 `fallback`（调用点给短 SHA）")
    func emptyFallsBack() {
        #expect(CommitMessage.firstLine("", fallback: "ab12cd") == "ab12cd")
        #expect(CommitMessage.firstLine("\n\n", fallback: "ab12cd") == "ab12cd")
        #expect(CommitMessage.firstLine("   ", fallback: "ab12cd") == "ab12cd")
        // CRLF 版同样要回落 —— 归一漏了这里，空信息就会显示成一行空白
        #expect(CommitMessage.firstLine("\r\n\r\n", fallback: "ab12cd") == "ab12cd")
    }

    @Test("首行内部的空白不动（只吃首尾）")
    func firstLineKeepsInnerSpacing() {
        #expect(CommitMessage.firstLine("  fix:  a  b  \n正文", fallback: "-") == "fix:  a  b")
    }
}
