import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 首页「最近访问」的一行（PRD §4.1、原型 `scripts/04-search.js` 的 `.recent-row`）。
///
/// ## ⚠️ 2026-10-16 起它是 **`List` 的一行**（NATIVE-MIGRATION P3）
///
/// 同 `PinRow`：自绘的内边距 14、卡内 hairline、外层 `CardBox` 全部删除 ——
/// 行内边距 / 卡片底 / 分隔线 / 整行点击范围改由 `List` 给。
/// `showsSeparator` 这个入参随之消失（系统知道首行与末行）。
///
/// ## ⚠️ 描述与私有标记是**可空**的，而且首页那条路径上它们就是 `nil`
///
/// 「最近访问」在本机**只存仓库全名、访问时刻、以及当时是否可写**（`RecentVisit`，
/// PRD §3.13 / TECH_SPEC §7.2）—— 描述与私有性**都不在里面**。
/// 原型那两样是从 `scripts/01-data.js` 的演示数据表里取的，而真实产品里没有这张表。
///
/// 所以本行的两个可选字段表达的是"**调用方手上有没有**"：
/// - 有（例如将来在写入访问记录时顺手存下了当时的摘要）→ 画出来；
/// - 没有（当前的实情）→ 只画 `owner/name` 与相对时间。
///
/// ## 它为什么不收 `RepoSummary`
///
/// 2026-10-06 改动：此前它收一个 `RepoSummary`，于是首页只能现造一个
/// `RepoSummary(fullName: visit.fullName, starCount: 0)` 塞进来 —— 那个 **`0` 是假的**。
/// 现在它不需要 star（原型 `.recent-row` 也不显示），所以干脆把 fake 去掉：
/// 参数就是它真正用到的三样。**不用的字段不进参数**，也就不会有"某天有人顺手把它画出来"
/// 而显示一个编出来的 0 星这种事。
///
/// ## 为什么它在本 Feature 里
///
/// 同 `PinRow` / `RepoCard`（决策 #43）：认识领域模型的卡片不进 `GitDuoDesign`。
struct RecentRow: View {

    /// 仓库全名 `owner/name`。
    let fullName: String

    /// 仓库简介。`nil` = 调用方手上没有（首页当前的实情）。
    let description: String?

    /// 是否私有。`nil` = 调用方手上没有（首页当前的实情）。
    let isPrivate: Bool?

    /// 相对时间文案（`刚刚` / `昨天` / `2 天前`），由 `RecentVisit.timeLabel(now:)` 现算。
    ///
    /// ⚠️ **传字符串而不是 `Date`**：`RecentVisit` 的说明里写明了"原型把显示串直接存进数组"
    /// 是个坑（那条"刚刚"会永远停在"刚刚"）。现算的责任在领域层，组件只负责画。
    let timeLabel: String

    /// owner 的头像地址。`nil` = 调用方手上没有（记录太旧 / 地址失效）——
    /// 行内回退 owner 登录名的首字母兜底圆（走查第 72 条）。
    var ownerAvatarURL: URL? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            // ⚠️ 2026-10-15 起是 **owner 头像**（圆形，走查第 72 条），不再是原型的
            //    文件夹图标块；尺寸仍是 30（`RepoAvatar.row.diameter`）。
            UserAvatar(
                login: ownerLogin,
                avatarURL: ownerAvatarURL,
                diameter: RepoAvatar.row.diameter
            )

            VStack(alignment: .leading, spacing: 2) {
                name
                if let description, !description.isEmpty {
                    Text(description)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.Spacing.s)

            Text(timeLabel)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
                // 时间戳不该被说明文字挤走 —— 挤掉之后这一行就看不出"多久以前"了。
                .layoutPriority(1)
        }
        // ⚠️ 同 `PinRow`：让整行矩形（含 `Spacer` 空白）成为命中区。
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var name: some View {
        HStack(spacing: Theme.Spacing.xs) {
            // ⚠️ `Text` **插值**，不是 `Text + Text` —— 后者自 iOS 26 起已废弃
            //    （与 `PinRow` 同一处修法，理由见那里）。
            Text("\(ownerPart)\(namePart)")
                .font(Theme.Font.footnote.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            if isPrivate == true {
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

    /// 拆 owner / name —— 走 `RepositoryMapper.splitFullName` 那**一个**实现。
    ///
    /// ⚠️ **不用 `RepoSummary.owner` / `.name`**：那两样挂在 `RepoSummary` 上，
    /// 为一个字符串去构造一个领域对象（还要给假装用不到的 `starCount` 填个数）是倒过来的
    /// 依赖方向。这里直接用同一个拆分函数，口径仍然只有一处。
    private var split: (owner: String, name: String)? {
        try? RepositoryMapper.splitFullName(fullName)
    }

    private var ownerPart: Text {
        Text("\(split?.owner ?? "")/")
            .foregroundStyle(Theme.Palette.textTertiary)
    }

    private var namePart: Text {
        Text(split?.name ?? fullName).foregroundStyle(Theme.Palette.textPrimary)
    }

    /// owner 登录名 —— 头像首字母兜底用。走 `RepositoryMapper.splitFullName` 那一个实现
    /// （`try?` 吞错），理由同 `RepoSummary.owner`：别各写一遍拆分。
    private var ownerLogin: String {
        (try? RepositoryMapper.splitFullName(fullName))?.owner ?? ""
    }

    private var accessibilityLabel: String {
        var parts = [fullName]
        if isPrivate == true { parts.append("私有仓库") }
        if let description, !description.isEmpty { parts.append(description) }
        parts.append(timeLabel)
        return parts.joined(separator: "，")
    }
}

#Preview {
    // 它现在是 `List` 的一行 ⇒ 预览也按 `List` 摆。
    List {
        RecentRow(
            fullName: "vercel/next.js",
            description: "The React Framework",
            isPrivate: false,
            timeLabel: "昨天",
            ownerAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/14985020?v=4")
        )
        // 头像取不到（旧记录 / 地址失效）⇒ 首字母兜底圆 —— 也是一行合法的样子。
        RecentRow(
            fullName: "my-git/notes",
            description: nil,
            isPrivate: true,
            timeLabel: "2 天前"
        )
    }
}
