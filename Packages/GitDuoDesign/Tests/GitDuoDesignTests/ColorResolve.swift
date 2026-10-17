import SwiftUI

/// 动态色时代的**求值**辅助（2026-10-15 走查第 69 条接通深色后必需）。
///
/// 为什么需要它：`Theme.Palette` 全部令牌双列化后都是动态色，
/// `Color ==` 对动态色比的是**实例身份**（每个令牌各带一个唯一的
/// `#$customDynamic <UUID>`）⇒ 任何**跨实例**的相等 / 互异断言都必须先
/// resolve 成分量再比，否则 `==` 恒假、`!=` 恒真（断言变成空气）。
/// 同一静态令牌与自己比较（如 `row.titleColor == Theme.Palette.textPrimary`）
/// 比的是同一个实例，仍然可靠，不必改。
///
/// 为什么挂 `@MainActor`：macOS 的 `NSColor(name:)` 动态色在非主线程
/// resolve 会死锁（探针实锤，见 `Theme.swift` 抬头）—— `swift test` 跑的是
/// 包的 macOS 变体，所以所有求值都必须在主线程进行。
@MainActor
enum ColorResolve {

    private static func env(_ scheme: ColorScheme) -> EnvironmentValues {
        var e = EnvironmentValues()
        if scheme == .dark { e.colorScheme = .dark }
        return e
    }

    /// 把（可能是动态的）颜色在指定模式下 resolve 成 [R, G, B]（0–1）。
    static func rgb(_ color: Color, _ scheme: ColorScheme) -> [Float] {
        let c = color.resolve(in: env(scheme))
        return [c.red, c.green, c.blue]
    }

    /// 颜色在指定模式下 resolve 出来的 alpha。
    static func alpha(of color: Color, _ scheme: ColorScheme) -> Float {
        color.resolve(in: env(scheme)).opacity
    }

    /// **含 alpha** 的全分量相等 —— 动态色时代 `==` 的替代品。
    ///
    /// ⚠️ 不能用精确相等：macOS 的 `NSColor` resolve 路径与 SwiftUI 直构路径
    /// 在 Float32 最低有效位上**差 1 ulp**（2026-10-15 探针实锤，源码
    /// `.ai/tools/probe-resolve-drift.swift`：同一十六进制
    /// 值两条路 resolve 出 `0.1882352829 vs 0.1882352829` 或 `…82829 vs …82283`
    /// 不等的结果，是否漂取决于具体数值）。容差取半格 8-bit（`0.5 / 255`）——
    /// 色值本就是 8-bit 量纲，量化到 8-bit 后同值即"同值"；真实取错色
    ///（整整差一档）仍会被抓住。动态对动态的比较（两侧同路径）不受影响。
    static func same(_ lhs: Color, _ rhs: Color, _ scheme: ColorScheme) -> Bool {
        let a = lhs.resolve(in: env(scheme))
        let b = rhs.resolve(in: env(scheme))
        let tol = Float(0.5 / 255)
        return abs(a.red - b.red) <= tol && abs(a.green - b.green) <= tol
            && abs(a.blue - b.blue) <= tol && abs(a.opacity - b.opacity) <= tol
    }

    /// `same` 的反义 —— 动态色时代 `!=` 的替代品（两档各钉一次）。
    static func distinct(_ lhs: Color, _ rhs: Color, _ scheme: ColorScheme) -> Bool {
        !same(lhs, rhs, scheme)
    }
}
