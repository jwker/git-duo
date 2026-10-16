import SwiftUI
import Testing

@testable import GitDuoDesign

/// 语言色查表（PRD §3.1「语言色」）。
@Suite("LanguageColor · 查表与回退")
struct LanguageColorTests {

    @Test(
        "常见语言命中，且色值与 GitHub 网页端一致",
        arguments: [
            ("Swift", UInt32(0xF05138)),
            ("Rust", 0xDEA584),
            ("JavaScript", 0xF1E05A),
            ("TypeScript", 0x3178C6),
            ("Python", 0x3572A5),
            ("Go", 0x00ADD8),
            ("Markdown", 0x519ABA)
        ]
    )
    func knownLanguagesResolve(_ language: String, _ expected: UInt32) {
        #expect(LanguageColor.hex(for: language) == expected)
    }

    @Test("查表与大小写、首尾空白无关 —— 否则 `swift ` 会悄悄退化成灰点")
    func lookupIsNormalized() {
        let expected = LanguageColor.hex(for: "Swift")

        #expect(LanguageColor.hex(for: "swift") == expected)
        #expect(LanguageColor.hex(for: "SWIFT") == expected)
        #expect(LanguageColor.hex(for: "  Swift \n") == expected)
    }

    @Test("`nil` / 空串 / 未知语言一律回退到中性灰（不猜一个颜色出来）")
    func unknownFallsBack() {
        #expect(LanguageColor.hex(for: nil) == nil)
        #expect(LanguageColor.hex(for: "") == nil)
        #expect(LanguageColor.hex(for: "   ") == nil)
        #expect(LanguageColor.hex(for: "Brainfuck") == nil)

        #expect(LanguageColor.color(for: nil) == Theme.Palette.textTertiary)
        #expect(LanguageColor.color(for: "Brainfuck") == Theme.Palette.textTertiary)
    }

    @Test("回退色**复用已有语义令牌**，不是新写一个十六进制")
    func fallbackReusesToken() {
        // 理由：将来补深色时只需补一份令牌映射；回退色若自成一个字面量，那一处必然被漏掉。
        #expect(LanguageColor.fallback == Theme.Palette.textTertiary)
    }

    @Test("有语言时**不**返回回退色（否则界面上所有色点都会是灰的，且没有任何报错）")
    func knownLanguageIsNotFallback() {
        #expect(LanguageColor.color(for: "Swift") != LanguageColor.fallback)
    }
}
