import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 仓库列表的首屏骨架（TECH_SPEC §8.5）。
///
/// ## ⚠️ 2026-10-16 起它**不再自己画灰条**（NATIVE-MIGRATION P1）
///
/// 从前的做法是"照着 `RepoCard` 抄一份几何、用 `SkeletonBar` 画灰条"，
/// 代价就是 §8.5 第 1 条那条纪律（"尺寸必须匹配真实布局"）根本**守不住** ——
/// 它没有断言可守，只能靠"两个文件挨着放、改的时候记得一起改"。
///
/// 现在换成 SwiftUI 的官方占位方案：**渲染真实布局 + `.redacted(reason: .placeholder)`**
/// ⇒ 第二份几何不存在了，"骨架与真实卡片失配"这件事在结构上不可能发生。
/// 灰块的形状、圆角、配色、呼吸节奏**全部交给系统**（也顺带自动响应
/// 「降低动态效果」与「增强对比度」，自绘版要手工做）。
///
/// 于是本文件剩下的只有"画几行"这一件事 —— 也因此它**仍然挨着 `RepoCard`**：
/// 这一层（行数、卡间距）还是要跟着列表改。
struct RepoCardSkeleton: View {

    /// 每张卡片的占位行数。默认 4 行（一屏多一点）。
    var rows: Int = 4

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<rows, id: \.self) { _ in
                RepoCard(repository: .placeholder)
            }
        }
        // ⚠️ 占位块是**装饰**：读屏该听到的是"正在加载"（由页面那层的
        // `accessibility` 处理），不是把四行假仓库名念一遍。
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

#Preview {
    RepoCardSkeleton()
        .padding(Theme.Spacing.page)
        .background(Theme.Palette.background)
}
