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
