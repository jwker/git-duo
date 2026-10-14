import SwiftUI
import GitDuoCore
import GitDuoDesign
import GitDuoKit

/// 他人仓库详情的头部大卡（PRD §4.13 第 1 条、原型 `scripts/10-explore-repo.js` 的 `.repo-hero`）。
///
/// 内容：仓库图标 · 全名 · `{更新时间} 更新 · {许可证} 许可证` · 描述 · 话题标签（链接色）·
/// 三个统计按钮（Star / Watch / Fork）· 底部说明。
///
/// ## ⚠️ Watch 与 Fork 是**纯展示**的（2026-10-06 拍板）
///
/// - **Watch**：PRD §4.13 只规定"展示订阅计数"（订阅动态依赖通知能力，本期不做）。
/// - **Fork**：PRD 仍标 ⏳「行为待细化」。Fork 是**会改变账号状态的写操作**，
///   在它的落地方案（真调还是跳网页端）定下来之前**不做半截**。
///
/// 所以两个按钮照原型画出来（含计数），但用 `allowsHitTesting(false)` 去掉点击 ——
/// **不是**用 `.disabled`：那会把它们变灰，看起来像"暂时不可用"，
/// 而这一屏本来就只呈现"有多少人在订阅 / 有多少个 Fork"这两个数。
/// 读屏用 hint 说明原因（否则用户只会听到一个点不动的按钮）。
///
/// ## Star 按钮的文案与图标由谁给
///
/// 文案走 `StarCopy.buttonTitle`（领域层，千分位全量 `2,341` —— 与卡片上的 `2.3k` 有意不同），
/// 图标由这里显式给出 `star` / `star.fill`
/// （⚠️ SF Symbols 里**不是每个符号都有 `.fill` 变体**，靠追加推导会静默拿到不存在的名字）。
///
/// ## 🔴 Star 按钮的**第二档**：确定写不了 ⇒ 置灰 + 一行说明（决策 #80）
///
/// 2026-10-09 起（走查 #3 定案，`TECH_SPEC §3.5.5`）：GitHub App 的用户令牌**只能 Star
/// 安装范围内（在册账号名下）的仓库**，别人的仓库一律 403。
///
/// ⚠️ **本页是这条限制影响最大的屏**：这里出现的每一条都是**别人的仓库**
/// （趋势榜 / 搜索点进来的 / 别人的 Star），也就是**几乎每一条都写不了**。
/// 这不是异常分支，它就是这一页的常态。
///
/// 形态与 §4.4 的 `RepoDetailHero` 一致（`.disabled(true)` + 下方一行 `StarCopy.unavailableHint`），
/// 唯一的差别是**这一张卡下面有页脚**：
///
/// ```
/// statRow
/// unavailableHint   ← 新增的这一行排在这里
/// footer            ← 「他人仓库 · 只读浏览，Fork 后可编辑与提交」，PRD §4.13 逐字，一个字都不能动
/// ```
///
/// ⚠️ 所以是**加一行**、不是改页脚那一句 —— 它与页脚的语义不冲突（页脚说"能做什么"，
/// 这一行说"这一次为什么不能"）。
struct RepoHeroCard: View {

    let detail: RepositoryDetail

    /// 相对时间现算用的"现在"。由调用方给，不在 `body` 里取 `Date()`
    /// —— 那样每次重绘都会拿到略微不同的值，测试也无从断言。
    let now: Date

    /// Star 的当前状态。`nil` = 基准还没确认（此时按未 Star 显示 —— 见 `StarState`）。
    let star: StarState?

    /// Star 现在**写不写得动**（决策 #80 / `TECH_SPEC §3.5.5`）。
    ///
    /// ⚠️ `false` 只有一个含义：**已经确定**写不了（查到了安装范围、而本仓库不在其中）。
    /// "还没查到 / 拉取失败"一律是 `true` —— `StarWriteScope` 的口径是**不确定就不拦**：
    /// 误灰一个本来能点的按钮，比漏灰一个不能点的更糟（同 §8.5「还没加载出来 ≠ 确实没有」）。
    let canStar: Bool

    /// Star 请求在途（按钮内联 loading + 禁用，§8.5）。
    let isTogglingStar: Bool

    let onToggleStar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            description
            topics
            statRow
                .padding(.top, Theme.Spacing.m)
            unavailableHint
            footer
                .padding(.top, Theme.Spacing.s)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .stroke(Theme.Palette.borderSoft, lineWidth: 1)
        )
    }

    // MARK: - 组成

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            RepoAvatar.standard
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.fullName)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                // `{更新时间} 更新 · {许可证} 许可证` —— 逐字对齐原型（`10-explore-repo.js:13`）。
                Text(detail.metaLabel(now: now))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var description: some View {
        if let description = detail.description, !description.isEmpty {
            Text(description)
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.leading)
                .padding(.top, 6)
        }
    }

    /// 话题标签。原型用 `.chip` + 链接色（没有边框、没有底色）——
    /// 理由说得通：标签是**可搜的入口**，而这一屏的链接色已经被用来表示"点得动"。
    @ViewBuilder
    private var topics: some View {
        if !detail.topics.isEmpty {
            // 换行排列：标签个数不定（0–20 个），一行放不下必须能折下去。
            FlowLayout(spacing: Theme.Spacing.s) {
                ForEach(detail.topics, id: \.self) { topic in
                    Text(topic)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
            .padding(.top, Theme.Spacing.s)
        }
    }

    /// 三颗统计按钮。
    ///
    /// ⚠️ 用 `FlowLayout`（**不是** `HStack`）：三颗的宽度随内容（2026-10-11 由
    /// "竖排 · 三等分整宽"改，见 `StatButton`），长数字或 Dynamic Type 放大时
    /// 应当**折行**；`HStack` 放不下只会把它们压扁，把那串数字截掉。
    private var statRow: some View {
        FlowLayout(spacing: Theme.Spacing.s) {
            starButton
            watchButton
            forkButton
        }
    }

    private var starButton: some View {
        // 基准未确认时按"未 Star"显示（`StarState` 的降级），计数用详情里的那个数。
        let isStarred = star?.isStarred ?? false
        let count = star?.starCount ?? detail.starCount

        return StatButton(
            systemImage: "star",
            activeSystemImage: "star.fill",
            title: StarCopy.buttonTitle(isStarred: isStarred, starCount: count),
            isActive: isStarred,
            activeTint: Theme.Palette.starActive,
            action: onToggleStar
        )
        // ⚠️ §8.5「操作类」：在途时**禁用**（防重复提交）并给内联 loading。
        //    与下面那一档共用同一个修饰符 —— 两者都表现为"灰"，但原因完全不同：
        //    在途是**等一会儿就好**，不可写是**换个人来点也不行**。
        .disabled(isTogglingStar || !canStar)
        .overlay {
            if isTogglingStar {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityLabel(StarCopy.accessibilityLabel(isStarred: isStarred, starCount: count))
        // ⚠️ 灰掉那一档把**原因**交给读屏（否则只听到一个"变暗的按钮"，
        //    而下面那行说明是另一个元素、要再滑一下才听到）。
        .accessibilityHint(canStar ? "" : StarCopy.unavailableHint)
    }

    /// 「写不了」时按钮下方那一行（决策 #80）。
    ///
    /// ⚠️ 它**排在 `statRow` 与 `footer` 之间** —— 页脚那句是 PRD §4.13 逐字给的原型文案，
    /// 一个字都不能动，所以这里只**加一行**。
    ///
    /// ⚠️ 文案就是 `StarCopy.unavailableHint`（与失败提示同一句，有意如此 ——
    /// 用户在两处读到同一个原因，才会接受"这不是偶发故障"）。
    @ViewBuilder
    private var unavailableHint: some View {
        if !canStar {
            Text(StarCopy.unavailableHint)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Theme.Spacing.s)
        }
    }

    /// Watch —— **纯展示**。计数读 `subscribers_count`（`detail.watcherCount`），
    /// ⚠️ 不是 `watchers_count`（那是 Star 数的历史别名，读错会让两个按钮显示同一个数）。
    private var watchButton: some View {
        StatButton(
            systemImage: "eye",
            title: RepoCopy.watchLabel(count: detail.watcherCount),
            action: {}
        )
        .allowsHitTesting(false)
        .accessibilityRemoveTraits(.isButton)
        .accessibilityHint(RepoCopy.watchUnavailableHint)
    }

    /// Fork —— **纯展示**（见类型说明）。
    private var forkButton: some View {
        StatButton(
            // ⚠️ 走 `ForkIcon()` 而不是 SF Symbol：SF Symbols 里没有「实线 fork」这个字形，
            // 用户报回相差太多，所以设计包里自绘了 `ForkIcon`，与 `RepoDetailHero` 统一用。
            icon: ForkIcon().frame(width: 12, height: 12),
            title: RepoCopy.forkLabel(count: detail.forkCount),
            action: {}
        )
        .allowsHitTesting(false)
        .accessibilityRemoveTraits(.isButton)
        .accessibilityHint(RepoCopy.forkUnavailableHint)
    }

    private var footer: some View {
        Text(Self.footerText)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity)
    }

    // MARK: - 文案（PRD §4.13 原文）

    static let footerText = "他人仓库 · 只读浏览，Fork 后可编辑与提交"

    // ⚠️ Watch / Fork 的按钮标题与读屏提示**已收拢到领域层** `RepoCopy`
    //    （`watchLabel(count:)` / `forkLabel(count:)` / `watchUnavailableHint` / `forkUnavailableHint`）：
    //    §4.4 的头部是同一个控件、同一个数、同一句话，两处各写一份迟早分叉
    //    —— 分叉的症状是同一个仓库在两页上显示成两个数，而两页单看都对。
}

#Preview {
    ScrollView {
        VStack(spacing: Theme.Spacing.l) {
            RepoHeroCard(
                detail: RepositoryDetail(
                    fullName: "kuda/ui-craft",
                    description: "面向 iOS 的组件库 · 设计令牌 / 无障碍 / 深色模式",
                    topics: ["swiftui", "design-tokens", "ios", "accessibility", "components"],
                    licenseLabel: "MIT",
                    defaultBranch: "main",
                    starCount: 11_240,
                    forkCount: 412,
                    watcherCount: 88,
                    pushedAt: Date().addingTimeInterval(-1_800),
                    permissions: .none
                ),
                now: Date(),
                star: StarState(
                    fullName: "kuda/ui-craft", isStarred: true, starCount: 11_241, baselineConfirmed: true
                ),
                // ⚠️ 置灰那一档**才是本页的常态**（这里装的都是别人的仓库）——
                //    所以拿它当第一张预览图，而不是拿"能点"的那一档。
                canStar: false,
                isTogglingStar: false,
                onToggleStar: {}
            )
            RepoHeroCard(
                detail: RepositoryDetail(
                    fullName: "misoge/paneltkit",
                    description: nil,
                    topics: [],
                    licenseLabel: "未指定",
                    defaultBranch: "main",
                    starCount: 2_341,
                    forkCount: 0,
                    watcherCount: 0,
                    pushedAt: nil,
                    permissions: .none
                ),
                now: Date(),
                star: nil,
                // 对照组：可写 ⇒ 按钮正常、**且没有那一行说明**（走查单 #152 的判据）。
                canStar: true,
                isTogglingStar: true,
                onToggleStar: {}
            )
        }
        .padding(Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
