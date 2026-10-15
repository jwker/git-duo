import Foundation
import GitHubAPI

/// `RepositoryDetailDTO` → `RepositoryDetail` 的**唯一**映射。
///
/// 依据：TECH_SPEC §9.11、PRD §4.13 第 1 条。
///
/// ## 为什么要单独一个类型（6.4 提取）
///
/// 切片 4 的 `LoadRepoInsights` 里有一份 `private static func detail(from:)`，
/// 而切片 6 的仓库详情页（§4.4）要**同一份**头部数据。
/// 复制一份的后果不是多十几行，而是两条链路会**分叉**：
/// 同一个仓库在"自己的详情页"和"探索详情页"上显示成不同的许可证 / 不同的关注者数，
/// 而两处单看都正常（同 `CommitMessage` 的告诫）。
///
/// ⚠️ 两页的**字段集**也确实不同（§4.4 的头部不画 `更新 · 许可证`、不画话题标签），
/// 但那是**渲染**的差异，不是**映射**的差异 —— 映射这一步两边取的是同几个字段、
/// 同几条兜底规则。把渲染差异塞进映射层（例如加一个 `forExplore: Bool`）
/// 会让"哪个页面少显示了什么"变成映射层的分支，那是视图该管的事。
public enum RepositoryDetailMapper {

    /// 组装头部模型。
    ///
    /// 三处**兜底**都在这里，且都不是随手给的默认值：
    /// - `topics` 缺席 ⇒ 空数组（「响应里省略了」与「就是没有标签」在界面上等价）；
    /// - 许可证走 `LicenseLabel.text` —— ⚠️ `spdx_id` 可能是哨兵值 `NOASSERTION`，
    ///   直接显示会得到「NOASSERTION 许可证」这种东西；
    /// - `permissions` 缺席 ⇒ `.none`（**不是**"默认可写"）。
    public static func detail(from dto: RepositoryDetailDTO) -> RepositoryDetail {
        RepositoryDetail(
            fullName: dto.fullName,
            description: dto.description,
            topics: dto.topics ?? [],
            licenseLabel: LicenseLabel.text(spdxID: dto.license?.spdxID, name: dto.license?.name),
            defaultBranch: dto.defaultBranch,
            starCount: dto.starCount,
            forkCount: dto.forkCount,
            // ⚠️ `watcherCount` 读的是 `subscribers_count`，见 `RepositoryDetail` 的说明：
            //    读成 `watchers_count` 会让 `Watch · n` 与 `Star · n` 恒相等（那是个历史别名）。
            watcherCount: dto.watcherCount,
            pushedAt: dto.pushedAt,
            permissions: Permissions(dto.permissions),
            ownerAvatarURL: dto.owner.avatarURL
        )
    }
}
