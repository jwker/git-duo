import GitDuoCore
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 「我的 Star」列表的一行（PRD §4.18、原型 `12-me.js` 的 `SCR.stars`）。
///
/// 形状（自上而下逐条对原型）：仓库图标 ·「全名（链接色）+ `★ {Star} · {语言}`」。
///
/// ```html
/// <div class="card"><div class="row">
///   <div class="repo-avatar">…</div>
///   <div class="grow" onclick="push(…)">
///     <div class="t1" style="color:var(--link)">{全名}</div>
///     <div class="t3" style="margin-top:3px">{星形图标} {星数} · {语言}</div>
///   </div>
///   <button class="btn ghost" style="padding:7px 12px" onclick="unstar(event,this)">已 Star</button>
/// </div></div>
/// ```
///
/// ## ⚠️ 2026-10-16 起它是 **`List` 的一行**（NATIVE-MIGRATION P3）
///
/// 两处变化：
/// 1. `CardBox` 撤掉（行底 / 内边距 / 圆角由 `List` 给），本件只画内容；
/// 2. **整行可点**（对外不再有 `onOpen`，由列表把它包进 `NavigationLink`）。
///
/// ⚠️ 第 2 条推翻了这里原先"只有「全名 + 副标题」那一块可点、图标不可点"的处置 ——
/// 那条处置是为了逐字跟随原型的 `onclick` 落点。**功能没有变**（点这一行还是去这个仓库），
/// 变的是命中面积：在 `List` 里"一行即一个目标"是平台的既有语义，
/// 而"行内划出一块才能点"反而是自定列表才有的形状（`AGENTS.md §0`：按原型 = 功能按原型）。
///
/// ## ⚠️ 右侧那颗「已 Star」按钮**不画了**（2026-10-15 · 用户裁定）
///
/// 原型每行右侧有一颗「取消 Star」的 ghost 按钮（上面 HTML 的最后那个 `<button>`）。
/// 用户裁定**先去掉**，原话「先去掉，因为也不可管理」—— 列表行不做 Star 的管理动作，
/// Star / 取消 Star 的操作入口留在仓库详情页头部那颗统计上（`StatStar`，写得了才有形状）。
/// ⚠️ ViewModel 侧的切换机制（`MyStarsViewModel.toggleStar` 那一套）**原样保留**，
/// 回加按钮时即用；`ProfileCopy.unstarAction` 文案同理。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
struct StarRow: View {

    let repository: Repository

    /// 这一行现在该显示什么 —— 由 ViewModel 给（星数从列表条目 / 本页改过的记录里来）。
    let state: StarState

    var body: some View {
        HStack(spacing: 10) {
            // 原型 `.row{gap:10px}`（10 不在 4pt 阶里 ⇒ 写原值，同 `SheetRow`）。
            // ⚠️ 2026-10-15 起是 **owner 头像**（圆形，走查第 72 条），不再是原型的
            //    文件夹图标块；尺寸仍是 34（`RepoAvatar.standard.diameter`）。
            UserAvatar(
                login: repository.owner,
                avatarURL: repository.ownerAvatarURL,
                diameter: RepoAvatar.standard.diameter
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(repository.fullName)
                    // 原型 `.t1{font-size:15px;font-weight:650}` ⇒ `rowTitle` + semibold。
                    .font(Theme.Font.rowTitle.weight(.semibold))
                    // …同行 `style="color:var(--link)"`。
                    .foregroundStyle(Theme.Palette.accent)
                    .lineLimit(1)
                    .truncationMode(.middle)

                metaLabel
                    // 原型 `style="margin-top:3px"`。
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 读屏：整行合成一句（全名 + 星数 + 语言），而不是把三个碎片逐个念。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// 副标题：`★ {Star} · {语言}`。
    ///
    /// ⚠️ 星数走 **`CompactNumber`**（`124k`）而不是千分位 —— 与仓库卡片上那一颗
    /// **同一套**：原型这两处用的是同一个字段、同一个写法（`01-data.js` 里
    /// `s` 就是 `"124k"` / `"98k"`）。⚠️ 别与「我的」页头部那三个数混：
    /// 那三个是用户要**读准**的，走千分位全量（`ProfileStatItem.valueText`）。
    ///
    /// ⚠️ 语言为 `nil` 时**整段去掉**（只留星数），不补一个空格或破折号
    /// —— 同 `CodeHit.metaLabel` 那条"遇到没覆盖的情形就不要编"。
    private var metaLabel: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: GitHubIcon.star)
                // 与仓库结果行那颗星同一档（`RepositoryResultRow.chips` 的 13）——
                // 两处是同一个视觉成语（"星形 + 数字"），尺寸不该各写一个。
                .font(.system(size: 13))
                .accessibilityHidden(true)

            if let language = repository.language, !language.isEmpty {
                Text("\(CompactNumber.string(from: state.starCount)) · \(language)")
            } else {
                Text(CompactNumber.string(from: state.starCount))
            }
        }
        // 原型 `.t3{font-size:11.5px;color:var(--text3)}`。
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.Palette.textTertiary)
        .lineLimit(1)
    }

    private var accessibilityLabel: String {
        var parts = [repository.fullName]
        parts.append("\(state.starCount) 个 Star")
        if let language = repository.language, !language.isEmpty { parts.append("主语言 \(language)") }
        return parts.joined(separator: "，")
    }
}

#Preview {
    // 它现在是 `List` 的一行 ⇒ 预览也按 `List` 摆。
    List {
        StarRow(
            repository: Repository(
                owner: "vercel", name: "next.js",
                description: nil, isPrivate: false, language: "JavaScript",
                starCount: 124_000, forkCount: 26_800,
                permissions: .none
            ),
            state: StarState(
                fullName: "vercel/next.js", isStarred: true,
                starCount: 124_000, baselineConfirmed: true
            )
        )

        // 语言为 nil ⇒ 副标题只留星数（不补空格 / 破折号）。
        StarRow(
            repository: Repository(
                owner: "my-git", name: "scripts",
                description: nil, isPrivate: false, language: nil,
                starCount: 41, forkCount: 5,
                permissions: .none
            ),
            state: StarState(
                fullName: "my-git/scripts", isStarred: true,
                starCount: 41, baselineConfirmed: true
            )
        )
    }
}
