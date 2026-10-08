import Testing

@testable import GitDuoKit

/// 作者拿不到时的显示名（Issue 评论 / Issue 正文 / PR 对话 / PR 状态说明四处共用）。
///
/// ## 这组断言守的是一条"松了一半也不报错"的规则
///
/// 判据是两句：`nil` ⇒ 兜底；**空串也 ⇒ 兜底**。漏掉后半句时，服务端给一个空串
/// （它把"没填"与"填了空"当两种写法）就会渲染出一个空名字 ——
/// 屏幕上表现为"作者名那一块莫名其妙地空着"，看起来不像一个 bug。
///
/// 切片 7.4 之前这段判据在四个类型里各写了一遍（逐字相同），
/// 现在收成 `AuthorName.display(_:)` 一处 ⇒ 这一条断言替的是四处。
@Suite("作者显示名 · 唯一判据")
struct AuthorNameTests {

    @Test("正常登录名原样返回")
    func normalLoginPassesThrough() {
        #expect(AuthorName.display("reviewer-a") == "reviewer-a")
        #expect(AuthorName.display("you") == "you")
    }

    @Test("⚠️ `nil` 与**空串**同一种处理（服务端是两种写法，屏幕上一件事）")
    func missingAndEmptyAreTreatedAlike() {
        #expect(AuthorName.display(nil) == AuthorName.unknown)
        #expect(AuthorName.display("") == AuthorName.unknown)
    }

    @Test("⚠️ 兜底词是「已注销账号」而**不是**「未知用户」/「匿名」")
    func fallbackWordingIsHonest() {
        // 「未知用户」听起来像一个真实的账号名（"用户"两个字在 GitHub 上到处都是），
        // 而这里的实情是确凿的：那个账号被删了。
        // 「匿名」也不行 —— 匿名是一个可选状态，账号被删不是。
        #expect(AuthorName.unknown == "已注销账号")
        #expect(AuthorName.unknown != "未知用户")
        #expect(AuthorName.unknown != "匿名")
    }

    @Test("⚠️ 判据的**边界**：只覆盖 `nil` 与空串，空白串会原样返回")
    func whitespaceIsOutsideTheBoundary() {
        // 真实登录名字符集里不可能有空格（GitHub 只允许字母数字与连字符）
        // ⇒ 这是个"不该出现"的输入，规格没有给它口径。
        //
        // 本断言**不是**在说"原样返回最好"，而是把边界钉在明面上：
        // 判据是 `!isEmpty`，不是 `trimmed.isEmpty`。要改成把空白也兜底，
        // 改 `AuthorName.display` 一处即可 —— 而在此之前，
        // 一处悄悄多写的 `trim` 会让四个调用点的行为分叉（那一处显示「已注销账号」、
        // 另外三处显示空白），且没有任何报错。
        #expect(AuthorName.display(" ") == " ")
    }
}
