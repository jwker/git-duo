import SwiftUI

/// 「我的」页头部那一排统计项 —— `42 仓库` / `318 Star` / `126 Follower`
/// （PRD §4.17 第 2 条、决策 #76）。
///
/// ```css
/// .pstats{display:flex;justify-content:center;gap:26px;margin:14px 0 6px}
/// .pstat{text-align:center;cursor:pointer}
/// .pstat b{display:block;font-size:17px;font-weight:750}
/// .pstat span{font-size:11.5px;color:var(--text2)}
/// ```
///
/// ## ⚠️ 它与 `StatButton` **不是同一件**，也不能合并
///
/// | | `StatButton`（§4.13 仓库头部） | 本件（§4.17 我的页头部） |
/// |---|---|---|
/// | 形态 | **图标与文字同一行** | **数字在上**、标签在下，无图标 |
/// | 容器 | 每个一枚灰底圆角框（`.stat-btn{background:var(--chip);border:1px}`);
///   宽度**随内容**、左对齐（2026-10-11 由"竖排 · 三等分整宽"改，见 `StatButton`）
///   | **没有框**，只有一行文字；三个紧凑居中（`gap:26px`） |
/// | 文案 | `Star · 2,341`（图标 + 名词 + 数字**一行**） | 数字与标签**上下两行** |
///
/// 四处都不同 ⇒ 合成一件要靠一堆开关，而开关漏了**不会报错**，
/// 只会让其中一处看起来"还是那个组件、只是淡了一点"
/// （同 `SheetRow` 与 `LinkRow`、`CardBox` 与 `MenuCard` 的那两条判例）。
///
/// ## 它只收基础类型（判据 #43）
///
/// 收的是 `(valueText, title, action)` 三件基础类型，**不认识** `ProfileStatItem` /
/// `ProfileStatKind`。所以"哪一项叫什么、数字怎么格式化（千分位、不缩写）、
/// 缺的那项跳不跳过"全在领域层（`ProfileStats.items` 已经把顺序与取舍定好了），
/// 这里只负责画。
///
/// ## ⚠️ 有的项可点、有的不可点
///
/// 原型只有 `Star` 那一项挂了 `onclick`（→ 我的 Star 页），另两项是纯展示
/// —— 所以 `action` 是 **Optional**，`nil` = 不可点（不画按压反馈、读屏不加按钮角色）。
/// 沿决策 **#51** 的处置：**不能**用 `.disabled`（那会让它变灰、像"暂时不可用"），
/// 而是根本不做成按钮。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct ProfileStatBar: View {

    /// 一项统计。
    public struct Item {

        /// 屏幕上那个数字（`318`）。**由调用方算好**（千分位、不缩写 —— 见 `ProfileStatItem.valueText`）。
        public let valueText: String

        /// 数字下面那个标签（`仓库` / `Star` / `Follower`）。
        public let title: String

        /// 点它去哪。`nil` = 这一项不可点（纯展示）。
        public let action: (() -> Void)?

        public init(valueText: String, title: String, action: (() -> Void)? = nil) {
            self.valueText = valueText
            self.title = title
            self.action = action
        }
    }

    /// 原型 `.pstats{gap:26px}`（26 不在 4pt 阶里 ⇒ 写原值）。
    static let spacing: CGFloat = 26

    /// 上边距（原型 `.pstats{margin:14px 0 6px}` 的前半；14 不在 4pt 阶里 ⇒ 写原值）。
    static let topPadding: CGFloat = 14

    /// 下边距（同上，后半）。
    static let bottomPadding: CGFloat = 6

    public let stats: [Item]

    public init(stats: [Item]) {
        self.stats = stats
    }

    public var body: some View {
        // 一项都没有 ⇒ **整行不画**（不是画一行空的）。
        //
        // 这个分支在真实数据上到得了：`GET /user` 与 GraphQL 两路同时失败时
        // `ProfileStats.isEmpty` 为真（见 `ProfileStats` 抬头那张表）。
        // 若这里照画，屏幕上会出现一条 20pt 高的**空白**——看着像加载卡住了。
        if stats.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: Self.spacing) {
                ForEach(stats.indices, id: \.self) { index in
                    cell(stats[index])
                }
            }
            // 三个紧凑居中（原型 `justify-content:center`）——
            // ⚠️ 别改成"每项 `maxWidth: .infinity` 均分"：那会在只有两项时
            // 把它们推到屏幕两端，与原型"三项居中"的样子完全不同。
            .frame(maxWidth: .infinity)
            .padding(.top, Self.topPadding)
            .padding(.bottom, Self.bottomPadding)
        }
    }

    @ViewBuilder
    private func cell(_ item: Item) -> some View {
        if let action = item.action {
            Button(action: action) { label(item) }
                .buttonStyle(.plain)
        } else {
            label(item)
        }
    }

    private func label(_ item: Item) -> some View {
        VStack(spacing: 0) {
            // 原型 `.pstat b{font-size:17px;font-weight:750}` ⇒ `headline`（`.headline` 17 semibold）。
            Text(item.valueText)
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                // 窄屏上 `1,234,567` 这种七位数可能顶到相邻项 —— 缩小而不是截断
                //（截断会把数字吃掉，而那正是这一项要读的东西；同 `StatButton`）。
                .minimumScaleFactor(0.8)

            // 原型 `.pstat span{font-size:11.5px;color:var(--text2)}` ⇒ `caption`（11）。
            Text(item.title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
        }
        // 可点的那一项，点击热区要盖住整块（否则只有数字与标签那两小块响应）。
        .contentShape(Rectangle())
        // 读屏念成一句："Star，318"（数字在上、标签在下，而听的时候顺序反过来更好懂）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title)，\(item.valueText)")
        .accessibilityAddTraits(item.action == nil ? [] : [.isButton])
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.xl) {
        // 三项齐全：只有 Star 那一项可点（原型就是这样）
        ProfileStatBar(stats: [
            .init(valueText: "42", title: "仓库"),
            .init(valueText: "318", title: "Star", action: {}),
            .init(valueText: "126", title: "Follower"),
        ])

        // 缺 Follower（`GET /user` 那一路失败）：剩下两项**居中**，不填 0 也不留空位
        ProfileStatBar(stats: [
            .init(valueText: "42", title: "仓库"),
            .init(valueText: "318", title: "Star", action: {}),
        ])

        // 只剩一项（GraphQL 那一路失败）
        ProfileStatBar(stats: [.init(valueText: "126", title: "Follower")])

        // 大同位数：不缩写、也不截断
        ProfileStatBar(stats: [
            .init(valueText: "1,024", title: "仓库"),
            .init(valueText: "12,345", title: "Star", action: {}),
            .init(valueText: "1,234,567", title: "Follower"),
        ])

        // 一项都没有（两路都失败）⇒ 什么都不画
        ProfileStatBar(stats: [])
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
