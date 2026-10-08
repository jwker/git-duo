import Foundation

/// 一个 GitHub 账号的**最小引用** —— 只带登录名（切片 7 新增）。
///
/// ## 为什么在切片 7 才提出来
///
/// 切片 4 时它叫 `IssueDTO.Author`（嵌在 `IssueDTO` 里），因为那时**只有 Issue 卡片**用得上。
/// 切片 7 一下子有三个新场景要用同一个形状 —— Issue 详情的创建者、评论作者、PR 详情与评审的作者 ——
/// 再嵌下去就会变成"每个 DTO 里各嵌一个同名小结构"，那是**分叉的标准起点**
/// （`AGENTS.md`：同一个东西两处定义 ⇒ 必然有一天长得不一样）。
/// 所以提到顶层，**一份定义**。
///
/// ## 为什么没有 `avatar_url`
///
/// 界面上的头像一律由 `UserAvatar` 从 `login` **现算**（首字母 + 由登录名派生的底色，
/// 见切片 5.4 的说明），本项目**不加载网络头像**。于是 `avatar_url` 没有任何消费端，
/// 声明它就等于多一处会因服务端形状变化而炸的地方（"只声明真正用到的字段"）。
///
/// ## 为什么没有 `id`
///
/// 同上：本项目的去重键一律用 `login`（仓库内 / 会话内足够唯一），
/// 而数字 `id` 一旦被谁拿去做键，就会与 `login` 形成两个"身份"。
public struct AuthorDTO: Sendable, Equatable, Decodable {

    /// 登录名。**服务端对已删除账号返回的是 `null` 整段 `user`**（不是 `login: null`），
    /// 所以引用方一律声明成 `AuthorDTO?`，而不是 `login: String?` —— 见各 DTO 的 `user` 字段。
    public let login: String

    public init(login: String) {
        self.login = login
    }
}
