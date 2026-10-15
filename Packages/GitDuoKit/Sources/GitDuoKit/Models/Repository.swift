import Foundation

/// 仓库 —— 领域模型（PRD §3.1、TECH_SPEC §6.2）。
///
/// ⚠️ **它与 `RepositoryDTO` 是两个类型，不是"多此一举"**：
/// DTO 是 GitHub 的响应形状（`snake_case`、可空性由服务端决定、字段随接口变），
/// 本类型是**产品语义**（`owner` / `name` 已拆开、`canWrite` 已算好、不认识的字段根本不进来）。
/// 把两者合并，等于让界面上的每一个判断都直接依赖 GitHub 的 JSON 形状 ——
/// 那样一次 API 改字段，全 App 都要跟着改。
///
/// 另有命名提示：本类型叫"仓库"，而 §2.1 里 `Repository` 一词也指"仓储"这个模式。
/// 为避免混淆，本项目把**仓储/取数**类型一律按动作命名（如 `LoadRepositoriesPage`），
/// 不叫 `XxxRepository`。
public struct Repository: Sendable, Hashable, Identifiable {

    /// 拥有者登录名。
    public let owner: String

    /// 仓库名。
    public let name: String

    /// 仓库简介。**可以是 `nil`**（未填简介的仓库很常见）。
    public let description: String?

    /// 是否私有。⚠️ 它与"能不能写"是**两个独立维度**（PRD §3.1）：
    /// 自己的私有仓库既私有又可写；他人的公开仓库公开但只读。
    public let isPrivate: Bool

    /// 主要语言。**可以是 `nil`**（空仓库、或只有配置文件）。
    public let language: String?

    public let starCount: Int

    public let forkCount: Int

    /// 当前令牌对该仓库的权限全集。
    public let permissions: Permissions

    /// owner 的头像地址。**可以是 `nil`** —— 取不到（或没取到）时界面回退首字母兜底圆。
    ///
    /// ## 它从哪来（走查第 72 条，2026-10-15）
    ///
    /// 列表行 / 详情头把文件夹图标换成了 **owner 头像**，地址来自 REST 响应里
    /// 本来就有的 `owner.avatar_url` —— 零额外请求。`nil` 的三种来路都要能兜住：
    /// 旧测试夹具没带、EMU 账号的短时效地址取不到、以及将来任何"响应没给"的情形
    /// —— 兜底表现统一是首字母圆块（`UserAvatar`），**不该有第三种样子**。
    ///
    /// ⚠️ 别拿它当长期资产：EMU 的地址约 20 分钟失效（`RepositoryOwnerDTO` 的说明）。
    public let ownerAvatarURL: URL?

    /// `owner/name` —— 唯一标识，也是路由、缓存与本地记忆的键。
    public var fullName: String { "\(owner)/\(name)" }

    /// `Identifiable` 的 id 用全名：列表去重、`ForEach` 稳定性都依赖它。
    /// ⚠️ 不要用自增序号 —— 分页追加时序号会变，列表会整片重绘、滚动位置跳。
    public var id: String { fullName }

    /// **可写性判定 —— 全项目唯一来源**（TECH_SPEC §8.1、铁律 #7）。
    ///
    /// 它决定点进仓库后走「可写工作台」还是「只读阅览室」，因此**禁止**任何地方
    /// 用名称前缀、静态名单或"是不是我自己的账号"来另判一次 ——
    /// 两处判定必然出现分歧，而分歧的表现是"某个入口能编辑、另一个入口不能"。
    public var canWrite: Bool { permissions.canWrite }

    public init(
        owner: String,
        name: String,
        description: String? = nil,
        isPrivate: Bool,
        language: String? = nil,
        starCount: Int,
        forkCount: Int,
        permissions: Permissions = .none,
        ownerAvatarURL: URL? = nil
    ) {
        self.owner = owner
        self.name = name
        self.description = description
        self.isPrivate = isPrivate
        self.language = language
        self.starCount = starCount
        self.forkCount = forkCount
        self.permissions = permissions
        self.ownerAvatarURL = ownerAvatarURL
    }
}

/// REST `permissions` 对象的领域化形态。
///
/// 与 `RepositoryPermissionsDTO` 的区别：DTO 里五个字段是 `Bool?`（服务端会省略键），
/// 这里五个都是 `Bool` —— "省略"这件事**在边界上就被解释掉**，不带着 `nil` 到处跑。
/// 否则每个使用点都要自己想一次"`nil` 算不算有权限"，而那种地方想错的概率很高。
public struct Permissions: Sendable, Hashable {

    public let admin: Bool
    public let maintain: Bool
    public let push: Bool
    public let triage: Bool
    public let pull: Bool

    /// 什么权限都没有 —— 也用于"响应里根本没带 `permissions`"。
    public static let none = Permissions()

    public init(
        admin: Bool = false,
        maintain: Bool = false,
        push: Bool = false,
        triage: Bool = false,
        pull: Bool = false
    ) {
        self.admin = admin
        self.maintain = maintain
        self.push = push
        self.triage = triage
        self.pull = pull
    }

    /// 可写性判定的**唯一实现**：`push == true`（TECH_SPEC §6.2 / §8.1）。
    ///
    /// ⚠️ **有意不由 `admin` / `maintain` 推断**。语义上"是管理员当然能推"，
    /// 但那样就有了两条规则，而两条规则迟早会分歧；规格点名的是 `push`。
    /// 而且判错的代价在这一侧是**保守**的：少显示一个可写入口，
    /// 用户看到的仍是只读页 —— 反过来（缺 `push` 却判成可写）会让他改完文件才吃 403。
    ///
    /// ⚠️ 由此，**`permissions` 缺失 ⇒ 不可写**（`RepositoryMapper` 把它映射成 `.none`）。
    /// 默认成"可写"是一个看起来更友好、实际会伤人的选择。
    public var canWrite: Bool { push }
}
