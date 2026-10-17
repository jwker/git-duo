import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 文件树分区的首屏骨架（TECH_SPEC §8.5）—— 代码页（§4.4.1）与 §4.13 文件浏览**共用这一份**。
///
/// ## ⚠️ 为什么它是独立类型，而不是 `RepoTreeSection.skeleton`（2026-10-09 切片 10）
///
/// 它现在有**两个调用点、都在代码页**（§4.4.1）：`RepoCodeView.content(_:)` 那一格
/// （头部还没回来 ⇒ 整页骨架）与 `RepoTreeSection` 自己那个 `skeleton`
/// （这一层的目录还在路上 ⇒ 分区骨架）。
/// ⚠️ §4.13 的文件浏览 2026-10-14 起就是**同一个代码页的只读档**，不再单独画一份。
///
/// ⚠️ **下面这条理由本体已经不作数了（2026-10-14 更正，别照旧读）**：
/// 当初写成 `RepoTreeSection.skeleton` 是**编译不过**的 —— 那时它是泛型视图
/// （`RepoTreeSection<Trailing: View>`，`Trailing` 就是面包屑右侧那个动作位），会报
/// `generic parameter 'Trailing' could not be inferred`。同一天那两个死参数删掉之后
/// **它不再是泛型视图** ⇒ 这条技术障碍没有了。
/// **但"独立件"这个结论仍然保留**：它靠的是"两个地方要画同一份"（上面那两个调用点），
/// 不是"泛型挡路"。所以**不要因为现在能写成 `RepoTreeSection.skeleton` 就顺手合并** ——
/// 那样代码页那一格（`content(_:)`）就没有骨架可用了。
///
/// 收成一份的判据同 6.4 建 `RepoTreeSection` 时那句话：
/// **同一个 UI 元素有两处定义 ⇒ 必然分叉**（分叉之后，改一处的人不会想到还有第二处）。
/// 此前 `RepoDetailView`（那时代码浏览还嵌在它里面）就自己抄了一份逐字相同的 `codeSkeleton`。
///
/// ## ⚠️ 2026-10-16 起目录那一片**不再自己画灰条**（NATIVE-MIGRATION P1）
///
/// 同 `RepoCardSkeleton`：渲染**真实的 `RepoFileRow`** + `.redacted(reason: .placeholder)`。
/// 从前那两条尺寸纪律（容器 padding 要与真实 `CardBox` 一致、行内边距要补 `11px 4px`）
/// **随之作废** —— 它们本来就是为了"手抄的几何别抄错"，现在没有第二份几何可抄。
///
/// ⚠️ 面包屑那一条（`BreadcrumbBar`，自绘件、C 组）**也换成了真件 + 占位路径**
/// —— 它只是一行纯展示（两个可选回调都不给），不需要"整套假的分支 / 路径上下文"。
///
/// ## ⚠️ 2026-10-16 起：回到 "面包屑 + `CardBox`" 一整块（本轮修复）
///
/// 代码页主干从 `List` 回到 `ScrollView` 后，本件也恢复为一块普通视图：
/// 面包屑直接放在 `VStack` 里，文件行装在 `CardBox` 中。
struct RepoTreeSkeleton: View {

    /// 画几行。取 6 是因为一屏能见到的行数大约就是这些。
    var rows: Int = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 面包屑：真件 + 占位分支名 / 路径段（两个回调都不给 ⇒ 整条不可点）。
            BreadcrumbBar(
                branch: Placeholders.shortLine,
                path: [Placeholders.line, Placeholders.shortLine]
            )
            // 骨架期不能把「占位占位占位」真画出来 ⇒ 用系统红化遮成灰块。
            .redacted(reason: .placeholder)
            // 原型 `.crumb{margin-bottom:8px}`。
            .padding(.bottom, Theme.Spacing.s)

            CardBox() {
                ForEach(0..<rows, id: \.self) { index in
                    RepoFileRow(
                        entry: .placeholder,
                        // `RepoFileRow` 是**底线件** ⇒ 最后一行不画（与真实树同一条）。
                        showsSeparator: index < rows - 1,
                        action: {}
                    )
                    .redacted(reason: .placeholder)
                    // ⚠️ `.redacted` **不拦截点击** ⇒ 遮住的行必须关命中，
                    //    否则骨架期点一行会推进一个 `README.md` 的占位目录。
                    .allowsHitTesting(false)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ScrollView {
        RepoTreeSkeleton()
            .padding(Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
