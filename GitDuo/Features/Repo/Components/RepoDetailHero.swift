import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 「我的仓库」详情页的头部大卡（PRD §4.4 第 1 条、原型 `scripts/05-repo.js` 的 `SCR.repoDetail`）。
///
/// 内容：仓库图标 · 全名 · 描述 · 一组统计（**能写的那颗星是按钮**，其余是**信息**）。
///
/// ## ⚠️ 它与 `RepoHeroCard`（§4.13）是**两张卡**，不是同一张的两种态
///
/// | | 本件（§4.4） | `RepoHeroCard`（§4.13） |
/// |---|---|---|
/// | 元信息行 `{更新时间} 更新 · {许可证} 许可证` | **没有** | 有 |
/// | 话题标签 | **没有** | 有 |
/// | 底部说明 | **没有** | 也**没有了**（原有一句「他人仓库 · 只读浏览…」，2026-10-15 走查第 68 条随用户裁定删掉） |
/// | Star / Watch / Fork | 同（文案都取自领域层 `StarCopy` / `RepoCopy`） |
///
/// 原型这两页的 `repo-hero` 块里就是这四行的差别，PRD §4.4 第 1 条也只列到描述为止。
/// 合并成一张"按 `canWrite` 决定画不画那三行"的卡会让两个页面的头部互相牵制
/// （给他人仓库加一行元信息，自己的仓库也跟着变了）——
/// 而归属本来就是**路由**在进入前定下的（铁律 #7），这里不该再判一次。
///
/// ## ⚠️ Watch 与 Fork **不是按钮**（2026-10-15 起，走查第 66 条）
///
/// 它俩从来就点不动（PRD §4.4 原文只写"**展示** Watch 数"），但此前与 Star 共用
/// `StatButton` 的形态（底色 + 圆角 + 边框），且刻意**不加灰**（当时的理由是"灰了
/// 反而像暂时不可用"）⇒ 结果与那颗能点的长得一模一样，按下去却没有任何反应。
/// 用户 2026-10-15 报回「没有必要做成按钮形状了」，打的正是这一点。
///
/// ⇒ 现在改用 `StatInfo`（裸信息：图标 + 文案，无底色 / 边框 / 圆角）——
/// **形状本身就是信号**：有形状 = 点得动，没形状 = 只是一条信息。
/// 这比"两颗都灰掉"更准：灰是"暂时不可用"，而它俩是**这一版压根没有这个动作**。
/// 文案仍与 Star 一致地取自领域层，两页共用一份。
///
/// 连带删掉两句读屏 hint（`watchUnavailableHint` / `forkUnavailableHint`）——
/// 它们解释的是"一个按下去没反应的按钮"，而它俩现在已经不是按钮了。
/// 留着那句 hint，「这颗还不能点」在代码里就仍然看起来成立
/// —— 同 `RepoCopy.addFileUnavailableHint` 被删时的先例。
///
/// ## Star 按钮：基准未确认时按「未 Star」显示
///
/// `star` 为 `nil`（进页那次 `GET /user/starred/{o}/{r}` 还没回来或失败了）
/// 时按未 Star 画 —— 这是 `StarState` 的既定降级（决策 #41），
/// 本件不自己造第二套判断。
///
/// ## ⚠️ Star 的**第二档**：确定写不了 ⇒ 那颗星**不再是按钮**（决策 #80 + 走查第 67 条）
///
/// 2026-10-09 起（走查 #3 定案，`TECH_SPEC §3.5.5`）：GitHub App 的用户令牌
/// **只能 Star 安装范围内（也就是在册账号名下）的仓库**，别人的仓库一律 403。
/// 查到并确定不在范围内时 —— **2026-10-15 起改用 `StatInfo`（裸信息）**，
/// 不再是 `.disabled(true)` 的灰按钮；那一行「GitDuo 未被授权访问该仓库，暂不能 Star」
/// 的说明也**一并去掉了**（2026-10-15 走查第 68 条：屏上没有 Star 动作了，
/// 它就没的可解释 —— 与 `RepoHeroCard` 同日同裁）。
///
/// ## 为什么要拆掉那颗灰按钮
///
/// 它点不动，却有**按钮的形状** —— 而"有形状 = 点得动"是本 App 唯一的形状信号
/// （走查第 66 条刚为 Watch / Fork 定下的）。留着它，那条信号就弱一分。
///
/// 更要紧的是**已 Star 那一档**：`.disabled` 会把按钮上的**文字一起压暗**，
/// 于是「我 star 过」与「我没 star 过」在屏幕上只差一串看不清的字。
/// 而"我 star 过没有"恰恰是进这一页最想知道的事 —— 并且那个状态**本来就查得到**：
/// `GET /user/starred/{o}/{r}` 在别人的仓库上也是通的（它读的是"你与仓库的关系"，
/// 那是你账号上的数据，不受安装范围约束。2026-10-09 实测，见 `GitHubStarEndpoint`）。
///
/// | | 能写（自己名下的仓库） | 确定写不了（别人的仓库） |
/// |---|---|---|
/// | 用的件 | `StatButton`（星**是**按钮） | `StatInfo`（一条裸信息） |
/// | 看起来 | 底色 + 圆角 + 边框 | 图标 + 文案，没有形状 |
/// | 已 Star 时 | `Starred · {n}` + 实心金星 | `Starred · {n}` + 实心金星（图标吃 `starActive`） |
/// | 在途时 | 禁用 + 内联 `ProgressView` | 不适用（它压根点不动） |
///
/// ⚠️ 两种形态的**唯一出处是 `StatStar`** —— 本件不自己判"该画哪个"。
/// ⚠️ 「为什么写不了」这件事只走**读屏 hint**，屏上不再画说明行
/// （2026-10-15 走查第 68 条，同 `RepoHeroCard`）。⚠️ §4.18 列表行右侧那颗 Star 按钮
/// **2026-10-15 起不渲染了**（用户裁定「先去掉，因为也不可管理」，见 `StarRow` 抬头）
/// ⇒ **全 App 的 Star / 取消 Star 操作入口只剩详情页头部这一处**（可写的那一档）。
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

    /// 三颗统计 —— **一颗按钮（Star）+ 两条信息**（Watch / Fork）。
    ///
    /// ⚠️ 用 `FlowLayout`（**不是** `HStack`）：三颗的宽度随内容（2026-10-11 由
    /// "竖排 · 三等分整宽"改，见 `StatButton`），长数字或 Dynamic Type 放大时
    /// 应当**折行**；`HStack` 放不下只会把它们压扁，把那串数字截掉。
    private var statRow: some View {
        FlowLayout(spacing: Theme.Spacing.s) {
            starStat
            watchInfo
            forkInfo
        }
    }

    private var starStat: some View {
        let isStarred = star?.isStarred ?? false
        // 基准未确认时计数用详情里的那个数（`RepositoryDetail.starCount`）——
        // 它与基准是**两个不同的量**：没 Star 过的仓库那个数就是总数，Star 过的也是。
        let count = star?.starCount ?? detail.starCount

        return StatStar(
            title: StarCopy.statTitle(isStarred: isStarred, starCount: count),
            isStarred: isStarred,
            // ⚠️ 决定"这颗星是按钮还是一条信息"的就是这一个参数（走查第 67 条）。
            canStar: canStar,
            isToggling: isTogglingStar,
            action: onToggleStar
        )
        .accessibilityLabel(
            // ⚠️ `isControl` 传的是**这一档到底是不是控件** —— 写不了那一档若还念
            //    "点按取消"，读屏用户会去双击一个不是按钮的东西（见 `StarCopy`）。
            StarCopy.accessibilityLabel(isStarred: isStarred, starCount: count, isControl: canStar)
        )
        // ⚠️ 写不了那一档把**原因**交给读屏 —— 屏上已经没有那行说明
        //    （2026-10-15 走查第 68 条删掉），读屏 hint 成了这件事**唯一**的承载：
        //    否则用户只听到"Starred，N 个 Star"，无从知道为什么没有 Star 动作。
        //    能写那一档不给 hint（空串 = 没有提示），否则每次念按钮都要多一句无用的。
        .accessibilityHint(canStar ? "" : StarCopy.unavailableHint)
    }

    /// Watch —— **一条信息，不是按钮**（2026-10-15，见类型说明）。
    private var watchInfo: some View {
        StatInfo(
            systemImage: "eye",
            title: RepoCopy.watchLabel(count: detail.watcherCount)
        )
    }

    /// Fork —— **一条信息，不是按钮**（2026-10-15，见类型说明）。
    private var forkInfo: some View {
        StatInfo(
            // ⚠️ 走 `ForkIcon()` 而不是 SF Symbol：`GitHubIcon.fork` 只能拿到
            // `point.3.connected.trianglepath.dotted`（虚点连线），与用户给的参考图
            //（两个上圆点 + 一个下圆点 + 实线）相差太多。所以设计包里自绘了一个
            // `ForkIcon`，两处统一用它。
            icon: ForkIcon().frame(width: 12, height: 12),
            title: RepoCopy.forkLabel(count: detail.forkCount)
        )
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

            // 确定写不了 ⇒ Star 是一条**裸信息**（**不是**按钮，也没有说明行 —— 走查第 67 / 68 条：
            // 从前这里是一颗灰按钮 + 一行灰字，现已都拆掉）。
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
