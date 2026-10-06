import Foundation

/// 仓库列表的四个分段（PRD §4.3 / TECH_SPEC §9.3）。
///
/// 文案**逐字取自原型**（`scripts/05-repo.js` 的 `['全部','公开','私有','Starred']`）——
/// 原型是"唯一可点验收依据"，这四个词是契约，不是随手写的标签。
/// 放在本类型上而不是散在 View 里，是为了让它能被单测守住（见 `RepoListSegmentTests`）。
public enum RepoListSegment: String, Sendable, Hashable, CaseIterable, Identifiable {

    case all
    case publicOnly
    case privateOnly
    case starred

    // ⚠️ 两个过滤段有意**不叫** `public` / `private`：那两个词是 Swift 关键字，
    //    每处使用都要写反引号（`` `public` ``），且极易与访问控制修饰符看混 ——
    //    在代码评审里一眼扫过去，"这个 case 是权限还是段位"分不清。
    //    也不用 `open` / `closed`：那是 Issue 状态的词汇，会和"开放 / 已关闭"撞车。

    public var id: String { rawValue }

    /// 展示文案 —— **与原型逐字一致**。
    public var title: String {
        switch self {
        case .all: "全部"
        case .publicOnly: "公开"
        case .privateOnly: "私有"
        case .starred: "Starred"
        }
    }

    /// 该段的数据来源（§9.3：前三段共用一份数据本地过滤，Starred 另取）。
    public var source: RepoListSource {
        switch self {
        case .all, .publicOnly, .privateOnly: .repos
        case .starred: .starred
        }
    }

    /// 本地过滤规则。Starred 段不做本地过滤 —— 它的数据源本身就是"我 Star 过的"。
    public func matches(_ repository: Repository) -> Bool {
        switch self {
        case .all, .starred:
            true
        case .publicOnly:
            !repository.isPrivate
        case .privateOnly:
            repository.isPrivate
        }
    }

    /// 空态文案 —— **逐段不同**（2026-10-06 用户拍板）。
    ///
    /// 为什么不共用一句「这里还没有仓库」：Starred 段为空时说那句话，
    /// 会让人以为**自己的仓库没了** —— 空态在说错话，比没有空态更糟。
    public var emptyTitle: String {
        switch self {
        case .all: "还没有仓库"
        case .publicOnly: "还没有公开仓库"
        case .privateOnly: "还没有私有仓库"
        case .starred: "还没有 Star 过的仓库"
        }
    }
}

/// 仓库列表的数据来源。
public enum RepoListSource: Sendable, Hashable {
    /// `GET /user/repos` —— 「全部 / 公开 / 私有」三段共用。
    case repos
    /// `GET /user/starred` —— 「Starred」段独占。
    case starred
}
