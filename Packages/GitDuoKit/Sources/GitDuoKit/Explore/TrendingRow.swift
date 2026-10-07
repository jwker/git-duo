import Foundation

/// 榜单行上的一个角标（PRD §4.12「趋势卡片内容」、TECH_SPEC §9.10.2）。
///
/// ## 为什么要有 `role` 而不是直接给颜色
///
/// 原型里两个角标的**读法**不同：榜单指标是这张卡的"主角数字"
/// （`+812 本周` / `⚡ 30 分钟前推送`，原型写作 `color:var(--green);font-weight:650`），
/// 创建日只是辅助信息（`🆕 08-05 创建`，常规灰字）。
/// "哪个是主角"是**内容语义**（哪一段才是这张卡片想让人先看到的），不是色值 ——
/// 色值由视图按主题令牌决定。所以领域层只回答"它是什么角色"，不回答"它什么颜色"。
///
/// ## 为什么文案必须在这里生成、而不是在视图里拼
///
/// `+812 本周`、`🆕 08-05 创建`、`⚡ 30 分钟前推送` 三句都是**可见契约**：
/// harness 直接断言榜单行里出现「创建」（`harness:358`）与「推送」（`harness:355`）。
/// 拼装规则散进视图就没人守得住，而本项目已经吃过一次"文案散落 4–6 处"的亏。
public struct TrendingIndicator: Sendable, Hashable {

    /// 角标的两种角色。
    public enum Role: Sendable, Hashable {
        /// **榜单指标** —— 这张卡的主角数字（`+812 本周` / `⚡ 30 分钟前推送`）。
        case metric
        /// **辅助信息** —— 附带说明（`🆕 08-05 创建`）。
        case detail
    }

    public let text: String
    public let role: Role

    public init(_ text: String, role: Role) {
        self.text = text
        self.role = role
    }
}

/// 探索榜的一行（PRD §4.12 的趋势卡片 / TECH_SPEC §9.10.1–§9.10.2）。
///
/// ## 它比 `RepoSummary` 多了什么，为什么不多不少
///
/// 多的是**榜单指标的原料**（两个时刻 + 基线增量）与**已经算好的角标**。
/// 少的仍是可写性 —— 探索榜的数据源是 `GET /search/repositories`，
/// 它不返回 `permissions`（与 `RepoSummary` 同源的理由，决策 #43）。
///
/// `createdAt` / `pushedAt` 单独留着（而不是只留拼好的角标）是为了让视图在需要时
/// 能给出更完整的无障碍文案 —— 例如 `⚡ 30 分钟前推送` 读屏时补成
/// 「最近推送：30 分钟前」。角标字符串本身是给眼睛看的，未必适合直接念出来。
public struct TrendingRow: Sendable, Hashable, Identifiable {

    public let summary: RepoSummary

    /// **周增量**（来自本机基线快照，§9.10.2）；`nil` = 首次见到这个仓库，还没有基线。
    ///
    /// ⚠️ 它**不是**"总 Star × 系数"。没有基线时不显示增幅、也不显示破折号
    /// （决策 #36）—— 视图据此判断角标数组里有没有第一个元素。
    public let weeklyDelta: Int?

    /// 创建时刻（新星榜的 `🆕 MM-DD 创建`）。
    public let createdAt: Date

    /// 最近推送时刻（活跃榜的 `⚡ …推送`）。**可以是 `nil`**：刚创建、还没推过提交的仓库。
    public let pushedAt: Date?

    /// 角标，**顺序即渲染顺序**（榜单指标在前、辅助信息在后）。
    ///
    /// 绝大多数情况是 2 条（新星榜）或 1 条（活跃榜）。
    /// ⚠️ 活跃榜遇到 `pushedAt == nil` 时是**空数组** —— 那时整行只有语言与 Star，
    /// 而不是拿 `createdAt` 顶上（那会把"创建于"显示成"推送于"，见 `SearchRepositoryDTO`）。
    public let indicators: [TrendingIndicator]

    /// 去重与 `ForEach` 稳定性的键 —— 与 `RepoSummary.id` 同一口径（仓库全名）。
    public var id: String { summary.fullName }

    public var fullName: String { summary.fullName }
}

/// 把一页搜索结果拼成榜单行（TECH_SPEC §9.10.1–§9.10.2、决策 #36）。
///
/// ## 排序为什么不能由服务端一个 `sort=` 搞定
///
/// - **活跃榜**：`sort=updated` 把最活跃的那批先捞进来，但服务端按 `updated_at`
///   （**Issue / 评论也算更新**）排，而榜单语义是"最近推送"（`pushed_at`）⇒ 客户端重排。
/// - **新星榜**：服务端 `sort=stars` 是**总 Star**，而榜单语义是"近期新增"。
///   真实增幅一律来自本地基线（API 不给增速）⇒ 客户端按窗口增量重排，
///   **没有基线的那部分保持服务端原序**（那正是决策 #36 说的"回退按总 Star"）。
public enum TrendingRowBuilder {

    /// 榜单行的原料 —— `RepoSummary` 装不下、而榜单指标又必须要的那三项。
    ///
    /// 它**不是** DTO：DTO 是 `GitHubAPI` 的响应形状，本类型是"一个待成行的搜索命中"。
    /// 中间隔这一层的好处是 `TrendingRowBuilder` 的测试不必组装 `SearchRepositoryDTO`。
    public struct Source: Sendable, Hashable {

        public let summary: RepoSummary
        public let createdAt: Date
        public let pushedAt: Date?

        /// 来自本机基线的周增量；`nil` = 尚无基线。
        public let weeklyDelta: Int?

        public init(
            summary: RepoSummary,
            createdAt: Date,
            pushedAt: Date? = nil,
            weeklyDelta: Int? = nil
        ) {
            self.summary = summary
            self.createdAt = createdAt
            self.pushedAt = pushedAt
            self.weeklyDelta = weeklyDelta
        }
    }

    /// 拼出一屏榜单行（已排序）。
    ///
    /// - Parameter now: 显式传入，不内部取 `Date()` —— 否则"30 分钟前"会随渲染时刻漂移，
    ///   测试也就无从断言。这与 `ExploreQueryBuilder.query(…, now:)` 同一取向。
    public static func rows(
        board: TrendingBoard,
        filters: ExploreFilters,
        sources: [Source],
        now: Date
    ) -> [TrendingRow] {
        let ordered: [Source] = switch board {
        case .rising:
            // 复用 `StarGain.rank`：它已经把"有基线降序在前、无基线保原序在后"写在一处了。
            StarGain.rank(sources, delta: { $0.weeklyDelta }, range: filters.range)
        case .active:
            byRecentPush(sources)
        }

        return ordered.map { source in
            TrendingRow(
                summary: source.summary,
                weeklyDelta: source.weeklyDelta,
                createdAt: source.createdAt,
                pushedAt: source.pushedAt,
                indicators: indicators(
                    board: board,
                    filters: filters,
                    source: source,
                    now: now
                )
            )
        }
    }

    /// 一行该显示哪些角标。
    ///
    /// 逐字对齐原型的 `trendRows()`：
    /// ```js
    /// const metric = EXPLORE_BOARD==='rising'
    ///   ? `<span …>${gain}</span><span class="chip">🆕 ${t.created.slice(5)} 创建</span>`
    ///   : `<span …>⚡ ${t.upd}推送</span>`;
    /// ```
    public static func indicators(
        board: TrendingBoard,
        filters: ExploreFilters,
        source: Source,
        now: Date
    ) -> [TrendingIndicator] {
        switch board {
        case .rising:
            var result: [TrendingIndicator] = []
            // ⚠️ 顺序有讲究：**先补增幅、再补创建日**。没有基线时这里只有一条，
            //    而那一条是创建日 —— 视图不需要为"少了一条"写任何特例分支。
            //
            // ⚠️ `weekly > 0` 这道闸门是**必须的**，由 §9.10.2 的"不显示编出来的数字"推出：
            //    增幅 = 本次 stars − 上次快照。**首次拉取就把快照写成了当前值**
            //    （§9.10.2「首次见到某仓库时只记基线」）⇒ 30 秒后下拉刷新时差值为 0，
            //    而 `StarGain.windowDelta` 的下限是 1（那条下限是为"今天档把 +3 算成 0"准备的）
            //    ⇒ 一屏 30 个仓库会齐刷刷显示 `+1 本周`。那个 1 是凭空来的。
            //    所以"没有涨"与"还没基线"走**同一个出口**：不显示增幅。
            //    （降星同理：负增量也走这里，原型只印 `+`，印 `−3 本周` 是自造文案。）
            if let weekly = source.weeklyDelta, weekly > 0,
               let gain = StarGain.badge(weeklyDelta: weekly, range: filters.range) {
                result.append(TrendingIndicator(gain, role: .metric))
            }
            result.append(TrendingIndicator(
                TrendingMetric.createdLabel(createdAt: source.createdAt),
                role: .detail
            ))
            return result

        case .active:
            guard let pushedAt = source.pushedAt else { return [] }
            return [TrendingIndicator(
                TrendingMetric.lastPushLabel(pushedAt: pushedAt, now: now),
                role: .metric
            )]
        }
    }

    // MARK: - 内部

    /// 按最近推送降序，**稳定**（同刻按原下标裁决），没有推送时间的排最后。
    ///
    /// 带原下标是因为 Swift 的 `sorted(by:)` **不保证稳定** —— 靠下标裁决才能保证
    /// 同一份输入永远得到同一份输出，否则列表会在两次刷新之间无理由地抖动。
    private static func byRecentPush(_ sources: [Source]) -> [Source] {
        sources.enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.pushedAt, rhs.element.pushedAt) {
                case let (left?, right?):
                    left == right ? lhs.offset < rhs.offset : left > right
                case (nil, _?):
                    false
                case (_?, nil):
                    true
                case (nil, nil):
                    lhs.offset < rhs.offset
                }
            }
            .map { $0.element }
    }
}
