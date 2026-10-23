import SwiftUI

/// **全局悬浮按钮** —— 圆形玻璃钮，浮在内容之上（2026-10-23 定：「上传图片」入口）。
///
/// ## 尺寸与形状
///
/// - 直径 **56 pt**（`Theme.Spacing` 之外的那个数，是这件自己的尺寸，**不是间距令牌**）；
/// - 圆形（圆角 = 半径），不用胶囊 —— 圆形让"浮在上面"这件事一眼可辨；
/// - 图标 22 pt，衬在按钮正中。
///
/// ## ⚠️ 为什么它**带玻璃**（而 `ActionButton` 不带）
///
/// 仓库的口径是「玻璃只属导航层，**绝不用在内容层**」（列表行 / 卡片 / 正文 / 图片）。
/// 这颗按钮是**悬浮层**：它浮在内容之上、不承载正文、点开是一张弹层 ——
/// 与 `Toast`（同为悬浮层、§8.4 允许带材质感）同一类。
/// 而 `ActionButton` 是**内容层**里的按钮（弹层表单里、页脚里）⇒ 它不带玻璃。
///
/// ## ⚠️ 玻璃着色必须走令牌
///
/// `Theme.Palette.glassTint`（浅色 30% / 深色 50% —— §10.4 #4）
/// —— 玻璃在深浅两档的 tint 混合比例不同，写死色值会让深色档发灰。
///
/// ## ⚠️ 命中区
///
/// 视觉 56 pt，命中区**外扩到 64 pt**（`hitAreaExpansion`）——
/// 视觉尺寸不等于命中尺寸，而悬浮按钮通常单手够，命中区小一点就容易按空。
public struct FloatingActionButton: View {

    /// 视觉直径。
    public static let diameter: CGFloat = 56

    /// 命中区外扩后的大小（比视觉大一圈，透明的部分照样可点）。
    public static let hitArea: CGFloat = 64

    /// 图标名（SF Symbol）。
    public let systemImage: String

    /// 读屏标签 —— ⚠️ **不能省**：一颗只有图标的按钮，读屏念不出它是干什么的。
    public let accessibilityLabel: String

    private let action: () -> Void

    public init(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: Self.diameter, height: Self.diameter)
                .contentShape(Circle())
        }
        // ⚠️ `.plain`：系统按钮样式会给 label 套一层自己的底（按下高亮那块），
        //    叠在玻璃上会变成"玻璃里的一块按钮"。
        .buttonStyle(.plain)
        .glassSurface(circle: true)
        // 命中区外扩：外扩的部分**透明**，但照样接点击。
        .frame(width: Self.hitArea, height: Self.hitArea)
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
    }
}

/// 一层薄薄的玻璃 —— **只有这一处**调 `glassEffect`。
///
/// ## ⚠️ 为什么抽出来而不是在按钮里直接写
///
/// ① 铁律 #4：`.glassEffect` **只允许出现在 `GitDuoDesign` 的组件封装内** ——
///    收在一处，App 层就不可能写出一个散落的 `.glassEffect`；
/// ② **macOS 也要编得过**（这个包同时为 macOS 构建，只为在宿主机上跑 `swift test`）——
///    `glassEffect` 是 iOS 26 / macOS 26 才有的 API，而包的 macOS 部署目标是 15.0
///    ⇒ 这里必须留一条降级路径（`.ultraThinMaterial`）。
private extension View {

    /// 玻璃表面。`circle: true` 时是圆形，否则是胶囊（圆角矩形）。
    @ViewBuilder
    func glassSurface(circle: Bool) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            // ⚠️ 两档**分开写**：`.circle` 与 `.capsule` 是两个不同类型，
            //    三元表达式里编译器没法统一它们（会报 "types be equivalent"）。
            if circle {
                self.glassEffect(.regular.tint(Theme.Palette.glassTint), in: .circle)
            } else {
                self.glassEffect(.regular.tint(Theme.Palette.glassTint), in: .capsule)
            }
        } else {
            if circle {
                self.background(.ultraThinMaterial, in: Circle())
            } else {
                self.background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}

#Preview {
    ZStack {
        Theme.Palette.background
        FloatingActionButton(
            systemImage: "photo.badge.plus",
            accessibilityLabel: "上传图片"
        ) {}
    }
}
