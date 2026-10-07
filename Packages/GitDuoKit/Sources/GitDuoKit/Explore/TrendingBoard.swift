import Foundation

/// 探索页的两个榜单（PRD §4.12 / TECH_SPEC §9.10.1）。
///
/// 文案**逐字取自原型**（`scripts/09-explore.js` 的 `BOARDS = { rising:'新星榜', active:'活跃榜' }`）——
/// 原型是"唯一可点验收依据"，且 harness 直接断言这两个词出现在标题里
/// （`harness.js:326` `default board title 新星榜`、`harness.js:352` `title switches to 活跃榜`）。
public enum TrendingBoard: String, Sendable, Hashable, CaseIterable, Identifiable {

    /// 新星榜：近 90 天新建的仓库，按**近期新增 Star** 降序（体现"近期涌现"）。
    case rising

    /// 活跃榜：所选时间窗内**有推送**的仓库，按**最近推送时间**降序（体现"持续活跃"）。
    case active

    public var id: String { rawValue }

    /// 榜单名 —— 出现在分段控件与列表标题（`新星榜 · 5 个仓库`）两处。
    public var title: String {
        switch self {
        case .rising: "新星榜"
        case .active: "活跃榜"
        }
    }
}
