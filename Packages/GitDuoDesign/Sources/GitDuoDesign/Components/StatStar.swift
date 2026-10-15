import SwiftUI

/// 仓库头部那一颗 **Star** —— 「**能写就画按钮、确定写不了就画成一条信息**」
/// 这条判据的**唯一一处**（2026-10-15 新增，走查第 **67** 条）。
///
/// ## 它治的是什么
///
/// 2026-10-09 起（决策 #80 / `TECH_SPEC §3.5.5`）本 App 的令牌**只能写安装范围内的仓库**，
/// 别人的仓库一律 403。查到并确定不在范围内时，这颗星此前画成
/// `.disabled(true)` + 下方一行说明 —— 但那是**一颗灰按钮**：它有按钮的形状，却点不动。
///
/// 用户 2026-10-15 报回「写不了就不画按钮」，打的正是这一点。它与两天前 Watch / Fork
/// 那次（走查第 66 条）**是同一条原则**：**形状即信号**。
/// 「有底色 + 边框 = 这块点得动」这条线索要成立，就不能有"长得像按钮但按不动"的东西。
///
/// ## ⚠️ 已 Star 那一档是重点（它是这次改动的起因）
///
/// 这一档从前是**一颗灰按钮**，标题写着 `已 Star · 12,341`。两个问题叠在一起：
///
/// 1. `.disabled(true)` 把**文字也一起压暗** —— "已 Star"那三个字基本被吞掉；
/// 2. 于是「我 star 过」与「我没 star 过」在屏幕上**只差一串看不清的字**。
///
/// 而"我 star 过没有"恰恰是进这一页最想知道的事。关键事实：`GET /user/starred/{o}/{r}`
/// **在别人的仓库上也是通的** —— 它读的是"**你**与这个仓库的关系"，那是你账号上的数据，
/// 不受安装范围约束（2026-10-09 真机实测；写那两条才要求仓库在册）。
/// 所以那个状态**本来就查得到、也早就查了**（`ToggleStar.initialState` 是无条件调的），
/// 只是屏幕上没有一处让人读得出来。
/// ⇒ 现在它改用 `StatInfo` 画：`Starred · 12,341` + 实心金星，
/// **不依赖"点得动"就能读出来**。
///
/// ## ⚠️ 两个形状的差别是有意的
///
/// | | 能写（自己名下的仓库） | 确定写不了（别人的仓库） |
/// |---|---|---|
/// | 件 | `StatButton` | `StatInfo` |
/// | 看起来 | 底色 + 圆角 + 边框 | 图标 + 文字，没有形状 |
/// | 已 Star 时 | 实心金星 + **整块**吃 `starActive` | 实心金星（吃 `starActive`）+ 文字 `textSecondary` |
/// | 在途时 | 禁用 + 内联 `ProgressView` | 不适用（它压根点不动） |
///
/// ⚠️ 「能写」那一档仍是**按钮**，这一点没变：它本来点得动，形状是**兑现**不是承诺。
///
/// ## ⚠️ 本件不产出文案
///
/// `title` 由调用方用 `StarCopy.statTitle(isStarred:starCount:)` 算好
/// （同 `StatButton` / `StatInfo` 的口径：文案属于领域层，组件只负责画）。
///
/// ⚠️ 本件也**不做任何判断**：`canStar` 为 `false` 只代表"**已经确定**写不了"，
/// 不确定（还没查到 / 拉取失败）一律传 `true`（`StarWriteScope` 的口径：不确定就不拦）。
/// 那条判断在领域层，这里只按传入的布尔量选形状。
///
/// ## 读屏
///
/// 两种形状各自带着 `title` 作标签（`StatButton` / `StatInfo` 内部都这么做）。
/// 调用方若要在"能点"那一档补一句"点按取消"，用外层 `.accessibilityLabel` 覆盖即可
/// —— 但**写不了那一档不要补"点按…"**（`StarCopy.accessibilityLabel(...isControl:)` 的第 3 个参数就是干这个的）。
public struct StatStar: View {

    /// 那颗星的文案（`StarCopy.statTitle(isStarred:starCount:)` 的产物）。
    public let title: String

    /// 是否已 Star —— 决定图标是实心还是空心，以及裸信息档的图标颜色。
    public let isStarred: Bool

    /// **确定写不了** ⇒ 不画按钮，画成裸信息。
    public let canStar: Bool

    /// 请求在途（只有能写那一档用得到 —— §8.5「操作类」防重复提交）。
    public let isToggling: Bool

    public let action: () -> Void

    public init(
        title: String,
        isStarred: Bool,
        canStar: Bool,
        isToggling: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isStarred = isStarred
        self.canStar = canStar
        self.isToggling = isToggling
        self.action = action
    }

    public var body: some View {
        if canStar {
            StatButton(
                systemImage: "star",
                activeSystemImage: "star.fill",
                title: title,
                isActive: isStarred,
                activeTint: Theme.Palette.starActive,
                action: action
            )
            // ⚠️ 只剩「在途」这一个 `.disabled` 了。从前它与"确定写不了"共用同一个修饰符，
            //    而两者原因完全不同：在途是**等一会儿就好**，写不了是**换个人来点也不行**
            //    —— 把后者拆去 `StatInfo` 之后，这里那个 `.disabled` 的语义才终于单一。
            .disabled(isToggling)
            .overlay {
                if isToggling {
                    ProgressView().controlSize(.small)
                }
            }
        } else {
            StatInfo(
                systemImage: isStarred ? "star.fill" : "star",
                title: title,
                // ⚠️ 金色只染**图标**：`Theme.Palette.starActive` 的抬头明写
                //    "只用于星形图标的填充 / 描边，绝不用作文字色"（白底上对比度不足 2:1）。
                iconTint: isStarred ? Theme.Palette.starActive : nil
            )
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
        // ① 能写（自己名下的仓库）：星是按钮，Watch / Fork 是信息。
        FlowLayout(spacing: Theme.Spacing.s) {
            StatStar(title: "Star · 2,341", isStarred: false, canStar: true, isToggling: false) {}
            StatInfo(systemImage: "eye", title: "Watch · 45")
            StatInfo(icon: ForkIcon().frame(width: 12, height: 12), title: "Fork · 88")
        }

        // ② ⚠️ **他人仓库的常态**：三颗全都不是按钮 —— 整行读起来真的只是一句统计。
        //    已 Star 那一颗是本件存在的理由：`Starred` + 实心金星，**不靠形状报状态**。
        //    （这一档从前是一颗灰按钮，"已 Star"三个字被 `.disabled` 一起压暗。）
        FlowLayout(spacing: Theme.Spacing.s) {
            StatStar(title: "Starred · 11,241", isStarred: true, canStar: false, isToggling: false) {}
            StatInfo(systemImage: "eye", title: "Watch · 88")
            StatInfo(icon: ForkIcon().frame(width: 12, height: 12), title: "Fork · 412")
        }

        // ③ 同一页的另一档：没 Star 过 —— 形状与 ② 相同，只有图标（空心）与词（`Star`）不同。
        FlowLayout(spacing: Theme.Spacing.s) {
            StatStar(title: "Star · 2,341", isStarred: false, canStar: false, isToggling: false) {}
            StatInfo(systemImage: "eye", title: "Watch · 3")
            StatInfo(icon: ForkIcon().frame(width: 12, height: 12), title: "Fork · 7")
        }

        // ④ 能写 + 已 Star + 在途：这一档仍是按钮（灰 + 内联 loading）。
        FlowLayout(spacing: Theme.Spacing.s) {
            StatStar(title: "Starred · 2,342", isStarred: true, canStar: true, isToggling: true) {}
            StatInfo(systemImage: "eye", title: "Watch · 45")
            StatInfo(icon: ForkIcon().frame(width: 12, height: 12), title: "Fork · 88")
        }
    }
    .padding(Theme.Spacing.page)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.Palette.background)
}
