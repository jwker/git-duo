import SwiftUI
import GitDuoCore
import GitDuoDesign
import GitDuoKit

/// 首页「置顶仓库」的**一行**（PRD §4.1、原型 `scripts/04-search.js` 的 `.pin-card`）。
///
/// ## ⚠️ 2026-10-15 走查第 75 条：它**不再是卡片**（`PinCard` → `PinRow`）
///
/// 方案 D 把页面转成白底之后，全页只有这一组还留着「灰底 + 圆角 + 12 内边距」，
/// 而且与同一页的「最近访问」长得不像一家人 —— 用户原话「首页的置顶仓库板块有点难看」。
/// 处置：**改成与 `.recent-row` 同款的单列平铺行**（30pt owner 头像 + 全名 + 一行描述 + 右侧 Star）。
///
/// 网格时代的三个约束随之作废（都是"为了让两列卡片等高/塞得下"才有的）：
///
/// | 约束 | 网格时代 | 行式 |
/// |---|---|---|
/// | 描述缺失 | 补 `—`（不然两卡不等高） | **整行不画**（行式不需要等高） |
/// | 描述行数 | 固定两行（`height:32px`） | **一行截断**（半行宽里放两行 11.5pt 是拥挤的主因） |
/// | 指标 | 语言点 + Star + Fork + 私有胶囊 | **只留 Star**（那三样挤在半个屏幕宽里会糊成一团） |
///
/// ⚠️ **私有标记保留** —— 它不是"指标"，是这一行的身份（与 `RecentRow` 同一处置）。
/// 语言与 Fork 是真的不再显示，不是漏画；读屏标签里也一并去掉（念屏幕上看不到的东西更糟）。
///
/// ## 为什么它在本 Feature 里
///
/// 与切片 3 的 `RepoCard` 同一口径（决策 #43）：**认识领域模型的卡片不进 `GitDuoDesign`**。
/// 这里出现的 `owner/name` 拆分、`CompactNumber` 都是**业务语义**，不是视觉件。
struct PinRow: View {

    let summary: RepoSummary

    /// 首行不画分隔线（原型 `.pin-card+.pin-card::before` —— 相邻才画，第一条上面没有东西）。
    var showsSeparator: Bool = true

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            // ⚠️ 2026-10-15 起是 **owner 头像**（圆形，走查第 72 条）—— 从前这里是一个
            //    15pt 的文件夹图标（`PinCard` 的说法是"两列宽放不下图标块"，行式没有这个问题）。
            UserAvatar(
                login: summary.owner,
                avatarURL: summary.ownerAvatarURL,
                diameter: RepoAvatar.row.diameter
            )

            VStack(alignment: .leading, spacing: 2) {
                name
                if let description = summary.description, !description.isEmpty {
                    Text(description)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.Spacing.s)

            Label(CompactNumber.string(from: summary.starCount), systemImage: "star")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
                // Star 数不该被仓库名挤走 —— 挤掉之后这一行就看不出"置顶的这个有多热"。
                .layoutPriority(1)
        }
        // 方案 A（2026-10-15，走查第 76 条）：行回到**卡内** ⇒ 左右留白由行自己给 14
        //（原型 `.recent-row{padding:14px}` / `.pin-card{padding:14px}`）。
        .padding(14)
        .contentShape(Rectangle())
        .overlay(alignment: .topLeading) {
            if showsSeparator {
                Rectangle()
                    .fill(Theme.Palette.borderSoft)
                    .frame(height: 1)
                    // 内嵌缩进：从文字起点起，缩进 = **卡内边距 14** + 头像 30 + gap 12 = 56
                    //（原型 `.pin-card+.pin-card::before{left:55px}`，App 的 gap 是 12 ⇒ 56）。
                    .padding(.leading, 14 + RepoAvatar.row.diameter + Theme.Spacing.m)
            }
        }
        // 读屏：整行合成一句，而不是把四五个碎片逐个念出来。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - 名字

    private var name: some View {
        HStack(spacing: Theme.Spacing.xs) {
            // ⚠️ 用 `Text` **插值**而不是 `Text + Text`：后者自 iOS 26 起已废弃
            //    （编译器明说"改用 string interpolation"）。插值同样保留两段各自的样式。
            Text("\(ownerPart)\(namePart)")
                .font(Theme.Font.footnote.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            if summary.isPrivate == true {
                Text("私有")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .stroke(Theme.Palette.border, lineWidth: 1)
                    )
            }
        }
    }

    private var ownerPart: Text {
        Text("\(summary.owner)/").foregroundStyle(Theme.Palette.textTertiary)
    }

    private var namePart: Text {
        Text(summary.name).foregroundStyle(Theme.Palette.textPrimary)
    }

    private var accessibilityLabel: String {
        var parts = [summary.fullName]
        if summary.isPrivate == true { parts.append("私有仓库") }
        if let description = summary.description, !description.isEmpty { parts.append(description) }
        parts.append("\(summary.starCount) 个 Star")
        return parts.joined(separator: "，")
    }
}

#Preview {
    VStack(spacing: 0) {
        PinRow(
            summary: RepoSummary(
                fullName: "my-git/gitduo",
                description: "GitHub 客户端 · SwiftUI · 零第三方依赖",
                language: "Swift", starCount: 128, forkCount: 12, isPrivate: false
            ),
            // ⚠️ 分隔线画在**顶上** ⇒ 第一行不画（同 `MenuRow`，走查第 77 条）。
            showsSeparator: false
        )
        PinRow(
            summary: RepoSummary(
                fullName: "my-git/notes",
                description: nil,
                language: nil, starCount: 3, forkCount: 0, isPrivate: true
            )
        )
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
