import Foundation

/// REST 仓库对象里的 `owner` 摘要 —— **本项目只消费头像地址**。
///
/// 三个仓库 DTO（列表 `RepositoryDTO` / 搜索 `SearchRepositoryDTO` / 详情 `RepositoryDetailDTO`）
/// 共用这一份：GitHub 的仓库对象恒带一个 `owner` 对象（用户或组织），
/// 2026-10-15 起列表行 / 详情头要把文件夹图标换成 **owner 头像**（走查第 72 条），
/// 于是把这条"本来就在响应里"的数据接进来 —— **零额外请求**。
///
/// ## ⚠️ `login` 有意不取
///
/// 各 DTO 已有 `full_name`（`owner/name`），owner 登录名由它派生 —— 再取一份 `owner.login`
/// 就是同一事实的两个来源，而两处迟早会有一处没人同步。
/// 首字母兜底用的"名字"同样从 `full_name` 拆，不走这里。
///
/// ## ⚠️ EMU 账号的头像地址是短时效的
///
/// GitHub 对企业托管账号（EMU）会返回 `private-avatars.githubusercontent.com` 上的
/// **带 JWT 的地址，约 20 分钟失效**（社区讨论 #147297，GitHub 员工答复）。
/// ⇒ 消费侧（`UserAvatar`）取不到就回退**首字母兜底圆**，不要把这里的地址
/// 当成长期资产落盘后再怪它失效 ——「最近访问」落盘的正是这个地址，
/// 失效的表现只是那一行退化成首字母，可接受（走查第 72 条已如实登记）。
public struct RepositoryOwnerDTO: Sendable, Equatable, Decodable {

    /// owner 的头像地址。**可以是 `null`** —— 理论上不该发生，但"图取不到就回退"
    /// 已是本项目头像消费的既定口径（`UserAvatar`），这里不必为它造一个错误态。
    public let avatarURL: URL?

    public init(avatarURL: URL? = nil) {
        self.avatarURL = avatarURL
    }

    private enum CodingKeys: String, CodingKey {
        case avatarURL = "avatar_url"
    }
}
