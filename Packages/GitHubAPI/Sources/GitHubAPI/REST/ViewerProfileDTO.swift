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
/// ## 有意**不声明** `avatar_url`
///
/// 同 `AuthorDTO` 的判据：界面上的头像一律由 `UserAvatar` 从 `login` **现算**
/// （首字母 + 由登录名派生的底座色 —— 原型 `12-me.js` 画的也正是
/// `<div class="big-avatar" style="…">J</div>` 这样一个首字母块）。
/// 声明一个没有消费端的字段，等于多一处会因为服务端形状变化而炸的地方。
public struct ViewerProfileDTO: Sendable, Equatable, Decodable {

    /// 登录名。**它同时是头像的种子**（`UserAvatar` 的首字母与兜底色都由它派生）。
    public let login: String

    /// 昵称。**可以是 `null`**（很多人不填）⇒ 那一行整行不渲染。
    public let name: String?

    /// 简介。**可以是 `null`** ⇒ 整行不渲染。
    public let bio: String?

    /// 关注者数。官方两个形状都列为必需，所以不写可选分支。
    public let followers: Int

    public init(login: String, name: String? = nil, bio: String? = nil, followers: Int) {
        self.login = login
        self.name = name
        self.bio = bio
        self.followers = followers
    }
}
