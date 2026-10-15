import Foundation

/// `GET /user/repos` / `GET /user/starred` 返回的仓库对象（REST 形状）。
///
/// 依据：TECH_SPEC §4.6.2、§6.2。
///
/// ## 只取切片 3 需要的字段
///
/// §6.2 给 `Repository` 列了 13 个字段，但本 DTO 只声明**仓库列表卡片真正用到的**那些。
/// 这不是偷懒，是纪律：`defaultBranch` / `pushedAt` / `license` / `topics` 属于详情页与
/// 探索页（切片 4+），现在把它们猜进来，等于替那时的自己拍板 —— 而字段一旦写进 DTO，
/// 后面的人就会以为它"已经定过"了。需要时再补，补的时候有真实响应可对照。
///
/// ⚠️ **`permissions` 只在已认证请求里返回**，且 GitHub 明确规定它代表
///    "**当前令牌**对该仓库的权限"。所以它是可选的，而"缺失"必须解释成
///    **不可写**（见 `Repository.canWrite`）—— 缺权限时默认可写，
///    会让用户点进编辑器、改完文件、提交时才吃 403。
public struct RepositoryDTO: Sendable, Equatable, Decodable {

    /// `owner/name`。GitHub 保证它有且只有一个 `/`（owner 与 repo 名都不允许含 `/`）。
    public let fullName: String

    public let isPrivate: Bool

    /// 仓库简介。**可以是 `null`**（未填简介的仓库很常见）。
    public let description: String?

    /// 主语言。**可以是 `null`**（空仓库、或只有配置文件）。
    public let language: String?

    public let starCount: Int

    public let forkCount: Int

    /// 当前令牌对该仓库的权限全集。**未认证 / 无权限时为 `nil`**。
    public let permissions: RepositoryPermissionsDTO?

    /// owner 摘要 —— 目前只消费头像地址（走查第 72 条：列表行换 owner 头像）。
    ///
    /// **必需**（非可选）：GitHub 的仓库对象恒带 `owner`；真缺了说明响应形状已经变了，
    /// "解码失败、整页报错"比"默默退化成首字母块"诚实（同 `starCount` 的口径）。
    public let owner: RepositoryOwnerDTO

    public init(
        fullName: String,
        isPrivate: Bool,
        description: String? = nil,
        language: String? = nil,
        starCount: Int = 0,
        forkCount: Int = 0,
        permissions: RepositoryPermissionsDTO? = nil,
        owner: RepositoryOwnerDTO = RepositoryOwnerDTO()
    ) {
        self.fullName = fullName
        self.isPrivate = isPrivate
        self.description = description
        self.language = language
        self.starCount = starCount
        self.forkCount = forkCount
        self.permissions = permissions
        self.owner = owner
    }

    private enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case isPrivate = "private"
        case description
        case language
        case starCount = "stargazers_count"
        case forkCount = "forks_count"
        case permissions
        case owner
    }

    // ⚠️ `starCount` / `forkCount` 有意声明为**必需**（非 `Int?`）。
    //    它们在 GitHub 的仓库对象里恒存在；真缺了说明响应形状已经变了，
    //    此时"解码失败、整页报错"比"默默显示 0 个 Star"诚实得多 ——
    //    后者会让用户以为自己的项目没人 star。
}

/// REST 返回的 `permissions` 对象：`{admin, maintain, push, triage, pull}`。
///
/// 依据：TECH_SPEC §6.2（"REST 返回的 `{admin,maintain,push,triage,pull}` 全集"）。
///
/// ⚠️ 五个字段都声明为 `Bool?`：GitHub 在不同情形下会省略其中某些键
///    （例如协作者可能没有 `admin` / `maintain`）。用非可选 `Bool` 会让
///    "省略"变成**解码失败**，而这明明是一个正常响应。
public struct RepositoryPermissionsDTO: Sendable, Equatable, Decodable {

    public let admin: Bool?
    public let maintain: Bool?
    public let push: Bool?
    public let triage: Bool?
    public let pull: Bool?

    public init(
        admin: Bool? = nil,
        maintain: Bool? = nil,
        push: Bool? = nil,
        triage: Bool? = nil,
        pull: Bool? = nil
    ) {
        self.admin = admin
        self.maintain = maintain
        self.push = push
        self.triage = triage
        self.pull = pull
    }
}
