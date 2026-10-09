import GitDuoDesign
import SwiftUI

/// 文件树分区的首屏骨架（TECH_SPEC §8.5）—— §4.4 代码分区与 §4.13 文件浏览**共用这一份**。
///
/// ## ⚠️ 为什么它是独立类型，而不是 `RepoTreeSection.skeleton`（2026-10-09 切片 10）
///
/// 两个地方要画它：`RepoTreeSection` 自己（§4.13），以及 `RepoDetailView` 的代码分区
/// —— 而后者**用的就是 `RepoTreeSection`**，所以骨架本该公司一份。
/// 但 `RepoTreeSection` 是**泛型视图**（`RepoTreeSection<Trailing: View>`，
/// 那个 `trailing` 是面包屑右侧的动作位）⇒ 写成 `RepoTreeSection.skeleton` 会直接
/// **报 `generic parameter 'Trailing' could not be inferred` 编译不过**。
/// 于是改成一个**非泛型**的独立件：两边都写 `RepoTreeSkeleton()`，仍然只有一处定义。
///
/// 收成一份的判据同 6.4 建 `RepoTreeSection` 时那句话：
/// **同一个 UI 元素有两处定义 ⇒ 必然分叉**（分叉之后，改一处的人不会想到还有第二处）。
/// 此前 `RepoDetailView` 就自己抄了一份逐字相同的 `codeSkeleton`。
///
/// ## ⚠️ 两条尺寸纪律（都是"看一眼看不出来"的那类）
///
/// ① **容器参数必须与 `RepoTreeSection` 里那个真实 `CardBox` 逐字一致**
///    （`vertical: Theme.Spacing.xs` = 4）—— 骨架此前写的是 `Theme.Spacing.m`（12）
///    ⇒ 数据到达时**整块上移 8pt**。
/// ② **每行要补上 `RepoFileRow` 自己的行内边距**（原型 `padding:11px 4px`）——
///    少了它，骨架 6 行挤成一团、真实 6 行摊开，接上的那一瞬间每一行都往下挪。
///
/// ⚠️ 它是内容层 ⇒ **只用实色**，绝不加 Liquid Glass（§10.2）。
struct RepoTreeSkeleton: View {

    /// 画几行。取 6 是因为一屏能见到的行数大约就是这些。
    var rows: Int = 6

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            // 面包屑那一条（`BreadcrumbBar` 高 32）。
            SkeletonBar(height: 32)

            CardBox(vertical: Theme.Spacing.xs, horizontal: 14) {
                ForEach(0..<rows, id: \.self) { _ in
                    SkeletonBar(height: 15, width: 190)
                        // 与 `RepoFileRow` 的 `padding:11px 4px` 同值。
                        .padding(.vertical, 11)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    RepoTreeSkeleton()
        .padding(.horizontal, Theme.Spacing.page)
        .background(Theme.Palette.background)
}
