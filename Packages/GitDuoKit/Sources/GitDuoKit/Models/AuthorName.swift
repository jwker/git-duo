import Foundation

/// 作者登录名拿不到时的显示名（Issue 评论 / PR 评审 / PR 头部都有这个情形）。
///
/// ## 为什么会有一个单独的类型放这一个常量
///
/// Issue 评论、PR 评审、PR 的三句状态说明里都可能出现"这个人的账号已经被删了"
/// （GitHub 会把整段 `user` 置成 `null`）。三处各写一句占位名的下场不是多几行 ——
/// 而是三处会渐渐用不同的词（`未知用户` / `已注销` / `匿名`），
/// 而**用户会把它们读成三件不同的事**。
///
/// ## 为什么是「已注销账号」而不是「未知用户」
///
/// 「未知用户」听起来像一个真实的账号名（"用户"两个字在 GitHub 上到处都是），
/// 而这里的实情是**确凿的**：那个账号被删了。说确切的那一句。
/// 同理由是它**不叫** `匿名` —— 匿名是一个可选状态，账号被删不是。
public enum AuthorName {

    /// 账号已删除时的显示名。
    public static let unknown = "已注销账号"

    /// 由登录名得到**显示名** —— 唯一的那个函数。
    ///
    /// ## 为什么它不是四个类型各自算一遍
    ///
    /// 到切片 7.4 为止，需要它的地方有四处：`IssueComment`（评论作者）、
    /// `IssueDetail`（正文气泡的作者）、`PullTimelineItem`（对话流的作者）、
    /// `PullDetail`（三句状态说明里的作者）。四段实现逐字相同：
    ///
    /// ```swift
    /// guard let authorLogin, !authorLogin.isEmpty else { return AuthorName.unknown }
    /// return authorLogin
    /// ```
    ///
    /// 四份的坏处不是行数，而是**判据会在某一处松动**：漏掉 `!isEmpty` 那一半时，
    /// 服务端给一个空串（它把"没填"与"填了空"当两种写法）就会渲染出一个空名字 ——
    /// 屏幕上表现为"作者名那一块莫名其妙地空着"，不像一个 bug。
    ///
    /// ⚠️ `nil` 与 `""` 在这里**同一种处理**：它们在服务端是两种写法，在屏幕上是一件事
    /// （同 `IssueDetail.hasBody` 对 `body` 的口径）。
    public static func display(_ login: String?) -> String {
        guard let login, !login.isEmpty else { return unknown }
        return login
    }
}
