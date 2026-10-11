import SwiftUI
import GitDuoCore
import GitDuoDesign
import GitDuoKit

/// 首页「置顶仓库」的网格卡片（PRD §4.1「卡片内容」、原型 `scripts/04-search.js` 的 `.pin-card`）。
///
/// ## 为什么它在本 Feature 里
///
/// 与切片 3 的 `RepoCard` 同一口径（决策 #43）：**认识领域模型的卡片不进 `GitDuoDesign`**。
/// 设计包里放的是"与业务无关的视觉件"（令牌 / 骨架块 / 仓库图标 / 统计按钮 / 占比条）。
/// 这里出现的 `owner/name` 拆分、私有标记都是**业务语义**，不是视觉件。
///
/// ## 与 `RepoCard`（仓库列表）的三处有意不同
///
/// | | 置顶卡（本类型） | 仓库列表卡 |
/// |---|---|---|
/// | 布局 | **2 列网格**，卡片更矮 | 单列，整行 |
/// | 描述 | **占位 `—`**、固定两行高 | 无描述时整块不渲染 |
/// | 名字 | `owner` 弱化（不换行截断） | 整串加粗 |
///
/// 描述用 `—` 而不是省略：置顶是并排的两列，一张有描述一张没有会让**两卡不等高**，
/// 网格看起来像坏了。原型同样写的是 `r.d || '—'`。
struct PinCard: View {

    let summary: RepoSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            name
            description
            metrics
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .stroke(Theme.Palette.borderSoft, lineWidth: 1)
        )
        // 读屏：整卡合成一句"这是什么、有什么"，而不是把四五个碎片逐个念出来。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - 名字

    private var name: some View {
        HStack(spacing: Theme.Spacing.xs) {
            // 原型用的是 15px 的仓库字形（`.pin-ic`），不是那个 34pt 的深色图标块 ——
            // 置顶卡只有两列宽，放不下图标块。
            Image(systemName: "folder.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.textTertiary)

            // owner 弱化 + 名字加粗，两段拼在一行里；整行截尾。
            //
            // ⚠️ 用 `Text` **插值**而不是 `Text + Text`：后者自 iOS 26 起已废弃
            //    （编译器明说"改用 string interpolation"）。插值同样保留两段各自的样式，
            //    所以视觉不变 —— 在 iOS 27 上继续用废弃 API 只是把债往后挪。
            Text("\(ownerPart)\(namePart)")
                .font(Theme.Font.footnote.weight(.bold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var ownerPart: Text {
        Text("\(summary.owner)/").foregroundStyle(Theme.Palette.textTertiary)
    }

    private var namePart: Text {
        Text(summary.name).foregroundStyle(Theme.Palette.textPrimary)
    }

    // MARK: - 描述

    private var description: some View {
        Text(summary.description ?? "—")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
            .multilineTextAlignment(.leading)
            // `reservesSpace` 而不是写死 `height: 32`：两行高度随 Dynamic Type 一起长，
            // 而写死高度在大字号下会把第二行裁掉（原型是 px 布局，没这个问题）。
            .lineLimit(2, reservesSpace: true)
            .padding(.top, 7)
    }

    // MARK: - 指标

    private var metrics: some View {
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

            // Fork 与私有标记都只在**数据源真的给了**的时候才画。
            // `nil` 表示"这个接口不返回这个字段"（决策 #43），不是"值是 0 / false"。
            if let forkCount = summary.forkCount {
                Label {
                    // SF Symbols 里没有「实线 fork」字形，改用设计包自绘的 `ForkIcon`。
                    Text(CompactNumber.string(from: forkCount))
                } icon: {
                    ForkIcon().frame(width: 11, height: 11)
                }
            }
            if summary.isPrivate == true {
                Text("私有")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .stroke(Theme.Palette.border, lineWidth: 1)
                    )
            }
        }
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.Palette.textTertiary)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .padding(.top, Theme.Spacing.s)
    }

    private var accessibilityLabel: String {
        var parts = [summary.fullName]
        if summary.isPrivate == true { parts.append("私有仓库") }
        if let description = summary.description, !description.isEmpty { parts.append(description) }
        if let language = summary.language { parts.append("主语言 \(language)") }
        parts.append("\(summary.starCount) 个 Star")
        if let forkCount = summary.forkCount { parts.append("\(forkCount) 个 Fork") }
        return parts.joined(separator: "，")
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
        PinCard(summary: RepoSummary(
            fullName: "my-git/gitduo",
            description: "GitHub 客户端 · SwiftUI · 零第三方依赖",
            language: "Swift", starCount: 128, forkCount: 12, isPrivate: false
        ))
        PinCard(summary: RepoSummary(
            fullName: "my-git/notes",
            description: nil,
            language: nil, starCount: 3, forkCount: 0, isPrivate: true
        ))
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
