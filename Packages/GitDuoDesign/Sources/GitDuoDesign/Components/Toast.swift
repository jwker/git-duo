import SwiftUI

/// 轻提示 —— 深色圆角块，浮在内容之上（TECH_SPEC §8.4、PRD §7「提示」一节）。
///
/// ## 外观逐字取自原型
///
/// ```css
/// /* styles/05-overlays.css:15 */
/// .toast{position:absolute;left:50%;bottom:96px;transform:translateX(-50%);
///        background:rgba(28,32,36,.92);color:#fff;font-size:12.5px;font-weight:600;
///        padding:10px 16px;border-radius:12px;z-index:90;max-width:84%;text-align:center}
/// ```
///
/// ⇒ 底 `toastSurface`（半透明深色）· 字 12pt semibold · 竖 10 / 横 16 · 圆角 12 · 居中。
/// 注意它**不是胶囊**（`border-radius:12px` 是定值，不是 50%）——
/// 一句话会折成两行，胶囊在那种形状下会变成一根两端半圆的怪东西。
///
/// ## 它是「导航 / 系统层」，所以可以用材质
///
/// §10.2 的"内容层必须实色"约束的是**常驻内容**（列表行 / 卡片 / 正文）。
/// Toast 浮在所有内容之上、2.4 秒即走、不承载正文，因此是 §8.4 明确列出的
/// 少数可以带材质感的元素之一。**但这里仍走原型的实色配置** ——
/// `rgba(28,32,36,.92)` 本身就是"半透明深色 + 文字压在上面"，
/// 再叠一层 `glassEffect` 会让它比原型更亮、更糊。
///
/// ## 它不认识"要显示什么"
///
/// 文案由调用方给（各 Feature 的文案都在领域层或各自的常量里）。
/// 本类型只负责画一个块 —— 于是"同一句提示在两个 Tab 里措辞不同"这类事
/// 不可能因为组件而不同。
public struct Toast: View {

    /// 距屏幕底部的距离（原型 `bottom:96px`）。
    ///
    /// 96 是原型机身内的绝对值；本项目里它要落在 **Tab 栏之上**，
    /// 所以保留原值并注明出处，而不是换算成一个"看起来差不多"的魔法数。
    public static let bottomInset: CGFloat = 96

    /// 最大宽度的两侧留白（原型 `max-width:84%` ⇒ 每侧 8%）。
    ///
    /// 用留白而不是百分比：SwiftUI 的 `Text` 会自己按可用宽度折行，
    /// 卡住两侧就等价于卡住了最大宽度（390pt 机身 ⇒ 每侧约 31pt）。
    public static let horizontalInset: CGFloat = 32

    public let message: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        Text(message)
            .font(Theme.Font.label)
            .foregroundStyle(Theme.Palette.toastText)
            .multilineTextAlignment(.center)
            // 10 / 16 是原型原值，4pt 间距阶里没有 10 这一档 —— 写原值并注明出处
            // （与 `SegmentedBar` 的 7/14 同一做法）。
            .padding(.vertical, 10)
            .padding(.horizontal, Theme.Spacing.l)
            .background(Theme.Palette.toastSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous))
            .padding(.horizontal, Self.horizontalInset)
            .padding(.bottom, Self.bottomInset)
            // 读屏：它是一条状态通告，不是可聚焦的内容。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(message)
    }

    /// 进出场是否播动画（原型 `animation:up .25s`）。
    ///
    /// 纯函数（`nonisolated static`，本包那条"reduceMotion 判定可单测"的老规矩）：
    /// 这样"设置里开了降低动态效果"
    /// 可以被单测钉住，而不是只能靠肉眼。
    public nonisolated static func animates(reduceMotion: Bool) -> Bool { !reduceMotion }

    /// 进出场转场。开了降低动态效果时**只留淡入淡出** ——
    /// 一个从底部窜上来的方块对前庭敏感的人是实打实的干扰（§10.5）。
    public nonisolated static func transition(reduceMotion: Bool) -> AnyTransition {
        animates(reduceMotion: reduceMotion)
            ? .move(edge: .bottom).combined(with: .opacity)
            : .opacity
    }

    /// 动画时长（原型 `.25s`）。开降低动态效果时压短。
    public nonisolated static func animation(reduceMotion: Bool) -> Animation {
        .easeOut(duration: animates(reduceMotion: reduceMotion) ? 0.25 : 0.15)
    }
}

#Preview {
    ZStack {
        Theme.Palette.background
        VStack {
            Spacer()
            Toast(message: StarToastPreviewText.short)
            Toast(message: StarToastPreviewText.long)
        }
    }
}

/// 只为预览用的一小撮文案（真文案在各 Feature / 领域层）。
private enum StarToastPreviewText {
    static let short = "已 Star · 公开星标，仓库计数 +1"
    static let long = "结果可能不完整（GitHub 计算超时）· 下拉刷新重试"
}
