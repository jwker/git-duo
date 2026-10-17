import SwiftUI
import GitDuoCore
import GitDuoDesign
import GitDuoKit

/// 首页「置顶仓库」的**一行**（PRD §4.1、原型 `scripts/04-search.js` 的 `.pin-card`）。
///
/// ## ⚠️ 2026-10-16 起它是 **`List` 的一行**（NATIVE-MIGRATION P3）
///
/// 此前它自己画「内边距 14 + 顶上一条内嵌 hairline（首行不画）」，外面再套
/// `CardBox` 与页面左右留白 —— 那三样加起来是"**用自绘件模拟系统列表行**"。
/// 现在它只负责**内容**：内边距 / 卡片底 / 行间分隔线 / 整行点击范围
/// 全部由 `List` 的行机制给出（`.listRowBackground` / 系统分隔线 / `NavigationLink`）。
///
/// ⇒ 两样东西随之删除：
/// - `showsSeparator`：系统知道"谁是首行、谁是末行"，调用方不必再数 index
///   （这正是走查第 76 / 77 条那两套"顶线 / 底线"口径要解决的问题 —— 现在问题本身不存在了）。
/// - `.padding(14)`：行内边距交给 `.listRowInsets`（默认值即系统标准）。
///
/// ## 它长什么样（内容部分没变）
///
/// 30pt owner 头像 + 全名 + 一行描述 + 右侧 Star。
///
/// ## ⚠️ 2026-10-15 走查第 75 条：它**不再是卡片**（`PinCard` → `PinRow`）
///
/// 网格时代的三个约束随之作废（都是"为了让两列卡片等高/塞得下"才有的）：
///
/// | 约束 | 网格时代 | 行式 |
/// |---|---|---|
/// | 描述缺失 | 补 `—`（不然两卡不等高） | **整行不画**（行式不需要等高） |
/// | 描述行数 | 固定两行（`height:32px`） | **一行截断** |
/// | 指标 | 语言点 + Star + Fork + 私有胶囊 | **只留 Star** |
///
/// ⚠️ **私有标记保留** —— 它不是"指标"，是这一行的身份（与 `RecentRow` 同一处置）。
///
/// ## 为什么它在本 Feature 里
///
/// 与切片 3 的 `RepoCard` 同一口径（决策 #43）：**认识领域模型的卡片不进 `GitDuoDesign`**。
/// 这里出现的 `owner/name` 拆分、`CompactNumber` 都是**业务语义**，不是视觉件。
struct PinRow: View {

    let summary: RepoSummary

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
        // ⚠️ 让整行矩形（含 `Spacer` 占的空白）都成为命中区，
        //    否则 `Button` 只认子视图几何并集，行内右侧空白点不动。
        .contentShape(Rectangle())
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
    // 它现在是 `List` 的一行 ⇒ 预览也按 `List` 摆（否则看不到真实的行内边距与分隔线）。
    List {
        PinRow(
            summary: RepoSummary(
                fullName: "my-git/gitduo",
                description: "GitHub 客户端 · SwiftUI · 零第三方依赖",
                language: "Swift", starCount: 128, forkCount: 12, isPrivate: false
            )
        )
        PinRow(
            summary: RepoSummary(
                fullName: "my-git/notes",
                description: nil,
                language: nil, starCount: 3, forkCount: 0, isPrivate: true
            )
        )
    }
}
