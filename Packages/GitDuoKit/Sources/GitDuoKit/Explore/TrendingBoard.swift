import Foundation

/// 探索页的两个榜单（PRD §4.12 / TECH_SPEC §9.10.1）。
///
/// 文案**逐字取自原型**（`scripts/09-explore.js` 分段条那两个按钮的字面量）——
/// 原型是"唯一可点验收依据"。
///
/// ⚠️ 原型原先还有一个 `BOARDS` 常量，喂给列表标题那一行（`新星榜 · 5 个仓库`）；
/// 2026-10-16 那一行连常量一起删了（走查第 **78** 条）⇒ 榜单名现在**只出现在分段控件上**。
public enum TrendingBoard: String, Sendable, Hashable, CaseIterable, Identifiable {

    /// 新星榜：近 90 天新建的仓库，按**近期新增 Star** 降序（体现"近期涌现"）。
    case rising

    /// 活跃榜：所选时间窗内**有推送**的仓库，按**最近推送时间**降序（体现"持续活跃"）。
    case active

    public var id: String { rawValue }

    /// 榜单名 —— **只出现在分段控件上**（列表标题那行已于 2026-10-16 删掉，走查第 78 条）。
    public var title: String {
        switch self {
        case .rising: "新星榜"
        case .active: "活跃榜"
        }
    }
}
