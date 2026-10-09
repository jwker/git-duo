import Foundation

/// 「我的」页个人资料头部 —— `GET /user` 的响应（TECH_SPEC §9.14、PRD §4.17、决策 #76）。
///
/// ## 为什么**不复用** `AuthenticatedUser`
///
/// `AuthenticatedUser` 是**登录第 8 步那条路径的契约**（§3.1）：它只声明 `login`，
/// 而且刻意收窄 —— 那一刻的用途是"校验令牌有效性"，多一个字段就多一处
/// "令牌有效但响应形状变了"的失败面。它自己也写着"完整的个人页模型由后续切片扩展，
/// **届时是扩展本类型还是另立 DTO，以那时的事实为准**"。
///
/// 这里选**另立**：两者的消费方、失败后果、字段集都不同（登录失败 = 进不去 App；
/// 我的页取不到 = 这一块降级）。合在一起会让"登录能不能成功"取决于一个它并不需要的字段。
///
/// ## 字段可选性：照官方 OpenAPI 抄，不凭直觉（2026-10-09 核实）
///
/// 来源 `github/rest-api-description` 的 `api.github.com.json`。`GET /user` 的 200
/// **有两个形状**，由 `user_view_type` 判别（`public` / `private`）：
///
/// | 字段 | `public-user` | `private-user` |
/// |---|---|---|
/// | `login` | 必需 | 必需 |
/// | `name` / `bio` | 必需，**可为 `null`** | 必需，**可为 `null`** |
/// | `followers` | **必需**（`integer`，非可空） | **必需**（同上） |
/// | `total_private_repos` | **可选** | 必需 |
///
/// ⇒ 三条结论，都不是猜的：
/// 1. **`followers` 两个形状都恒定返回** ⇒ 声明成非可选 `Int`（决策 #76 说的"恒定返回"得到证实）。
///    ⚠️ 但仍按"这一项拿不到就不画这一项"处理 —— 那不是在防这个字段，是在防**整个请求失败**
///    （见 `ViewerProfile.followers`）。
/// 2. `name` / `bio` **键一定在，值可能是 `null`** ⇒ `String?`（PRD §4.17：取不到时整行不渲染）。
/// 3. `total_private_repos` 在 `public-user` 下**整个键可能不在** ⇒ 若将来要用它，
///    必须按可选解码（决策 #76 已经把这条写进判据了）。
///
/// ## `avatar_url` —— 2026-10-09 补上（此前**有意不声明**，那是个错）
///
/// 本类型原先在这里写着"有意不声明 `avatar_url`"，理由是"声明一个没有消费端的字段，
/// 等于多一处会因为服务端形状变化而炸的地方"。那条理由**当时就与正本矛盾**：
/// `TECH_SPEC §9.14` 的「个人资料头部」那一行一直把 `avatar_url` 列在字段清单里，
/// `§5.3` 更早就定了"头像走 `AsyncImage`"。2026-10-09 用户走完全屏走查报回
/// 「我的 Tab 下没有正确显示头像图片」⇒ 翻两处正本才确认这是**欠账**、不是新要求
/// （`REVIEW-CHECKLIST` 偏差第 43 条）。
///
/// ⚠️ 值得记的教训：**"某个字段没有消费端"这句话会过期** —— 写它的时候（切片 9.1）
/// 确实没有消费端，而同一批规格已经把消费端写进去了。这类矛盾**编译器不报、测试也不报**。
///
/// ## 为什么是 `String?` 而不是 `URL?`
///
/// 同 `RepoContributorDTO`（那份也是 `String?`）。判据不是"哪个更好看"，而是
/// **同一份响应里 GitHub 真的会发空串**：`GET /user` 的官方示例里 `gravatar_id` 就是 `""`。
/// 空串对 `URL` 解码是**会抛错**的（`URL(string: "")` 解不出来），一旦 `avatar_url` 哪天也这样，
/// 后果是**整条 `/user` 解码失败** ⇒ 昵称、简介、关注者数**一起消失**（正是 `RepoContributorDTO`
/// 那条"一个匿名贡献者让整块消失"的同型事故）。
/// 交给映射层 `String?.flatMap(URL.init(string:))` 之后，空串自然变成 `nil`，
/// 而 `nil` 有一个现成的正确渲染（首字母块）—— **失败半径从"整块头部"缩到"一个头像"**。
///
/// ⚠️ 可选而非必需：官方两个形状的示例里它都是非空字符串，但**它们的 required 清单没核实到**
/// （docs 页只给示例、不给 schema 的 `required` 列表）⇒ 取失败半径小的那一侧。
public struct ViewerProfileDTO: Sendable, Equatable, Decodable {

    /// 登录名。**它同时是头像的种子**（`UserAvatar` 的首字母与兜底色都由它派生）。
    public let login: String

    /// 昵称。**可以是 `null`**（很多人不填）⇒ 那一行整行不渲染。
    public let name: String?

    /// 简介。**可以是 `null`** ⇒ 整行不渲染。
    public let bio: String?

    /// 关注者数。官方两个形状都列为必需，所以不写可选分支。
    public let followers: Int

    /// 头像地址（**原样收字符串**，解释成 `URL` 是映射层的事，见类型说明）。
    public let avatarURL: String?

    public init(
        login: String,
        name: String? = nil,
        bio: String? = nil,
        followers: Int,
        avatarURL: String? = nil
    ) {
        self.login = login
        self.name = name
        self.bio = bio
        self.followers = followers
        self.avatarURL = avatarURL
    }

    private enum CodingKeys: String, CodingKey {
        case login
        case name
        case bio
        case followers
        case avatarURL = "avatar_url"
    }
}
