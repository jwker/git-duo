import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 「我的仓库」详情页的头部大卡（PRD §4.4 第 1 条、原型 `scripts/05-repo.js` 的 `SCR.repoDetail`）。
///
/// 内容：仓库图标 · 全名 · 描述 · 三个统计按钮（Star / Watch / Fork）。
///
/// ## ⚠️ 它与 `RepoHeroCard`（§4.13）是**两张卡**，不是同一张的两种态
///
/// | | 本件（§4.4） | `RepoHeroCard`（§4.13） |
/// |---|---|---|
/// | 元信息行 `{更新时间} 更新 · {许可证} 许可证` | **没有** | 有 |
/// | 话题标签 | **没有** | 有 |
/// | 底部说明 | **没有** | `他人仓库 · 只读浏览，Fork 后可编辑与提交` |
/// | Star / Watch / Fork | 同（文案都取自领域层 `StarCopy` / `RepoCopy`） |
///
/// 原型这两页的 `repo-hero` 块里就是这四行的差别，PRD §4.4 第 1 条也只列到描述为止。
/// 合并成一张"按 `canWrite` 决定画不画那三行"的卡会让两个页面的头部互相牵制
/// （给他人仓库加一行元信息，自己的仓库也跟着变了）——
/// 而归属本来就是**路由**在进入前定下的（铁律 #7），这里不该再判一次。
///
/// ## ⚠️ Watch 与 Fork 是**纯展示**的（决策见 PRD §4.4 / §4.13）
///
/// 与 `RepoHeroCard` 同一处置：`allowsHitTesting(false)`（**不是** `.disabled`
/// —— 后者会变灰、看起来像"暂时不可用"）+ 去掉 `.isButton` trait + 一句读屏 hint。
/// 文案与 STAR 一致地取自领域层，两页共用一份。
///
/// ## Star 按钮：基准未确认时按「未 Star」显示
///
/// `star` 为 `nil`（进页那次 `GET /user/starred/{o}/{r}` 还没回来或失败了）
/// 时按未 Star 画 —— 这是 `StarState` 的既定降级（决策 #41），
/// 本件不自己造第二套判断。
struct RepoDetailHero: View {

    let detail: RepositoryDetail

    /// Star 的当前状态。`nil` = 基准还没确认（见类型说明）。
    let star: StarState?

    /// Star 请求在途（按钮内联 loading + 禁用，§8.5）。
    let isTogglingStar: Bool

    let onToggleStar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            description
            statRow
                .padding(.top, Theme.Spacing.m)
        }
        // 原型 `.repo-hero{padding:16px;border-radius:16px}`。
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

            // 原型 `.repo-hero h2{font-size:19px;font-weight:750}` ⇒ 最近的一档是
            // `title`（`.title3` 20 + semibold；本仓没有 750 这一档字重）。
            Text(detail.fullName)
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// 描述。**为空时整块不渲染**（原型会把 `undefined` 印出来）。
    @ViewBuilder
    private var description: some View {
        if let description = detail.description, !description.isEmpty {
            Text(description)
                // 原型 `.repo-hero .desc{font-size:13px;color:var(--text2);margin:6px 0 12px}`。
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .padding(.bottom, Theme.Spacing.m)
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
        let isStarred = star?.isStarred ?? false
        // 基准未确认时计数用详情里的那个数（`RepositoryDetail.starCount`）——
        // 它与基准是**两个不同的量**：没 Star 过的仓库那个数就是总数，Star 过的也是。
        let count = star?.starCount ?? detail.starCount

        return StatButton(
            systemImage: "star",
            activeSystemImage: "star.fill",
            title: StarCopy.buttonTitle(isStarred: isStarred, starCount: count),
            isActive: isStarred,
            activeTint: Theme.Palette.starActive,
            action: onToggleStar
        )
        .disabled(isTogglingStar)
        .overlay {
            if isTogglingStar {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityLabel(StarCopy.accessibilityLabel(isStarred: isStarred, starCount: count))
    }

    private var watchButton: some View {
        StatButton(
            systemImage: "eye",
            title: RepoCopy.watchLabel(count: detail.watcherCount),
            action: {}
        )
        .allowsHitTesting(false)
        .accessibilityRemoveTraits(.isButton)
        .accessibilityHint(RepoCopy.watchUnavailableHint)
    }

    private var forkButton: some View {
        StatButton(
            // ⚠️ 走 `GitHubIcon.fork` 而不是字面量：`RepoHeroCard`（§4.13）画的是同一个按钮，
            //    两处各写一串字面量时，"换一个图标"只会改到其中一处。
            systemImage: GitHubIcon.fork,
            title: RepoCopy.forkLabel(count: detail.forkCount),
            action: {}
        )
        .allowsHitTesting(false)
        .accessibilityRemoveTraits(.isButton)
        .accessibilityHint(RepoCopy.forkUnavailableHint)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: Theme.Spacing.l) {
            RepoDetailHero(
                detail: RepositoryDetail(
                    fullName: "my-git/gitduo",
                    description: "GitHub 客户端 · SwiftUI · 零第三方依赖",
                    defaultBranch: "main",
                    starCount: 128,
                    forkCount: 12,
                    watcherCount: 9
                ),
                star: StarState(
                    fullName: "my-git/gitduo", isStarred: true, starCount: 129, baselineConfirmed: true
                ),
                isTogglingStar: false,
                onToggleStar: {}
            )

            // 描述为空 + 基准未确认（首帧与失败降级都走这一支）。
            RepoDetailHero(
                detail: RepositoryDetail(
                    fullName: "my-git/empty-repo",
                    description: nil,
                    defaultBranch: "trunk",
                    starCount: 0,
                    forkCount: 0,
                    watcherCount: 0
                ),
                star: nil,
                isTogglingStar: true,
                onToggleStar: {}
            )
        }
        .padding(Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
