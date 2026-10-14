import Foundation
import Testing

@testable import GitDuoKit

/// shields.io 徽章的解析（2026-10-14 新增，`REVIEW-CHECKLIST` **第 65 条**）。
///
/// ## 这批用例在守什么
///
/// 徽章是**唯一一条"不取字节就能画出来"的路** —— 它的全部内容都在地址里。
/// 而它错了的样子**全都不报错**：
///
/// | 写错了的地方 | 屏幕上的表现 | 像什么 |
/// |---|---|---|
/// | 不认 `--` 转义 | `MIT OR Apache-2.0` 被切成两段、丢一半 | 像作者写错了 |
/// | 只剩一段时当成 label + message | 两段一模一样的文字 | 像作者写重了 |
/// | 色名表漏一项 | 那一段不算颜色 ⇒ 颜色名当正文显示 | 像 shields 换了规则 |
/// | 动态徽章也硬解 | 地址解不出内容却硬画一个空标签 | 像图坏了 |
/// | 别的徽章服务也认 | 解析出**错的内容** | 最糟的一种：看着像对的 |
///
/// ⚠️ 最后一条是这批用例里最该留着的：**宁可回落成一张普通的图，也别画错**。
///
/// 用例里的地址全部是 **`storytold/pdfcraft` 那份 README 上的真实地址**
/// （用户 2026-10-14 报回时贴的那一份），不是编的。
@Suite("Markdown 徽章 · shields.io 地址解析")
struct MarkdownBadgeTests {

    private func parse(_ url: String, alt: String = "") throws -> MarkdownBadge {
        let parsed = try #require(URL(string: url))
        return try #require(MarkdownBadge.parse(url: parsed, alt: alt))
    }

    // MARK: - 静态徽章（地址里写着全部内容）

    @Test("`badge/license-MIT OR Apache--2.0-12a58a` ⇒ 三段各归其位（`--` 是一个字面横线）")
    func staticBadgeWithEscapedHyphen() throws {
        let badge = try parse(
            "https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-12a58a"
        )
        #expect(badge.label == "license")
        #expect(badge.message == "MIT OR Apache-2.0")
        #expect(badge.color == MarkdownBadgeColor(parsing: "12a58a"))
        #expect(badge.isFromAddress)
        #expect(badge.style == .flat)
    }

    @Test("`badge/written in-Rust-0a7563` ⇒ label 里的空格（`%20`）解得开")
    func staticBadgeWithSpaceInLabel() throws {
        let badge = try parse("https://img.shields.io/badge/written%20in-Rust-0a7563")
        #expect(badge.label == "written in")
        #expect(badge.message == "Rust")
        #expect(badge.color == MarkdownBadgeColor(parsing: "0a7563"))
    }

    @Test("中间那一段里的 `·`（`%C2%B7`）解出来是原文，不被当成分隔符")
    func staticBadgeWithMiddleDot() throws {
        let badge = try parse(
            "https://img.shields.io/badge/runs%20on-macOS%20%C2%B7%20Windows%20%C2%B7%20Linux%20%C2%B7%20FreeBSD%20%C2%B7%20web-12a58a"
        )
        #expect(badge.label == "runs on")
        #expect(badge.message == "macOS · Windows · Linux · FreeBSD · web")
    }

    @Test("`badge/no account-no telemetry-0a7563` ⇒ 两个空格段各归其位")
    func staticBadgeWithTwoSpaceParts() throws {
        let badge = try parse("https://img.shields.io/badge/no%20account-no%20telemetry-0a7563")
        #expect(badge.label == "no account")
        #expect(badge.message == "no telemetry")
    }

    @Test("⚠️ 剥掉颜色后**只剩一段** ⇒ 它是 message，label 为 `nil`（不是「两段同值」）")
    func singleSegmentHasNoLabel() throws {
        let badge = try parse(
            "https://img.shields.io/badge/Join%20us%20on%20Discord-5865F2?style=for-the-badge&logo=discord&logoColor=white"
        )
        #expect(badge.label == nil)
        #expect(badge.message == "Join us on Discord")
        #expect(badge.color == MarkdownBadgeColor(parsing: "5865F2"))
        #expect(badge.style == .forTheBadge)
    }

    @Test("`.svg` 后缀不参与解析（`badge/foo-bar-green.svg` 与不带后缀等价）")
    func svgSuffixIsStripped() throws {
        let withSuffix = try parse("https://img.shields.io/badge/foo-bar-green.svg")
        let without = try parse("https://img.shields.io/badge/foo-bar-green")
        #expect(withSuffix == without)
    }

    // MARK: - 颜色

    @Test("色名能解出颜色（表照 `badge-maker` 的 `namedColors` 抄）")
    func namedColors() {
        #expect(MarkdownBadgeColor(parsing: "green") == MarkdownBadgeColor(parsing: "67ac09"))
        #expect(MarkdownBadgeColor(parsing: "red") == MarkdownBadgeColor(parsing: "dd4343"))
        #expect(MarkdownBadgeColor(parsing: "blue") == MarkdownBadgeColor(parsing: "007ec6"))
        // ⚠️ `brightgreen` 在 shields 里写的是 3 位（`#4b0`）⇒ 展开成 `#44bb00`。
        #expect(MarkdownBadgeColor(parsing: "brightgreen") == MarkdownBadgeColor(parsing: "44bb00"))
    }

    @Test("语义别名与它指向的基础色是同一个值（`success` → `brightgreen`、`critical` → `red`）")
    func aliasesResolveToTheSameColor() {
        #expect(MarkdownBadgeColor(parsing: "success") == MarkdownBadgeColor(parsing: "brightgreen"))
        #expect(MarkdownBadgeColor(parsing: "critical") == MarkdownBadgeColor(parsing: "red"))
        #expect(MarkdownBadgeColor(parsing: "important") == MarkdownBadgeColor(parsing: "orange"))
        #expect(MarkdownBadgeColor(parsing: "informational") == MarkdownBadgeColor(parsing: "blue"))
        #expect(MarkdownBadgeColor(parsing: "inactive") == MarkdownBadgeColor(parsing: "lightgrey"))
        #expect(MarkdownBadgeColor(parsing: "gray") == MarkdownBadgeColor(parsing: "grey"))
        #expect(MarkdownBadgeColor(parsing: "lightgray") == MarkdownBadgeColor(parsing: "lightgrey"))
    }

    @Test("hex 大小写不敏感、可带 `#`（shields 的路径上不带，但作者手写时常带上）")
    func hexIsCaseInsensitive() {
        #expect(MarkdownBadgeColor(parsing: "FF69B4") == MarkdownBadgeColor(parsing: "ff69b4"))
        #expect(MarkdownBadgeColor(parsing: "#ff69b4") == MarkdownBadgeColor(parsing: "ff69b4"))
        #expect(MarkdownBadgeColor(parsing: "#f6b") == MarkdownBadgeColor(parsing: "ff66bb"))
    }

    @Test("⚠️ 位数只认 3 / 6 —— `1234` 不是颜色（否则它会从 message 里被吃掉）")
    func onlyThreeOrSixDigitsAreColors() {
        #expect(MarkdownBadgeColor(parsing: "1234") == nil)
        #expect(MarkdownBadgeColor(parsing: "12345") == nil)
        #expect(MarkdownBadgeColor(parsing: "12345678") == nil)
        // ⚠️ 表里没有的色名同样判否 —— 宁可显示成文字，也别猜一个色。
        #expect(MarkdownBadgeColor(parsing: "chartreuse") == nil)
    }

    @Test("深色底配白字、浅色底配深字（阈值 0.69 照 shields）")
    func textContrast() throws {
        // ⚠️ 注意哪一头是哪儿：shields 上**连黄色徽章都是白字**
        //    （`#d8b800` 的加权亮度 0.677，刚好压在 0.69 之下）——
        //    这条断言正是为"别凭直觉把黄色归到浅色那一头"写的。
        let dark = try #require(MarkdownBadgeColor(parsing: "12a58a"))
        let yellow = try #require(MarkdownBadgeColor(parsing: "d8b800"))
        let pale = try #require(MarkdownBadgeColor(parsing: "eeeeee"))
        #expect(dark.prefersDarkText == false)
        #expect(yellow.prefersDarkText == false)
        #expect(pale.prefersDarkText == true)
    }

    // MARK: - 动态徽章（地址里没有内容）

    @Test("⚠️ 动态徽章用 `alt` 兜底 ⇒ 画成中性灰标签，且 `isFromAddress` 为假")
    func computedBadgeFallsBackToAlt() throws {
        let badge = try parse("https://img.shields.io/github/stars/storytold/pdfcraft", alt: "GitHub stars")
        #expect(badge.label == nil)
        #expect(badge.message == "GitHub stars")
        // ⚠️ 颜色为 `nil` ⇒ 视图用中性灰 —— 别让一句**描述**看起来像真数据。
        #expect(badge.color == nil)
        #expect(badge.isFromAddress == false)
    }

    @Test("⚠️ 动态徽章且 `alt` 也是空的 ⇒ 整条判否（回落成一张普通的图）")
    func computedBadgeWithoutAltIsRejected() throws {
        let url = try #require(URL(string: "https://img.shields.io/github/stars/a/b"))
        #expect(MarkdownBadge.parse(url: url, alt: "") == nil)
        #expect(MarkdownBadge.parse(url: url, alt: "   ") == nil)
    }

    // MARK: - 不该认的

    @Test("⚠️ 别的 host 一律不认 —— 地址规则不同，硬解出来的是**错的内容**")
    func otherHostsAreRejected() throws {
        for address in [
            "https://badgen.net/badge/icon/github",
            "https://img.shields.io.example.com/badge/a-b-green",
            "https://example.com/badge/a-b-green",
        ] {
            let url = try #require(URL(string: address))
            #expect(MarkdownBadge.parse(url: url, alt: "x") == nil, "不该认：\(address)")
        }
    }

    @Test("shields.io 上但路径不是 `/badge/` 的，走动态那一档（不是硬解）")
    func nonBadgePathsAreComputed() throws {
        let badge = try parse("https://img.shields.io/npm/v/react", alt: "npm")
        #expect(badge.isFromAddress == false)
        #expect(badge.message == "npm")
    }

    @Test("`/badge/` 后面是空的 ⇒ 判否")
    func emptyBadgePathIsRejected() throws {
        let url = try #require(URL(string: "https://img.shields.io/badge/"))
        #expect(MarkdownBadge.parse(url: url, alt: "") == nil)
    }

    // MARK: - 可选参数

    @Test("`?color=` 覆盖路径末段那个颜色（末段照旧被剥掉，不留在 message 里）")
    func queryColorWins() throws {
        let badge = try parse("https://img.shields.io/badge/foo-bar-green?color=blue")
        #expect(badge.color == MarkdownBadgeColor(parsing: "blue"))
        #expect(badge.label == "foo")
        #expect(badge.message == "bar")
    }

    @Test("`?labelColor=` 只换左半段底色，不动右半段")
    func labelColorIsSeparate() throws {
        let badge = try parse("https://img.shields.io/badge/foo-bar-green?labelColor=red")
        #expect(badge.labelColor == MarkdownBadgeColor(parsing: "red"))
        #expect(badge.color == MarkdownBadgeColor(parsing: "green"))
    }

    @Test("四个外观档都认得出来，认不出来的落到默认")
    func styles() throws {
        #expect(try parse("https://img.shields.io/badge/a-b-green?style=flat-square").style == .flatSquare)
        #expect(try parse("https://img.shields.io/badge/a-b-green?style=for-the-badge").style == .forTheBadge)
        #expect(try parse("https://img.shields.io/badge/a-b-green?style=plastic").style == .plastic)
        #expect(try parse("https://img.shields.io/badge/a-b-green?style=social").style == .social)
        #expect(try parse("https://img.shields.io/badge/a-b-green").style == .flat)
        #expect(try parse("https://img.shields.io/badge/a-b-green?style=unknown").style == .flat)
    }

    @Test("作者没写颜色 ⇒ 用 shields 的默认（`lightgrey`），而不是没有颜色")
    func defaultColorWhenAbsent() throws {
        let badge = try parse("https://img.shields.io/badge/foo-bar")
        #expect(badge.color == MarkdownBadgeColor(parsing: "lightgrey"))
        #expect(badge.labelColor == MarkdownBadgeColor(parsing: "grey"))
    }

    @Test("`_` 也是空格（shields 的另一种写法，与 `%20` 等价）")
    func underscoreIsSpace() throws {
        let badge = try parse("https://img.shields.io/badge/written_in-Rust-green")
        #expect(badge.label == "written in")
    }
}
