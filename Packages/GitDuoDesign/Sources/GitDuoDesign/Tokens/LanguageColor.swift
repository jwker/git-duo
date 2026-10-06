import SwiftUI

/// 主语言的品牌色 —— 仓库卡片上的那个小色点（PRD §3.1「语言色」、§4.3 卡片内容）。
///
/// ## 为什么这张表在本项目里是**必需**的
///
/// GitHub 的仓库对象只给一个 `language` 字符串，**不给颜色**，也没有任何接口能取到它 ——
/// 网页端那个色点是 GitHub 自己用 linguist 的词表算的（同一语言名恒定同色）。
/// 所以要么本地维护一张表，要么卡片上永远只有一种灰点。
///
/// 契合 §10.7 的口径：颜色一律走出处明确的来源，不写魔法值 ——
/// 这些色值取自 linguist 的公开词表，逐条写在这里，**未知语言回退中性灰而不是猜一个**。
public enum LanguageColor {

    /// 未知语言 / 未设语言时的颜色。
    ///
    /// 用三级文字灰而不是某个随机彩色：一个空仓库的色点不该看起来像"它有语言"。
    /// 复用已有的语义令牌（而不是再写一个十六进制），免得将来补深色时漏掉这一处。
    public static var fallback: Color { Theme.Palette.textTertiary }

    /// 取主语言色。`nil` 与未知语言都回退到 `fallback`。
    public static func color(for language: String?) -> Color {
        guard let hex = hex(for: language) else { return fallback }
        return Color(hex: hex)
    }

    /// 查表结果；`nil` 表示要回退。internal —— 供测试逐条核对，业务代码不需要它。
    static func hex(for language: String?) -> UInt32? {
        guard let key = normalized(language) else { return nil }
        return table[key]
    }

    /// 归一化：去空白 + 小写。
    /// `language` 由服务端给，但大小写与空格都不该影响查表 ——
    /// 否则 "swift " 会悄悄退化成灰点，而这种缺陷在界面上看起来"只是没颜色"。
    private static func normalized(_ language: String?) -> String? {
        guard let trimmed = language?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed.lowercased()
    }

    /// linguist 词表里的常见语言（色值与 GitHub 网页端一致）。
    private static let table: [String: UInt32] = [
        "swift": 0xF05138,
        "objective-c": 0x438EFF,
        "objective-c++": 0x6866FB,
        "rust": 0xDEA584,
        "javascript": 0xF1E05A,
        "typescript": 0x3178C6,
        "python": 0x3572A5,
        "go": 0x00ADD8,
        "java": 0xB07219,
        "kotlin": 0xA97BFF,
        "ruby": 0x701516,
        "php": 0x4F5D95,
        "c": 0x555555,
        "c++": 0xF34B7D,
        "c#": 0x178600,
        "shell": 0x89E051,
        "bash": 0x89E051,
        "powershell": 0x012456,
        "html": 0xE34C26,
        "css": 0x563D7C,
        "scss": 0xC6538C,
        "vue": 0x41B883,
        "svelte": 0xFF3E00,
        "astro": 0xFF5A03,
        "dart": 0x00B4AB,
        "elixir": 0x6E4A7E,
        "erlang": 0xB83998,
        "haskell": 0x5E5086,
        "ocaml": 0x3BE133,
        "scala": 0xC22D40,
        "clojure": 0xDB5855,
        "lua": 0x000080,
        "perl": 0x0298C3,
        "r": 0x198CE7,
        "julia": 0xA270BA,
        "zig": 0xEC915C,
        "nim": 0xFFC200,
        "crystal": 0x000100,
        "elm": 0x60B5CC,
        "nix": 0x7E7EFF,
        "groovy": 0x4298B8,
        "fortran": 0x4D41B1,
        "sql": 0xE38C00,
        "tex": 0x3D6117,
        "markdown": 0x519ABA,
        "json": 0x292929,
        "yaml": 0xCB171E,
        "toml": 0x9C4221,
        "dockerfile": 0x384D54,
        "makefile": 0x427819,
        "cmake": 0xDA3434,
        "hcl": 0x844FBA,
        "solidity": 0xAA6746,
        "assembly": 0x6E4C13,
        "jupyter notebook": 0xDA5B0B,
        "vim script": 0x199F4B,
        "emacs lisp": 0xC065DB
    ]
}
