import SwiftUI

/// 菜单组 —— 「我的」页那两组、设置页各分区（含末尾那张**无标题**的）
/// （PRD §4.17 第 4/5 条、§4.20）。
///
/// ## ⚠️ 2026-10-16 起**没有生产调用方**（NATIVE-MIGRATION P3 第二批）
///
/// 它的三个消费者（「我的」根页 / 设置页 / 仓库首页的四行入口）**都已换成 `List`** ——
/// "一组行"这件事现在由 `List` 的 `Section` 表达（卡面、圆角、分隔线全由系统给）。
/// 本件留着只是为了让"这个语义"还在代码里可读，**不要**给它加回分隔线 /
/// `showsSeparator` 这类调用方开关 —— 那正是本件从前出过两次错的地方
/// （2026-10-15 走查第 77 条：线画在顶上，要关的却是"最后一行"）。
///
/// ⚠️ 与 `CardBox` 的分工不变：本件 = "这几行是一组"这一层语义，形状由 `CardBox` 给
/// （`CardBox(vertical: 0, horizontal: 0)`）。`CardBox` 随 P5 令牌收尾退休时本件一并删。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct MenuCard<Content: View>: View {

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        // `CardBox` 内部已经是一个 `spacing: 0` 的 `VStack(alignment: .leading)`，
        // 所以多行会紧贴在一起 —— 那正是 `.menu-item` 之间不要间隙的意思。
        CardBox(vertical: 0, horizontal: 0) {
            content
        }
    }
}
