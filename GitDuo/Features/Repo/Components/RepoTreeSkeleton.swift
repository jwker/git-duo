import GitDuoDesign
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
