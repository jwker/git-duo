import Foundation
import GitDuoCore

/// 仓库详情的头部 —— `GET /repos/{owner}/{repo}` 的领域形态（PRD §4.13 第 1 条、TECH_SPEC §9.11）。
///
/// ## 为什么不再复用 `Repository`
///
/// `Repository` 需要 `permissions` 与 `isPrivate` 两个**必有**的量，而
/// `RepositoryDetailDTO` **不解码私有性**（头部不显示它），可以复用会逼着这里填一个假值。
/// 反过来，头部需要的 `topics` / `license` / `defaultBranch` / `watcherCount`
/// 又是 `Repository` 没有的 —— 两边字段集**互有出入**，合并不成立
/// （与 `RepositoryDTO` / `RepositoryDetailDTO` 不合并同源）。
///
/// ## ⚠️ `permissions` 在这里，但**不许**用它分支出可写入口
///
/// 本页（§4.13）**不含任何写操作**，而"这是他人仓库"是由**路由**在进入前定下的
/// —— `ReposView` 按 `Repository.canWrite` 二选一推入 `.repoDetail` / `.exploreRepoDetail`
/// （TECH_SPEC §8.3、铁律 #7：只读态显式传参，不让下层页自行推断）。
///
/// 保留 `permissions` 有两个具体理由：① DTO 里本来就有，映射时丢掉它属于"静默丢字段"；
/// ② 切片 6 的只读文件页与切片 7 的 PR 详情会从本页往下走，那时需要它。
/// **但不要**因为 `canWrite == true` 就在这里长出编辑 / 提交入口 ——
/// 那会让"两种入口能做的事不一致"，而这正是铁律 #7 要挡的。
public struct RepositoryDetail: Sendable, Hashable, Identifiable {

    public let fullName: String
    public let description: String?

    /// 话题标签。**空数组与"响应里省略了"等价**（都是"没有标签"），见 `RepositoryDetailDTO`。
    public let topics: [String]

    /// 许可证标签 —— 已解释成可直接显示的一句话（`MIT` / `未指定`），见 `LicenseLabel`。
    public let licenseLabel: String

    /// 默认分支名（切片 6 的"进仓库先解析默认分支"要用它）。
    public let defaultBranch: String

    public let starCount: Int
    public let forkCount: Int

    /// ⚠️ **关注者数**，来源是 `subscribers_count`。不是 `watchers_count`
    /// （那个是 `stargazers_count` 的历史别名，与 Star 数恒相等）——
    /// 读错不会报错，只会让 `Watch · 45` 和旁边的 `Star · 45` 显示成同一个数。
    public let watcherCount: Int

    /// 最近推送时间。**可以是 `nil`**（从未推送过任何提交的仓库）。
    public let pushedAt: Date?

    /// 当前令牌对该仓库的权限（可写性判定的唯一来源）—— ⚠️ 本页不要用它分支，见类型说明。
    public let permissions: Permissions

    /// owner 的头像地址。**可以是 `nil`** —— 取不到时界面回退首字母兜底圆（走查第 72 条）。
    ///
    /// 来源是 `GET /repos/{o}/{r}` 响应里本来就有的 `owner.avatar_url`（零额外请求）。
    /// ⚠️ 别当长期资产：EMU 账号的地址约 20 分钟失效（`RepositoryOwnerDTO` 的说明）。
    public let ownerAvatarURL: URL?

    /// ⚠️ **公开构造是有意的**，但它不是生产路径。
    ///
    /// 生产路径**只有一条**：`LoadRepoInsights` 走 `RepoInsightsMapper` 从
    /// `RepositoryDetailDTO` 映射。这里开放出来，是因为 App 层的 `#Preview`（以及将来的
    /// 快照测试）需要造一个样本，而让预览代码去拼一个网络层 DTO 会把 DTO 的形状
    /// 渗进 UI 层 —— 那正是"数据层的形状不许外溢"要挡的。
    ///
    /// 字段默认值只给"确实有天然缺省"的那几个（描述可以为空、没有标签、没有许可证、
    /// 从未推送、没有权限）；`starCount` / `forkCount` / `watcherCount` / `defaultBranch`
    /// **必须显式给** —— 给它们编一个默认数会让"忘了传"编译通过，而界面上看起来完全正常。
    public init(
        fullName: String,
        description: String? = nil,
        topics: [String] = [],
        licenseLabel: String = LicenseLabel.unspecified,
        defaultBranch: String,
        starCount: Int,
        forkCount: Int,
        watcherCount: Int,
        pushedAt: Date? = nil,
        permissions: Permissions = .none,
        ownerAvatarURL: URL? = nil
    ) {
        self.fullName = fullName
        self.description = description
        self.topics = topics
        self.licenseLabel = licenseLabel
        self.defaultBranch = defaultBranch
        self.starCount = starCount
        self.forkCount = forkCount
        self.watcherCount = watcherCount
        self.pushedAt = pushedAt
        self.permissions = permissions
        self.ownerAvatarURL = ownerAvatarURL
    }

    public var id: String { fullName }

    /// 拆出来的 owner / 仓库名 —— 走 `RepositoryMapper.splitFullName` 那**一个**实现。
    public var owner: String { (try? RepositoryMapper.splitFullName(fullName))?.owner ?? "" }

    public var name: String { (try? RepositoryMapper.splitFullName(fullName))?.name ?? fullName }

    public var canWrite: Bool { permissions.canWrite }

    /// 推送时间为空时头部显示的占位（原型 `TRENDING` 的兜底对象写的是 `upd:'未知'`）。
    public static let unknownUpdateLabel = "未知"

    /// `{更新时间} 更新` 里的那一段。
    ///
    /// ⚠️ 时间**现算**（`RelativeTime`），不存字符串 —— 存字符串会让"2 小时前"永远停在
    /// "2 小时前"（原型就是这么存的，见 `RelativeTime` 的类型说明）。
    public func updatedLabel(now: Date) -> String {
        pushedAt.map { RelativeTime.string(from: $0, now: now) } ?? Self.unknownUpdateLabel
    }

    /// 头部全名下方那一行：`{更新时间} 更新 · {许可证} 许可证`（逐字对齐原型 `10-explore-repo.js:13`）。
    public func metaLabel(now: Date) -> String {
        "\(updatedLabel(now: now)) 更新 · \(licenseLabel) 许可证"
    }
}

/// 许可证标签的解释（`RepositoryDetailDTO.License` → 一句可显示的话）。
///
/// ## 为什么需要它
///
/// REST 的 `license` 对象给两个字段，而**两个都不总能直接用**：
/// - `spdx_id` 是短名（`MIT` / `Apache-2.0`），正是原型要显示的那一档；
///   但它在"有 LICENSE 文件却不是标准许可证"时会是字符串
///   **`NOASSERTION`** —— 那是 GitHub 的"我认不出来"，不是许可证名。
/// - `name` 是完整名（`MIT License`），只在 `spdx_id` 不可用时才退到它。
/// - 两者都没有（未指定许可证的仓库很常见）⇒ `未指定`。
///
/// ⚠️ 漏掉 `NOASSERTION` 这一档，界面上会出现 **`NOASSERTION 许可证`** 这种东西 ——
/// 它既不是中文也不是许可证名，而用户完全无从知道那是什么意思。
public enum LicenseLabel {

    /// 无许可证时的文案（原型 `TRENDING` 的兜底对象写的是 `lic:'未指定'`）。
    public static let unspecified = "未指定"

    /// GitHub 用来表示"认不出这个许可证"的哨兵值 —— **不是一个 spdx 短名**。
    public static let noAssertionSentinel = "NOASSERTION"

    public static func text(spdxID: String?, name: String?) -> String {
        if let spdx = spdxID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !spdx.isEmpty,
           spdx.uppercased() != noAssertionSentinel {
            return spdx
        }
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return unspecified
    }
}
