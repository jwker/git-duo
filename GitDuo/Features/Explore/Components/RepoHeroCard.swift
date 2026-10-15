import SwiftUI
import GitDuoCore
import GitDuoDesign
import GitDuoKit

/// 他人仓库详情的头部大卡（PRD §4.13 第 1 条、原型 `scripts/10-explore-repo.js` 的 `.repo-hero`）。
///
/// 内容：仓库图标 · 全名 · `{更新时间} 更新 · {许可证} 许可证` · 描述 · 话题标签（链接色）·
/// 一组统计（**能写的那颗星是按钮**，其余是**信息**）。
///
/// ## ⚠️ 那一排里**最多只有一颗是按钮**（2026-10-15，走查第 66 / 67 条）
///
/// 这一天连着定了两件事，原则是同一条 —— **形状即信号**：
/// "有底色 + 边框"在这个 App 里 = **这块点得动**。
///
/// | | 用的件 | 为什么 |
/// |---|---|---|
/// | Watch / Fork | `StatInfo`（裸信息） | 它们**永远**点不动（PRD §4.13 原文只写"展示订阅计数"），画成按钮就是承诺一件不会发生的事 |
/// | Star · **能写** | `StatButton` | 它本来点得动 —— 形状在这里是**兑现**，不是承诺 |
/// | Star · **确定写不了** | `StatInfo`（裸信息） | 同第一条：一颗点不动的灰按钮，形状在撒谎 |
///
/// （Fork 另有一条理由：它是**会改变账号状态的写操作**，PRD 仍标 ⏳「待细化」，
/// 在落地方式定下来之前不做半截。）
///
/// ⚠️ **本页是这条改动受益最明显的一屏**：这里出现的几乎都是别人的仓库
/// （见下"Star 的第二档"），从前是**三颗按钮、三颗按不动** ——
/// 现在那一排在常态下**一颗按钮都没有**，整行读起来真的只是一句统计。
///
/// ⚠️ 三颗该画成什么形状，判据**全部收在 `StatStar` / `StatInfo`**，本件不自己判 ——
/// 这里只负责把 `canStar` / `isStarred` 传下去（文案仍取自领域层 `StarCopy` / `RepoCopy`）。
///
/// ## 🔴 Star 的**第二档**：确定写不了 ⇒ 那颗星**不再是按钮**（决策 #80 + 走查第 67 条）
///
/// 2026-10-09 起（走查 #3 定案，`TECH_SPEC §3.5.5`）：GitHub App 的用户令牌**只能 Star
/// 安装范围内（在册账号名下）的仓库**，别人的仓库一律 403。
///
/// ⚠️ **本页是这条限制影响最大的屏**：这里出现的每一条都是**别人的仓库**
/// （趋势榜 / 搜索点进来的 / 别人的 Star），也就是**几乎每一条都写不了**。
/// 这不是异常分支，它就是这一页的常态。
///
/// ⇒ 2026-10-15 起那一档改用 `StatInfo`（裸信息），**不再是灰按钮**。
/// 理由与 §4.4 的 `RepoDetailHero` 是同一份（**形状即信号** + `.disabled` 会把
/// "已 Star"那几个字一起压暗）。
///
/// ## ⚠️ 本页**不再有**「不能 Star」的说明行与页脚（2026-10-15，走查第 68 条）
///
/// 从前这一行是三段：`statRow` / 说明行（「GitDuo 未被授权访问该仓库，暂不能 Star」）/
/// 页脚（「他人仓库 · 只读浏览，Fork 后可编辑与提交」，PRD §4.13 原文）。
/// 用户同日用截图圈掉这两行灰字，裁定**都去掉**：
///
/// - **说明行**：它的解释对象（那颗灰按钮）第 67 条已经拆掉了 —— 屏上没有 Star 动作，
///   「暂不能 Star」就没的可解释（同第 66 条删 Watch / Fork hint 的先例）。
///   "为什么不能"这件事只保留在**读屏 hint**里（视觉上不再占一行）。
/// - **页脚**：用户裁定一并去掉 ⇒ **PRD §4.13 那句一并撤了**（PRD 侧已加补记）。
///   "这是别人的仓库、只读"这件事由页面本身的形态表达，不再用一行字重复。
struct RepoHeroCard: View {

    let detail: RepositoryDetail

    /// 相对时间现算用的"现在"。由调用方给，不在 `body` 里取 `Date()`
    /// —— 那样每次重绘都会拿到略微不同的值，测试也无从断言。
    let now: Date

    /// Star 的当前状态。`nil` = 基准还没确认（此时按未 Star 显示 —— 见 `StarState`）。
    let star: StarState?

    /// Star 现在**写不写得动**（决策 #80 / `TECH_SPEC §3.5.5`）。
    ///
    /// ⚠️ `false` 只有一个含义：**已经确定**写不了（查到了安装范围、而本仓库不在其中）。
    /// "还没查到 / 拉取失败"一律是 `true` —— `StarWriteScope` 的口径是**不确定就不拦**：
    /// 误灰一个本来能点的按钮，比漏灰一个不能点的更糟（同 §8.5「还没加载出来 ≠ 确实没有」）。
    let canStar: Bool

    /// Star 请求在途（按钮内联 loading + 禁用，§8.5）。
    let isTogglingStar: Bool

    let onToggleStar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            description
            topics
            statRow
                .padding(.top, Theme.Spacing.m)
        }
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
            // ⚠️ 2026-10-15 起是 **owner 头像**（圆形，走查第 72 条），不再是原型的
            //    文件夹图标块；尺寸仍是 34（`RepoAvatar.standard.diameter`）。
            UserAvatar(
                login: detail.owner,
                avatarURL: detail.ownerAvatarURL,
                diameter: RepoAvatar.standard.diameter
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.fullName)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                // `{更新时间} 更新 · {许可证} 许可证` —— 逐字对齐原型（`10-explore-repo.js:13`）。
                Text(detail.metaLabel(now: now))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var description: some View {
        if let description = detail.description, !description.isEmpty {
            Text(description)
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.leading)
                .padding(.top, 6)
        }
    }

    /// 话题标签。原型用 `.chip` + 链接色（没有边框、没有底色）——
    /// 理由说得通：标签是**可搜的入口**，而这一屏的链接色已经被用来表示"点得动"。
    @ViewBuilder
    private var topics: some View {
        if !detail.topics.isEmpty {
            // 换行排列：标签个数不定（0–20 个），一行放不下必须能折下去。
            FlowLayout(spacing: Theme.Spacing.s) {
                ForEach(detail.topics, id: \.self) { topic in
                    Text(topic)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
            .padding(.top, Theme.Spacing.s)
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
        // 基准未确认时按"未 Star"显示（`StarState` 的降级），计数用详情里的那个数。
        let isStarred = star?.isStarred ?? false
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
        // ⚠️ 写不了那一档把**原因**交给读屏 —— 屏上已经没有那一行说明
        //    （2026-10-15 走查第 68 条删掉），读屏 hint 成了这件事**唯一**的承载：
        //    否则用户只听到一句不带动作的 "Starred，N 个 Star"，无从知道为什么没有 Star 动作。
        //    能写那一档不给 hint（空串 = 没有提示），否则每次念按钮都要多一句无用的。
        .accessibilityHint(canStar ? "" : StarCopy.unavailableHint)
    }

    /// Watch —— **一条信息，不是按钮**。计数读 `subscribers_count`（`detail.watcherCount`），
    /// ⚠️ 不是 `watchers_count`（那是 Star 数的历史别名，读错会让两个数显示成同一个）。
    private var watchInfo: some View {
        StatInfo(
            systemImage: "eye",
            title: RepoCopy.watchLabel(count: detail.watcherCount)
        )
    }

    /// Fork —— **一条信息，不是按钮**（见类型说明）。
    private var forkInfo: some View {
        StatInfo(
            // ⚠️ 走 `ForkIcon()` 而不是 SF Symbol：SF Symbols 里没有「实线 fork」这个字形，
            // 用户报回相差太多，所以设计包里自绘了 `ForkIcon`，与 `RepoDetailHero` 统一用。
            icon: ForkIcon().frame(width: 12, height: 12),
            title: RepoCopy.forkLabel(count: detail.forkCount)
        )
    }

    // ⚠️ Watch / Fork 的文案**已收拢到领域层** `RepoCopy`
    //    （`watchLabel(count:)` / `forkLabel(count:)`）：
    //    §4.4 的头部是同一个数、同一句话，两处各写一份迟早分叉
    //    —— 分叉的症状是同一个仓库在两页上显示成两个数，而两页单看都对。
    //    （两句 `...UnavailableHint` 2026-10-15 已随"改成裸信息"一起删掉，见类型说明。）
}

#Preview {
    ScrollView {
        VStack(spacing: Theme.Spacing.l) {
            RepoHeroCard(
                detail: RepositoryDetail(
                    fullName: "kuda/ui-craft",
                    description: "面向 iOS 的组件库 · 设计令牌 / 无障碍 / 深色模式",
                    topics: ["swiftui", "design-tokens", "ios", "accessibility", "components"],
                    licenseLabel: "MIT",
                    defaultBranch: "main",
                    starCount: 11_240,
                    forkCount: 412,
                    watcherCount: 88,
                    pushedAt: Date().addingTimeInterval(-1_800),
                    permissions: .none
                ),
                now: Date(),
                star: StarState(
                    fullName: "kuda/ui-craft", isStarred: true, starCount: 11_241, baselineConfirmed: true
                ),
                // ⚠️ **写不了那一档才是本页的常态**（这里装的都是别人的仓库）——
                //    所以拿它当第一张预览图，而不是拿"能点"的那一档。
                //    ⚠️ 2026-10-15 起它不再画成灰按钮，而是一条**裸信息**：
                //    实心金星 + `Starred · 11,241` —— **不靠形状报状态**，
                //    所以"已 Star"这件事终于读得出来了（从前被 `.disabled` 一起压暗）。
                canStar: false,
                isTogglingStar: false,
                onToggleStar: {}
            )
            RepoHeroCard(
                detail: RepositoryDetail(
                    fullName: "misoge/paneltkit",
                    description: nil,
                    topics: [],
                    licenseLabel: "未指定",
                    defaultBranch: "main",
                    starCount: 2_341,
                    forkCount: 0,
                    watcherCount: 0,
                    pushedAt: nil,
                    permissions: .none
                ),
                now: Date(),
                star: nil,
                // 对照组：可写 ⇒ 按钮正常（走查单 #152 的判据）。
                canStar: true,
                isTogglingStar: true,
                onToggleStar: {}
            )
        }
        .padding(Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
