import GitDuoCore
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 「我的 Star」列表的一行（PRD §4.18、原型 `12-me.js` 的 `SCR.stars`）。
///
/// 形状（自上而下逐条对原型）：一张 `.card` 里一行 —— 仓库图标 · 「全名（链接色）+
/// `★ {Star} · {语言}`」· 右侧那颗「已 Star」按钮。
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
/// ## ⚠️ 只有「全名 + 副标题」那一块可点，图标不可点
///
/// 原型把 `onclick` 挂在 `.grow` 上（**不含**仓库图标与那颗按钮）。
/// 顺手把整张卡做成按钮看着更"好用"，但那会让"点图标"与"点名字"跳去同一个地方
/// —— 而这一行的右侧按钮做的是**另一件事**（取消 Star），三者挤在一起时
/// 区分"点到哪个"就变得很难说清。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
struct StarRow: View {

    let repository: Repository

    /// 这一行现在该显示什么 —— **由 ViewModel 给**（它记着哪几行被点过）。
    let state: StarState

    /// 这颗按钮是否在途（内联转圈 + 禁用，§8.5「操作类」）。
    let isToggling: Bool

    /// 点「全名 / 副标题」那一块 → 去这个仓库。
    let onOpen: () -> Void

    /// 点右侧那颗按钮 → 切换 Star。
    let onToggle: () -> Void

    var body: some View {
        // 原型 `.card{padding:14px}` ⇒ `CardBox(vertical: 14)`。
        CardBox(vertical: 14) {
            HStack(spacing: 10) {
                // 原型 `.row{gap:10px}`（10 不在 4pt 阶里 ⇒ 写原值，同 `SheetRow`）。
                RepoAvatar.standard

                Button(action: onOpen) {
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
                    // 点名前那一块要盖住整块（否则只有文字那几个字响应点击）。
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 原型 `style="padding:7px 12px"` + `.btn.ghost`。
                // ⚠️ `fillsWidth: false` —— `.btn` 本身是 `display:inline-flex`（按内容宽）。
                ActionButton(
                    title: ProfileCopy.unstarAction,
                    style: .ghost,
                    verticalPadding: 7,
                    horizontalPadding: 12,
                    fillsWidth: false,
                    isWorking: isToggling,
                    action: onToggle
                )
            }
        }
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
}

#Preview {
    VStack(spacing: Theme.Spacing.s) {
        // 已 Star（进页的样子）。
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
            ),
            isToggling: false,
            onOpen: {}, onToggle: {}
        )

        // 点过「已 Star」之后就地改文案（PRD §4.18）—— 这一行**不消失**。
        StarRow(
            repository: Repository(
                owner: "rust-lang", name: "rust",
                description: nil, isPrivate: false, language: "Rust",
                starCount: 98_000, forkCount: 12_600,
                permissions: .none
            ),
            state: StarState(
                fullName: "rust-lang/rust", isStarred: false,
                starCount: 97_999, baselineConfirmed: true
            ),
            isToggling: false,
            onOpen: {}, onToggle: {}
        )

        // 在途：按钮内联转圈。
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
            ),
            isToggling: true,
            onOpen: {}, onToggle: {}
        )
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
