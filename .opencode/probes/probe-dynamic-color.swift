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


