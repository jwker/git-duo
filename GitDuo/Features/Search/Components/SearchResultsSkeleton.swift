import SwiftUI
import GitDuoDesign

/// 搜索结果的首屏骨架屏（TECH_SPEC §8.5 第 1 档）。
///
/// 形状照着 `.sr-item` 那一族行写：**方形图标块 + 两行占位条**。
/// 四种结果行的图标分别是 32 的仓库块 / 34 的头像 / 16 的文件图标 / 17 的状态图标，
/// 骨架屏不可能同时对着四种 —— 取其中最宽的那一档（32，仓库块），
/// 于是切换范围时那一片占位的**左边界不会跳**。
///
/// ⚠️ 尺寸必须跟着真实行的改动一起改（§8.5 第 1 条）：行里的
/// `padding(.vertical, 11)` 与 11 的间距一旦变了，这里的数字不跟，数据到达时整屏就会跳一下。
///
/// ⚠️ 它是内容层 ⇒ **只用实色**，绝不加 Liquid Glass（§10.2）。
struct SearchResultsSkeleton: View {

    /// 画几条。默认 6 —— 首屏（30 条一页）里能填满一屏，又不至于在数据到达时
    /// "多出几条凭空消失"。
    var count = 6

    var body: some View {
        // 方案 A：与真实结果同构 —— 一组行 = 一张白卡（`SearchView` 那处也这么包）。
        CardBox(vertical: 0, horizontal: 0) {
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    HStack(alignment: .center, spacing: 11) {
                        SkeletonBar(height: 32, width: 32, cornerRadius: Theme.Radius.segment)

                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            SkeletonBar(height: 14)
                            SkeletonBar(height: 11, width: 150)
                        }

                        Spacer(minLength: 0)
                    }
                    // 方案 A：与 `SearchRowBox` 一致（padding 14 / 内嵌缩进 57）。
                    .padding(14)
                    .overlay(alignment: .topLeading) {
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.Palette.borderSoft)
                                .frame(height: 1)
                                .padding(.leading, 57)
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    SearchResultsSkeleton()
        .padding(.horizontal, Theme.Spacing.page)
        .background(Theme.Palette.background)
}
