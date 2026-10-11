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
///
/// ## ⚠️ Star 按钮的**第二档**：确定写不了 ⇒ 置灰 + 一行说明（决策 #80）
///
/// 2026-10-09 起（走查 #3 定案，`TECH_SPEC §3.5.5`）：GitHub App 的用户令牌
/// **只能 Star 安装范围内（也就是在册账号名下）的仓库**，别人的仓库一律 403。
/// 查到并确定不在范围内时，这里画成 `.disabled(true)` + 下方一行 `StarCopy.unavailableHint`。
///
/// ⚠️ 这一档与 `watchButton` / `forkButton` 的 `allowsHitTesting(false)` **有意不同**：
/// 那两个是"**这一屏本来就只展示计数**"（点了也没这功能），Star 是"**本该能点、此刻不能**"
/// —— 后者必须让用户看得出"是权限问题"，而不是"这功能还没做"。
///
/// | | Watch / Fork | Star（确定不可写） |
/// |---|---|---|
/// | 修饰符 | `.allowsHitTesting(false)` | **`.disabled(true)`** |
/// | 看起来 | 与可点的一模一样 | **灰的** |
/// | 为什么 | 它**永远**不可点 ⇒ 灰了反而像"暂时不可用" | 它本来能点 ⇒ 必须显出这一档差别 |
/// | 说明放哪 | 读屏 `hint` | **屏幕上那一行**（这一屏放得下） |
///
/// ⚠️ 判据只有一条：**这一处放得下说明吗**。放得下就置灰（本件与 §4.13 的头部），
/// 放不下就照常可点、失败时再说（§4.18 的列表行，见 `MyStarsViewModel.toggleStar`）。
struct RepoDetailHero: View {

    let detail: RepositoryDetail

    /// Star 的当前状态。`nil` = 基准还没确认（见类型说明）。
    let star: StarState?

    /// Star 现在**写不写得动**（决策 #80 / `TECH_SPEC §3.5.5`）。
    ///
    /// ⚠️ `false` 只有一个含义：**已经确定**写不了 —— 查到了安装范围、而本仓库
    /// 不在其中。"**还没查到 / 拉取失败**"一律是 `true`：`StarWriteScope` 的口径是
    /// **不确定就不拦**（灰掉它是替用户断言一件我们手里没有依据的事，同 §8.5）。
    ///
    /// ⚠️ 本页大概率永远看不到 `false`（这里的仓库多半是自己的，而自己的必然在范围内）。
    /// **唯一的例外是组织仓库**：你对它有 push、而那个组织没装 GitDuo ——
    /// 那一档正是这个参数存在的理由。
    let canStar: Bool

    /// Star 请求在途（按钮内联 loading + 禁用，§8.5）。
    let isTogglingStar: Bool

    let onToggleStar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            description
            statRow
                .padding(.top, Theme.Spacing.m)
            unavailableHint
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

    /// 三颗统计按钮。
    ///
    /// ⚠️ 用 `FlowLayout`（**不是** `HStack`）：三颗的宽度随内容（2026-10-11 由
    /// "竖排 · 三等分整宽"改，见 `StatButton`），长数字或 Dynamic Type 放大时
    /// 应当**折行**；`HStack` 放不下只会把它们压扁，把那串数字截掉。
    private var statRow: some View {
        FlowLayout(spacing: Theme.Spacing.s) {
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
        // 两档共用这一个修饰符：**在途**（§8.5"操作类"防重复提交）与**确定写不了**（§3.5.5）。
        .disabled(isTogglingStar || !canStar)
        .overlay {
            if isTogglingStar {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityLabel(StarCopy.accessibilityLabel(isStarred: isStarred, starCount: count))
        // ⚠️ 灰掉那一档把**原因**交给读屏 —— 否则用户只听到"一个变暗的按钮"，
        //    而下面那行说明是**另一个**元素（要再滑一下才听得到）。
        //    可点那一档不给 hint（空串 = 没有提示），否则每次念按钮都要多一句无用的。
        .accessibilityHint(canStar ? "" : StarCopy.unavailableHint)
    }

    /// 「写不了」时按钮下方那一行（决策 #80）。
    ///
    /// ⚠️ 文案取自 `StarCopy.unavailableHint` —— 与**失败提示**是同一句，
    /// 而这是有意的：用户在两处读到同一个原因，才不会再试第三次。
    /// 两处说的是同一件事的两种到达方式（"事先拦下"与"写了被拒"）。
    ///
    /// ⚠️ 形态与 `RepoHeroCard` 那一处逐字相同（`caption` / `textTertiary`），
    /// 差别只在**下面有没有页脚** —— 那边要多留一个 `Spacing.s` 把它与页脚隔开。
    @ViewBuilder
    private var unavailableHint: some View {
        if !canStar {
            Text(StarCopy.unavailableHint)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Theme.Spacing.s)
        }
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
            // ⚠️ 走 `ForkIcon()` 而不是 SF Symbol：`GitHubIcon.fork` 只能拿到
            // `point.3.connected.trianglepath.dotted`（虚点连线），与用户给的参考图
            //（两个上圆点 + 一个下圆点 + 实线）相差太多。所以设计包里自绘了一个
            // `ForkIcon`，两处统一用它。
            icon: ForkIcon().frame(width: 12, height: 12),
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
                canStar: true,
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
                canStar: true,
                isTogglingStar: true,
                onToggleStar: {}
            )

            // 确定写不了 ⇒ Star 变灰 + 下方一行说明（决策 #80）。
            // ⚠️ 本页真要看到这一档，得是"你对某个组织仓库有 push、而那个组织没装 GitDuo"
            //    —— 少见但可达，所以留一张在这儿当评审底图（走查单 #152 的对照组就在上面那张）。
            RepoDetailHero(
                detail: RepositoryDetail(
                    fullName: "org/private-tools",
                    description: "这个组织没有安装 GitDuo",
                    defaultBranch: "main",
                    starCount: 412,
                    forkCount: 7,
                    watcherCount: 3
                ),
                star: StarState(
                    fullName: "org/private-tools",
                    isStarred: false,
                    starCount: 412,
                    baselineConfirmed: true
                ),
                canStar: false,
                isTogglingStar: false,
                onToggleStar: {}
            )
        }
        .padding(Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
