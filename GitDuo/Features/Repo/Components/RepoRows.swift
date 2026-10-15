import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 代码分区里的一行：目录或文件（原型 `scripts/05-repo.js` 的 `.file-row`）。
///
/// ```css
/// .file-row{display:flex;align-items:center;gap:11px;padding:11px 4px;
///           border-bottom:1px solid var(--border-soft)}
/// .file-row svg{width:17px;height:17px;stroke:var(--text3)}
/// .file-row .fname{font-size:14.5px;font-weight:550}
/// .file-row .fmsg{font-size:11.5px;color:var(--text3);margin-top:2px;
///                 white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
/// ```
///
/// ## ⚠️ 2026-10-11：`.fmsg`（行副标题）**有意不画**
///
/// 它要靠"每个条目补一次 `GET /commits?path=`"换来（决策 #49），
/// 用户认为这点信息不值这个代价 ⇒ 那条链路整条删除（`TreeEntry` 上已没有它）。
/// 原型那行 CSS 留在上面只为对照，本件不再渲染。
///
/// ## ⚠️ 图标用 SF Symbols，不照 SVG 描
///
/// 原型 `I.dir` / `I.file` 是自绘的 17px 线框图标。本仓从切片 3 起一律用
/// SF Symbols（`GitHubIcon`），好处是无障碍与 Dynamic Type 一起生效。
/// 这一处在 6.3 已按同一口径登记过（`GitHubIcon` 的说明），此处沿用。
struct RepoFileRow: View {

    let entry: TreeEntry

    /// 最后一行不画下边线（原型 `.file-row:last-child{border-bottom:none}`）。
    let showsSeparator: Bool

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: entry.kind == .directory ? GitHubIcon.folder : GitHubIcon.file)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: 20)

                Text(entry.name)
                    // 原型 14.5px/550 ⇒ 最近的一档是 `rowTitle`（`.subheadline` 15）。
                    .font(Theme.Font.rowTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: GitHubIcon.chevron)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            // 原型 `padding:11px 4px`（11 不在 4pt 阶里 ⇒ 写原值）。
            .padding(.vertical, 11)
            .padding(.horizontal, Theme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(Theme.Palette.borderSoft)
                    .frame(height: 1)
            }
        }
    }
}

// MARK: -

/// Commits 页里的一行（原型 `SCR.repoSection` 里 `repoSeg('commits')` 那支的 `.commit-row`）。
///
/// ```css
/// .commit-row{display:flex;gap:10px;align-items:center;padding:11px 4px;
///             border-bottom:1px solid var(--border-soft)}
/// .sha{font-family:Menlo;font-size:11.5px;color:var(--link);background:#ddf4ff;
///      padding:2px 7px;border-radius:6px}
/// ```
///
/// 第二行是 `{作者} 提交于 {时间}`。⚠️ 作者取不到时**只留时间** ——
/// 原型那处会拼出 `undefined 提交于 …`（它的演示数据里每个提交都有作者）。
/// 判据收在 `CommitSummary.metaLabel(now:)`，不在这里各写一次。
///
/// ## ⚠️ 「现在」由调用方给
///
/// 原型在渲染时算相对时间。SwiftUI 里在 `body` 里取 `Date()` 会让**每次重绘**
/// 都拿到略微不同的值 —— 本身无害，但它让"相对时间"变成渲染时机的一部分，
/// 截图与断言都无从稳定。所以本件收 `now`，由页面在进页 / 刷新时取一次。
struct RepoCommitRow: View {

    let commit: CommitSummary

    let now: Date

    /// 最后一行不画下边线。
    let showsSeparator: Bool

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // 原型 `.avatar{width:28px;height:28px}`（覆写了默认的 34）。
                UserAvatar(
                    login: commit.authorLogin,
                    avatarURL: commit.avatarURL,
                    diameter: 28
                )

                VStack(alignment: .leading, spacing: 0) {
                    Text(commit.message)
                        // 原型在这一处覆写 `font-size:13.5px;font-weight:600`（`.t1` 是 15/650）。
                        .font(Theme.Font.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(commit.metaLabel(now: now))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }

                Spacer(minLength: 0)

                shaBadge
            }
            .padding(.vertical, 11)
            .padding(.horizontal, Theme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(Theme.Palette.borderSoft)
                    .frame(height: 1)
            }
        }
    }

    /// 短哈希徽章（原型 `.sha`）。
    ///
    /// ⚠️ 视觉在 **`SHABadge`（设计包）**里 —— 提交详情页的头部画的是同一个徽章，
    /// 而它原先在这里是私有的一份。两处各画一次，任何一处改错了底色或字号
    /// 都不会报错，只会让同一个 SHA 在两个页面上长得不一样。
    ///
    /// ⚠️ 那句话（`提交 {shortSHA}`）**原先硬编码在这里**，现收进 `CommitCopy`
    /// —— 文案散在视图里是 App target 没有测试 target 时最容易漏掉的一类。
    private var shaBadge: some View {
        SHABadge(sha: commit.shortSHA)
            .accessibilityLabel(CommitCopy.shaAccessibilityLabel(shortSHA: commit.shortSHA))
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            CardBox() {
                RepoFileRow(
                    entry: TreeEntry(
                        name: "GitDuo", path: RepoPath(path: "GitDuo"), kind: .directory,
                        size: 0, sha: "abc"
                    ),
                    showsSeparator: true,
                    action: {}
                )
                RepoFileRow(
                    entry: TreeEntry(
                        name: "README.md", path: RepoPath(path: "README.md"), kind: .file,
                        size: 1_024, sha: "def"
                    ),
                    showsSeparator: false,
                    action: {}
                )
            }

            CardBox() {
                RepoCommitRow(
                    commit: CommitSummary(
                        sha: "a1b2c3d4e5f6", message: "fix(auth): 断网不再被当成登出",
                        authorLogin: "dev-j", avatarURL: nil, authoredAt: Date()
                    ),
                    now: Date(),
                    showsSeparator: true,
                    action: {}
                )
                // 作者被删号 ⇒ 第二行只留时间。
                RepoCommitRow(
                    commit: CommitSummary(
                        sha: "0f1e2d3c4b5a", message: "chore: 清掉 URLCache 残留",
                        authorLogin: nil, avatarURL: nil,
                        authoredAt: Date().addingTimeInterval(-7_200)
                    ),
                    now: Date(),
                    showsSeparator: false,
                    action: {}
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
