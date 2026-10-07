import SwiftUI
import GitDuoCore
import GitDuoDesign
import GitDuoKit

/// 探索榜的一行趋势卡片（PRD §4.12「趋势卡片内容」、原型 `scripts/09-explore.js` 的 `trendRows()`）。
///
/// ## 卡片内容（三处并列，缺一不可）
///
/// 仓库图标 · **全名（链接色）** · 描述 · 主语言 + Star 总数 + **榜单指标**。
///
/// ## ⚠️ 名字用链接色，与首页置顶卡 / 仓库列表卡**有意不同**
///
/// 原型里只有趋势卡片的仓库名是 `style="color:var(--link)"`（其余几处是正文色）。
/// 这不是随意取的：这一屏是**浏览 / 发现**语境，名字是这一行唯一可点进去的东西；
/// 首页与仓库列表是**自己的收藏**语境，名字已经很熟悉，不需要再被强调。
///
/// ## 指标角标为什么由调用方给
///
/// `+812 本周`、`🆕 08-05 创建`、`⚡ 30 分钟前推送` 三句都是**可见契约**
/// （harness 直接断言榜单行里出现「创建」与「推送」），它们的生成规则在领域层
/// （`StarGain` / `TrendingMetric`），**不在视图里** —— 视图只负责把拿到的两段文案摆上去。
///
/// ## 尚未取到基线时只有一段文案
///
/// 新星榜在**首次运行**、还没有 Star 基线时**不显示增幅**（决策 #36）⇒ 调用方只传
/// 创建日那一个角标。所以这里是数组而不是"一定有两条"。
struct TrendCard: View {

    /// 角标的两种语态。
    enum BadgeTone: Sendable, Hashable {
        /// 榜单指标（`+812 本周` / `⚡ 30 分钟前推送`）—— 绿色加粗，是这张卡的**主角数字**。
        case metric
        /// 辅助信息（`🆕 08-05 创建`）—— 常规灰字。
        case plain
    }

    struct Badge: Sendable, Hashable {
        let text: String
        let tone: BadgeTone

        init(_ text: String, tone: BadgeTone = .plain) {
            self.text = text
            self.tone = tone
        }
    }

    let summary: RepoSummary
    let badges: [Badge]

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            RepoAvatar.standard

            VStack(alignment: .leading, spacing: 2) {
                name
                if let description = summary.description, !description.isEmpty {
                    Text(description)
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                chips
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous)
                .stroke(Theme.Palette.borderSoft, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var name: some View {
        Text(summary.fullName)
            .font(Theme.Font.bodyStrong)
            .foregroundStyle(Theme.Palette.accent)
            .lineLimit(1)
            .truncationMode(.middle)   // 仓库名尾部更有辨识度，别从尾截
    }

    private var chips: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let language = summary.language {
                HStack(spacing: Theme.Spacing.xs) {
                    Circle()
                        .fill(LanguageColor.color(for: language))
                        .frame(width: 8, height: 8)
                    Text(language)
                }
            }

            Label(CompactNumber.string(from: summary.starCount), systemImage: "star")

            ForEach(badges.indices, id: \.self) { index in
                let badge = badges[index]
                Text(badge.text)
                    // `metric` 用 `accentStrong`：原型这处写的是 `color:var(--green)`，
                    // 而 `--green` 同时是主按钮的底色 —— 两处本就同一个值，别新造一个 token。
                    .font(badge.tone == .metric
                          ? Theme.Font.caption.weight(.semibold)
                          : Theme.Font.caption)
                    .foregroundStyle(badge.tone == .metric
                                     ? Theme.Palette.accentStrong
                                     : Theme.Palette.textSecondary)
            }
        }
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.Palette.textSecondary)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .padding(.top, 7)
    }

    private var accessibilityLabel: String {
        var parts = [summary.fullName]
        if let description = summary.description, !description.isEmpty { parts.append(description) }
        if let language = summary.language { parts.append("主语言 \(language)") }
        parts.append("\(summary.starCount) 个 Star")
        parts.append(contentsOf: badges.map(\.text))
        return parts.joined(separator: "，")
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.s) {
        TrendCard(
            summary: RepoSummary(
                fullName: "misoge/paneltkit",
                description: "SwiftUI 自适应布局工具库 · Swift",
                language: "Swift", starCount: 2_341
            ),
            badges: [.init("+812 本周", tone: .metric), .init("🆕 08-05 创建")]
        )
        TrendCard(
            summary: RepoSummary(
                fullName: "zed-flow/agent-kit",
                description: "终端 AI 编程助手工具链",
                language: "Go", starCount: 6_720
            ),
            badges: [.init("⚡ 1 小时前推送", tone: .metric)]
        )
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
