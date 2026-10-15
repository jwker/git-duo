import SwiftUI
import GitDuoCore
import GitDuoDesign
import GitDuoKit

/// 仓库卡片 —— 仓库列表的一行（PRD §4.3「卡片内容」）。
///
/// ## 为什么它在本 Feature 里，而不是进 `GitDuoDesign`
///
/// 因为它**认识领域模型**（`Repository`）。设计包里放的是"与业务无关的视觉件"
/// （令牌、骨架块、玻璃封装），一旦把 `Repository` 传进去，设计包就得反向依赖领域包 ——
/// 依赖方向立刻变成环。所以业务卡片留在 Feature，样式仍然全部引用 `Theme` 令牌。
///
/// ## 卡片内容（原型 `scripts/05-repo.js` 的 `.card`）
///
/// 仓库图标 · 全名（私有加「私有」标记）· 描述 · 主语言色点 + 语言名 · Star · Fork。
struct RepoCard: View {

    let repository: Repository

    /// 顶上一条内嵌 hairline（方案 D 的 `.card+.card{border-top:…}`）——
    /// 列表里**第一行传 `false`**。与 `StarRow.showsTopSeparator` 同一条处置。
    var showsTopSeparator: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            icon
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                title
                if let description = repository.description, !description.isEmpty {
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
        // 方案 D（2026-10-15，走查第 73 条）：`.card` 去形 —— 条目直接坐在页面上，
        // 行间靠顶上那条内嵌 hairline 分隔（原型 `padding:13px 2px`）。
        .padding(.vertical, 13)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if showsTopSeparator {
                Rectangle()
                    .fill(Theme.Palette.borderSoft)
                    .frame(height: 1)
            }
        }
        // 无障碍：读屏读的是"这是什么、有什么"，而不是把六个碎片逐个念一遍
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - 组成

    /// 仓库行的头像块。
    ///
    /// ⚠️ 2026-10-06 改回原型：此前这里是浅底 `surfaceSunken` + 灰色 `book.closed`
    /// （36×36 r6），而原型 `scripts/05-repo.js:15` 走的是 `.repo-avatar`
    /// —— **深底 `#24292f` + 白色文件夹字形**，34×34 圆角 9。
    /// 4.3 新做的 `RepoAvatar` 已按原型实现，于是同一 App 里曾出现两种仓库图标；
    /// 用户拍板「两处都改回原型」⇒ 这里复用 `RepoAvatar.standard`。
    ///
    /// ⚠️⚠️ **2026-10-15 再改（走查第 72 条，用户裁定）**：换成了 **owner 头像**
    /// （圆形、首字母兜底，与全 App 的头像语言统一）—— 原型的文件夹图标让位。
    /// 尺寸仍是 34（`RepoAvatar.standard.diameter`），骨架几何不动。
    private var icon: some View {
        UserAvatar(
            login: repository.owner,
            avatarURL: repository.ownerAvatarURL,
            diameter: RepoAvatar.standard.diameter
        )
    }

    private var title: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(repository.fullName)
                .font(Theme.Font.bodyStrong)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)   // 仓库名尾部更有辨识度，别从尾截

            if repository.isPrivate {
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

    private var chips: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let language = repository.language {
                HStack(spacing: Theme.Spacing.xs) {
                    Circle()
                        .fill(LanguageColor.color(for: language))
                        .frame(width: 8, height: 8)
                    Text(language)
                }
            }
            Label(CompactNumber.string(from: repository.starCount), systemImage: "star")
            Label {
                Text(CompactNumber.string(from: repository.forkCount))
            } icon: {
                // SF Symbols 里没有「实线 fork」字形，改用设计包自绘的 `ForkIcon`。
                ForkIcon().frame(width: 11, height: 11)
            }
        }
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.Palette.textSecondary)
        .labelStyle(.titleAndIcon)
        .padding(.top, 2)
    }

    private var accessibilityLabel: String {
        var parts = [repository.fullName]
        if repository.isPrivate { parts.append("私有仓库") }
        if let description = repository.description, !description.isEmpty { parts.append(description) }
        if let language = repository.language { parts.append("主语言 \(language)") }
        parts.append("\(repository.starCount) 个 Star")
        parts.append("\(repository.forkCount) 个 Fork")
        return parts.joined(separator: "，")
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.s) {
        RepoCard(repository: Repository(
            owner: "my-git", name: "gitduo",
            description: "GitHub 客户端 · SwiftUI · 零第三方依赖",
            isPrivate: false, language: "Swift",
            starCount: 128, forkCount: 12,
            permissions: Permissions(push: true)
        ))
        RepoCard(repository: Repository(
            owner: "rust-lang", name: "rust",
            description: "Empowering everyone to build reliable software",
            isPrivate: true, language: nil,
            starCount: 98_200, forkCount: 12_600,
            permissions: .none
        ))
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
