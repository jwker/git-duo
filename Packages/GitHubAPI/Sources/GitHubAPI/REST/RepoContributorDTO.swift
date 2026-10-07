import Foundation

/// 贡献者 —— `GET /repos/{owner}/{repo}/contributors` 的元素（TECH_SPEC §9.11、§4.6.3）。
///
/// ## 顺序即语义：**服务端已按贡献次数降序**
///
/// 这个端点按 `contributions` 降序返回。PRD §4.13 第 8 条的「头像 + 以及另外 {N} 位贡献者」
/// 就是取**前几位**，所以本类型**有意不解码 `contributions`** ——
/// 界面不显示它，而"顺序已经代表了它"。自己再排一次反而多一处可能排错的地方。
///
/// ## 两个字段都可空，且这是**必须**的
///
/// GitHub 的贡献者是**按提交邮箱**归并的，只有前 500 个邮箱能关联到账号，
/// 其余会以"匿名贡献者"出现（没有 `login`、也没有 `avatar_url`）。
/// 若把 `login` 声明成必需的 `String`，**一个匿名贡献者会让整个数组解码失败**
/// —— 表现是"这个仓库的贡献者整块显示不出来"，而它其实只差一个名字。
public struct RepoContributorDTO: Sendable, Equatable, Decodable {

    /// 登录名。**可以是 `null`**（匿名贡献者，见类型说明）。
    /// 它也是身份键：头像堆叠的去重与 `ForEach` 的 id 都该用它，`nil` 时按位置兜底。
    public let login: String?

    /// 头像地址。**可以是 `null`**（同上；也可能因为隐私设置没有头像）。
    public let avatarURL: String?

    public init(login: String? = nil, avatarURL: String? = nil) {
        self.login = login
        self.avatarURL = avatarURL
    }

    private enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatar_url"
    }
}
