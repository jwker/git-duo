import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 仓库列表的首屏骨架（TECH_SPEC §8.5）。
///
/// ## ⚠️ 2026-10-16 起它是**行**，不是一个 `VStack`（NATIVE-MIGRATION P3）
///
/// P1 把它从"自绘灰条"改成"真实的 `RepoCard` + `.redacted`"；P3 把主干换成 `List`
/// 之后，**一行就是一个 `List` 行**，本件只负责把 N 行吐出去 —— 行间距（10）与卡面
/// 由 `List` 给。同 `PinRowsSkeleton`。
///
/// ## ⚠️ 2026-10-16（P1）它不再自己画灰条
///
/// 从前的做法是"照着 `RepoCard` 抄一份几何、用自绘的 `SkeletonBar` 画灰条"（那个件已随 P1 删除），
/// 代价就是 §8.5 第 1 条那条纪律（"尺寸必须匹配真实布局"）根本**守不住** ——
/// 它没有断言可守，只能靠"两个文件挨着放、改的时候记得一起改"。
///
/// 现在换成 SwiftUI 的官方占位方案：**渲染真实布局 + `.redacted(reason: .placeholder)`**
/// ⇒ 第二份几何不存在了，"骨架与真实卡片失配"这件事在结构上不可能发生。
///
/// ## ⚠️ 两条实证（2026-10-16，宿主机 `NSHostingView` 探针，P3 时补测）
///
/// 1. **`body` 是 `ForEach` 的自定义 `View`，放进 `List` 会被摊成多行**
///    （4 行 ⇒ 4 个 `ListTableRowView`，与"`ForEach` 直写在 `List` 里"逐个一致）。
///    ⇒ 本件可以继续是"一个吐 N 行的件"，不必把 `ForEach` 抄到每个调用点。
/// 2. **在这种包装件上挂行修饰符（`.redacted` / `.listRowBackground`）不会破坏摊平**
///    （三种形态行数都是 4）。
struct RepoCardSkeleton: View {

    /// 每张卡片的占位行数。默认 4 行（一屏多一点）。
    var rows: Int = 4

    var body: some View {
        ForEach(0..<rows, id: \.self) { _ in
            RepoCard(repository: .placeholder)
        }
        // ⚠️ 占位块是**装饰**：读屏该听到的是"正在加载"（由页面那层的
        // `accessibility` 处理），不是把四行假仓库名念一遍。
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

#Preview {
    List {
        RepoCardSkeleton()
    }
}
