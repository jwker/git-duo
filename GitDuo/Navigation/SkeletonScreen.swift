import SwiftUI
import GitDuoDesign

/// 骨架期占位屏 —— 明确显示"这一屏属于哪个切片"，而不是空白或假数据。
///
/// 设计意图：骨架阶段最大的风险是**假数据被误当成已完成**。
/// 因此占位屏一律显示切片归属 + 对应文档章节，评审时一眼可辨。
///
/// ## ⚠️ 切片 9 之后它**已经没有调用点**了
///
/// 它是"骨架期"的工具：`RouteView` 里每一条未落地的推入页都用它顶着。
/// 切片 9 把最后三条（我的 Star / 我的收藏 / 设置）换成真件之后，
/// 全 App 再没有半成品页面 —— `SkeletonPlaceholders.registry` 也随之清空
/// （`AGENTS.md §5.2`：登记册清零是"没有占位"的唯一证据）。
///
/// 类型**留着**而不是删掉：`AGENTS.md §0` 那条纪律（"未落地的界面一律用本屏占位，
/// 不许用假数据冒充成品"）指向的就是它，下一个切片真要再加页面时它还是那个落点。
/// 而与它**同一用途、同一哲学**的 `PendingSection`（页内占位块）已随本片删除 ——
/// 那是因为它的 `#Preview` 里逐字写着"切片 9 落地"，留着就与完成定义第 149 条
/// （"全 App 不该再有一个'切片 N 落地'字样"）自相矛盾。
struct SkeletonScreen: View {

    let title: String
    /// 该屏将在哪个切片落地
    let slice: String
    /// 对应文档出处（PRD / TECH_SPEC 章节）
    let reference: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(title)
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Palette.textPrimary)

            Label(slice, systemImage: "hammer")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)

            Text(reference)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.page)
        .background(Theme.Palette.background)
    }
}

#Preview {
    // ⚠️ 演示值**不提任何切片编号**：它只是这个屏长什么样的说明，
    //    而"切片 N 落地"这种字样在完成定义里是被点名要绝迹的
    //    （第 149 条 —— 那是给评审用的"还差什么"清单，不该留在演示里）。
    SkeletonScreen(
        title: "尚未落地的页面",
        slice: "本切片尚未落地",
        reference: "PRD §4.x / TECH_SPEC §9.x"
    )
}
