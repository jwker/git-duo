import SwiftUI

/// 设计令牌 —— 颜色 / 字号 / 间距 / 圆角的**唯一定义处**。
///
/// 依据：TECH_SPEC §10.7。
/// 铁律：
/// 1. 业务代码**禁止写魔法值**（颜色、字号、间距、圆角一律引用本文件的令牌）。
/// 2. 令牌按**用途**命名，不按色相命名（禁 `gray600` / `blue500` 这类）。
/// 3. 色值**只在 `light` 一处定义**：本期只交付浅色；将来补深色时只需增加一份映射，不必逐页返工。
/// 4. ⚠️ Liquid Glass 深浅色的 tint 混合比例不同（浅 ≈30% / 深 ≈50%，§10.4 #4），
///    因此**玻璃着色值也必须走令牌**（`glassTint`），不得内联色值。
public enum Theme {

    // MARK: - 颜色（浅色为唯一实现，取值与原型 `redesign/prototype/styles/01-base.css` 的 `:root` 一致）

    public enum Palette {
        public static let background      = Color(hex: 0xF6F8FA)
        public static let surface         = Color(hex: 0xFFFFFF)
        public static let surfaceRaised   = Color(hex: 0xFFFFFF)
        public static let surfaceSunken   = Color(hex: 0xEFF2F5)
        public static let border          = Color(hex: 0xD0D7DE)
        public static let borderSoft      = Color(hex: 0xE8ECEF)

        public static let textPrimary     = Color(hex: 0x1F2328)
        public static let textSecondary   = Color(hex: 0x656D76)
        public static let textTertiary    = Color(hex: 0x8B949E)

        public static let accent          = Color(hex: 0x0969DA)   // 链接 / 强调
        public static let accentStrong    = Color(hex: 0x1F883D)   // 主按钮（GitHub 绿）
        public static let destructive     = Color(hex: 0xCF222E)   // 危险操作（删除 / 退出登录）

        /// 状态色沿用 GitHub 语义（PRD §1 / §10.7 一致口径）：
        /// 开放 = 绿 · 已合并 = 紫 · 已关闭 = 红 · 已发布 = 紫
        /// ⚠️ 已合并与已发布**有意同色**——它们同属"完成 / 发布"紫族，
        /// 靠**文案与图标**区分而非颜色（GitHub 网页端同样如此）。改色前先读 ThemeTests 的不变式。
        public static let stateOpen       = Color(hex: 0x1A7F37)   // 开放 = 绿
        public static let stateMerged     = Color(hex: 0x8250DF)   // 已合并 = 紫
        public static let stateReleased   = Color(hex: 0x8250DF)   // 已发布 = 紫（与 merged 同色，见上）
        public static let stateClosed     = Color(hex: 0xCF222E)   // 已关闭 / 未合并 = 红

        /// diff 行底色 / 文字色
        public static let diffAddedSurface   = Color(hex: 0xDAFBE1)
        public static let diffAddedText      = Color(hex: 0x116329)
        public static let diffDeletedSurface = Color(hex: 0xFFEBE9)
        public static let diffDeletedText    = Color(hex: 0xCF222E)

        /// 玻璃着色值（浅色约 30% 混合 —— §10.4 #4）
        public static let glassTint       = Color(hex: 0xFFFFFF).opacity(0.30)
    }

    // MARK: - 间距（4pt 基准）

    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat  = 4
        public static let s: CGFloat   = 8
        public static let m: CGFloat   = 12
        public static let l: CGFloat   = 16
        public static let xl: CGFloat  = 24
        public static let xxl: CGFloat = 32
        /// 页面左右安全边距
        public static let page: CGFloat = 16
    }

    // MARK: - 圆角

    public enum Radius {
        public static let chip: CGFloat  = 6
        public static let card: CGFloat  = 10
        public static let sheet: CGFloat = 14
        /// 与容器同心（Liquid Glass 推荐，§10.3）
        public static let container: CGFloat = 12
    }

    // MARK: - 字号（沿用系统 Dynamic Type 语义层级，不自造点数）

    public enum Font {
        public static let caption     = SwiftUI.Font.caption2
        public static let footnote    = SwiftUI.Font.footnote
        public static let body        = SwiftUI.Font.body
        public static let bodyStrong  = SwiftUI.Font.body.weight(.semibold)
        public static let headline    = SwiftUI.Font.headline
        public static let title       = SwiftUI.Font.title3.weight(.semibold)
        public static let largeTitle  = SwiftUI.Font.largeTitle.weight(.bold)
        /// 代码 / diff / 提交哈希
        public static let monospaced  = SwiftUI.Font.system(.footnote, design: .monospaced)
    }
}

/// 十六进制色值 → `Color`，**仅供 `GitDuoDesign` 内部的令牌定义使用**
/// （`Theme` 与 `LanguageColor` 都要用它，故不再是 `private`）。
///
/// ⚠️ 它**不是 `public`**：业务代码拿不到它，也就写不出内联色值 ——
///    这正是"颜色必须走语义令牌"（§10.7）在类型系统上的那道防线。
extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
