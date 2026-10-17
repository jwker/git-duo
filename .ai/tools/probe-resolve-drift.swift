// 探针：同一个十六进制色值，经 `Color(nsColor: NSColor(name:)…)` 与 `Color(.sRGB, …)` 两条路
// resolve 出来的分量**是否逐位相同**。
//
// 跑法：`swift .ai/tools/probe-resolve-drift.swift`（macOS 宿主机，用到 AppKit）
// 已观测输出（2026-10-15）：8 个色值里有的 `equal=Y`、有的 `equal=N` —— 不等的那几档只差
//   **Float32 最低有效位**（形如 `…82829 vs …82283`），是否漂取决于具体数值。
// 结论落点：`GitDuoDesignTests/ColorResolve.swift:37-48` —— 相等断言不能用精确相等，容差取半格 `0.5 / 255`。
// ⚠️ 独立脚本，不参与任何 target 构建。

import SwiftUI
import AppKit

func nsColor(hex: UInt32, alpha: Double) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha))
}

let hexes: [UInt32] = [0x0A3069, 0x6E7781, 0x116329, 0x40C463, 0x216E39, 0x30A14E, 0xCF222E, 0xEBEDF0]
for hex in hexes {
    let dynamic = Color(nsColor: NSColor(name: nil) { _ in nsColor(hex: hex, alpha: 1) })
    let plain = Color(.sRGB,
                      red: Double((hex >> 16) & 0xFF) / 255,
                      green: Double((hex >> 8) & 0xFF) / 255,
                      blue: Double(hex & 0xFF) / 255,
                      opacity: 1)
    let env = EnvironmentValues()
    let a = dynamic.resolve(in: env)
    let b = plain.resolve(in: env)
    let eq = a.red == b.red && a.green == b.green && a.blue == b.blue && a.opacity == b.opacity
    print(String(format: "%06X dyn=(%.10f, %.10f, %.10f) plain=(%.10f, %.10f, %.10f) equal=%@",
                 hex, a.red, a.green, a.blue, b.red, b.green, b.blue, eq ? "Y" : "N"))
}
