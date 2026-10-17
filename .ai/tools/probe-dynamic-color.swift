// 探针：`NSColor(name:)` 动态色在**非主线程** resolve 会不会死锁。
//
// 跑法：`swift .ai/tools/probe-dynamic-color.swift`（macOS 宿主机，用到 AppKit）
// 已观测输出（2026-10-15）：后台线程打出 "resolving…" 后**不再返回**，15 秒后打出 "DEADLOCK (15s)"。
// 结论落点：`GitDuoDesign/Tokens/Theme.swift:718-729`（macOS 变体必须主线程取色；iOS 走 UIColor 不受影响）、
//   `GitDuoDesignTests/ThemeTests.swift:20-26`、`GitDuoDesignTests/ColorResolve.swift:12-14`（两处因此挂 `@MainActor`）。
//   ⚠️ 那两处注释还记了对照结论"主线程毫秒级完成" —— 本探针验的是**后台线程死锁**这一半。
// ⚠️ 独立脚本，不参与任何 target 构建。

import SwiftUI
import AppKit

func dynColor(light: UInt32, dark: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let hex = isDark ? dark : light
        return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                       green: CGFloat((hex >> 8) & 0xFF) / 255,
                       blue: CGFloat(hex & 0xFF) / 255,
                       alpha: 1)
    })
}

let done = DispatchSemaphore(value: 0)
Thread.detachNewThread {
    print("worker thread: \(Thread.current)")   // 用 fflush 强刷
    let c = dynColor(light: 0xF6F8FA, dark: 0x0D1117)
    print("constructed on background"); fflush(stdout)
    var e = EnvironmentValues()
    e.colorScheme = .dark
    print("resolving…"); fflush(stdout)
    let r = c.resolve(in: e)
    print("resolved:", r.red, r.green, r.blue); fflush(stdout)
    done.signal()
}
let ok = done.wait(timeout: .now() + 15)
print(ok == .success ? "OK" : "DEADLOCK (15s)"); fflush(stdout)


