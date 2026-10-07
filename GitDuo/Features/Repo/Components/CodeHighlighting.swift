import GitDuoDesign
import GitDuoKit

/// 领域层的**语义类别** → 设计包的**着色档位**的那一次显式翻译（TECH_SPEC §11.3）。
///
/// ## 为什么这层翻译必须存在，而且必须在 App 层
///
/// 两侧都不能认识对方：
/// - `GitDuoDesign` **不得 import 领域层**（依赖铁律）⇒ 设计包里不能出现 `SyntaxTokenKind`；
/// - `GitDuoKit` **不得 import SwiftUI** ⇒ 领域包里不能出现 `CodeTone`（它带颜色）。
///
/// 于是"语义 → 颜色"这件事只能落在 App 层。设计包已经在 `CodeSurface` 的说明里
/// 点名了本文件就是那次翻译的落点。
///
/// ## 为什么"漏一档"不会变成静默错误
///
/// 这里的 `switch` 是**穷尽的**（不带 `default`）⇒ 领域层将来给 `SyntaxTokenKind`
/// 加一档时，**这里编译不过**。App target 没有测试 target，编译期报错是这类
/// 翻译函数唯一可用的守卫（`GitDuoKit` 的 `DiffLine.Kind` → `DiffRow.Tone` 同理，
/// 见 `DiffCard`）。
enum CodeHighlighting {

    /// 一个片段 → 着色档位。
    ///
    /// ⚠️ **`.number` 与 `.type` 两档有意落到 `.plain`（不着色）** ——
    /// 原型只给了四色，那两档**没有颜色**，已登记为「规格未给，待评审」
    /// （论证见 `CodeTone` 与 `Theme.Palette.syntaxKeyword` 的类型说明）。
    /// 从四色里挑一个塞给它们属于自造视觉，而原型是唯一可点验收依据。
    static func tone(_ kind: SyntaxTokenKind) -> CodeTone {
        switch kind {
        case .plain: .plain
        case .keyword: .keyword
        case .string: .string
        case .comment: .comment
        case .function: .function
        // 下面两档**没有**对应颜色，见类型说明。
        case .number, .type: .plain
        }
    }

    /// 一行源码 → 设计包的片段数组。
    ///
    /// ⚠️ 片段拼起来**恒等于原行**这条不变量由 `SyntaxHighlighter` 保证
    /// （它自己有一组"任意输入"用例守着）；这里只是逐段翻译，
    /// **不许**过滤、合并或裁剪任何片段 —— 那会让代码被悄悄改掉。
    static func spans(of line: String, language: CodeLanguage?) -> [CodeSpan] {
        SyntaxHighlighter.tokens(of: line, language: language).map { token in
            CodeSpan(text: token.text, tone: tone(token.kind))
        }
    }

    /// 多行源码 → 设计包的行数组。
    static func lines(_ lines: [String], language: CodeLanguage?) -> [[CodeSpan]] {
        lines.map { spans(of: $0, language: language) }
    }

    /// 代码块 fence 后面那个词 → 认得出的语言（`nil` = 纯文本）。
    ///
    /// ⚠️ 认不出来就是 `nil`、由 `CodeSurface` 走纯文本降级，
    /// **不去猜**（见 `CodeLanguage.named` 的说明：按错的规则着色
    /// 比不着色更让人怀疑内容本身）。
    static func language(_ info: String?) -> CodeLanguage? {
        CodeLanguage.named(info)
    }
}
