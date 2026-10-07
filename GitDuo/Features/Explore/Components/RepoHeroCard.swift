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
struct RepoHeroCard: View {

    let detail: RepositoryDetail

    /// 相对时间现算用的"现在"。由调用方给，不在 `body` 里取 `Date()`
    /// —— 那样每次重绘都会拿到略微不同的值，测试也无从断言。
    let now: Date

    /// Star 的当前状态。`nil` = 基准还没确认（此时按未 Star 显示 —— 见 `StarState`）。
    let star: StarState?

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
                // `{更新时间} 更新 · {许可证} 许可证` —— 逐字对齐原型（`10-explore-repo.js:14`）。
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

    private var statRow: some View {
        HStack(spacing: Theme.Spacing.s) {
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
        .disabled(isTogglingStar)
        .overlay {
            if isTogglingStar {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityLabel(StarCopy.accessibilityLabel(isStarred: isStarred, starCount: count))
    }

    /// Watch —— **纯展示**。计数读 `subscribers_count`（`detail.watcherCount`），
    /// ⚠️ 不是 `watchers_count`（那是 Star 数的历史别名，读错会让两个按钮显示同一个数）。
    private var watchButton: some View {
        StatButton(
            systemImage: "eye",
            title: "Watch · \(GroupedNumber.string(from: detail.watcherCount))",
            action: {}
        )
        .allowsHitTesting(false)
        .accessibilityRemoveTraits(.isButton)
        .accessibilityHint(Self.watchHint)
    }

    /// Fork —— **纯展示**（见类型说明）。
    private var forkButton: some View {
        StatButton(
            systemImage: "arrow.triangle.branch",
            title: "Fork · \(GroupedNumber.string(from: detail.forkCount))",
            action: {}
        )
        .allowsHitTesting(false)
        .accessibilityRemoveTraits(.isButton)
        .accessibilityHint(Self.forkHint)
    }

    private var footer: some View {
        Text(Self.footerText)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity)
    }

    // MARK: - 文案（PRD §4.13 原文）

    static let footerText = "他人仓库 · 只读浏览，Fork 后可编辑与提交"

    /// ⚠️ 这两句**不是 PRD 原文** —— §4.13 只写了"纯展示"。它们是给读屏补的说明，
    /// 因为一个点不动的按钮如果不解释，用户只会反复点它。
    static let watchHint = "仅展示订阅计数，订阅动态依赖通知能力，本版本不做"
    static let forkHint = "Fork 功能待细化，本版本不可用"
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
                isTogglingStar: true,
                onToggleStar: {}
            )
        }
        .padding(Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
