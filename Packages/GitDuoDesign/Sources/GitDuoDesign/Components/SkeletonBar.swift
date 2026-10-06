import SwiftUI

/// 骨架块 —— 首屏加载时的占位条（TECH_SPEC §8.5）。
///
/// ## 三条纪律（§8.5 明写）
///
/// 1. **尺寸必须匹配真实布局** —— 否则数据到达时整屏跳动。所以这里只提供"一条占位块"，
///    具体的长宽由各 Feature **照着它旁边那个真实组件**写（例如 `RepoCardSkeleton`
///    就挨着 `RepoCard`）。把卡片形状收进本类型，等于把业务布局搬进设计包，
///    而且真卡片的间距一改，骨架就会悄悄失配。
/// 2. **骨架屏属内容层 ⇒ 只用实色，绝不加 Liquid Glass**（§10.2）。
/// 3. **响应「降低动态效果」** —— 见 `animates(reduceMotion:)`。
public struct SkeletonBar: View {

    public let height: CGFloat
    /// `nil` 表示撑满可用宽度（列表行常见）。
    public let width: CGFloat?
    public let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    public init(height: CGFloat, width: CGFloat? = nil, cornerRadius: CGFloat = Theme.Radius.chip) {
        self.height = height
        self.width = width
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.Palette.surfaceSunken)
            .frame(width: width, height: height)
            .opacity(opacity)
            .onAppear(perform: startBreathingIfAllowed)
            .accessibilityHidden(true)   // 装饰性：读屏该听到的是"正在加载"，不是一排空块
    }

    /// 是否播放呼吸动画。**纯函数** —— 这样"设置里开了降低动态效果"这件事
    /// 可以被单测钉住，而不是只能靠肉眼。
    ///
    /// `nonisolated`：它不碰任何 UI 状态，而 `View` 的成员默认继承主 actor 隔离 ——
    /// 不标的话，测试里调用它会得到一条 actor 隔离告警（那条告警本身无害，
    /// 但它会训练人忽略告警，而下一个真告警就不会被看见了）。
    public nonisolated static func animates(reduceMotion: Bool) -> Bool { !reduceMotion }

    private var opacity: Double {
        guard Self.animates(reduceMotion: reduceMotion) else { return 1 }
        return isDimmed ? 0.55 : 1
    }

    private func startBreathingIfAllowed() {
        guard Self.animates(reduceMotion: reduceMotion) else { return }
        // 轻微呼吸：幅度小（1 → 0.55）、周期近 1 秒。再大就像页面在闪。
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            isDimmed = true
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
        SkeletonBar(height: 14, width: 180)
        SkeletonBar(height: 12)
        SkeletonBar(height: 12, width: 120)
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
