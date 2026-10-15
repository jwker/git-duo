import SwiftUI

/// 一段代码的**着色档位** —— 语法类别 → 颜色的那一半（TECH_SPEC §11.3）。
///
/// ## ⚠️ 为什么领域层的 `SyntaxTokenKind` 不能直接用
///
/// 领域层（`GitDuoKit`）的 `SyntaxTokenKind` 有七档，但那是**语义**类别；
/// 而颜色是排版决定（会随主题变：本期只做浅色，将来要补深色）。
/// 设计包**不得依赖领域层**（依赖铁律），所以这里另立一个**只谈颜色**的枚举，
/// 由 App 层做一次显式翻译（`GitDuo/Features/Repo/Components/CodeHighlighting.swift`）。
/// 与 `StatusPill.Tone`、`DiffRow.Tone` 是同一条纪律。
///
/// ## ⚠️ 只有五档，而领域层有七档
///
/// 原型只给了四色（关键字 / 函数名 / 字符串 / 注释），
/// `number`（数字）与 `type`（类型名）**原型里没有颜色** ⇒ 它们落到 `.plain`（不着色）。
/// 这是「规格未给，待评审」的一条，**不是**遗漏：
/// 从四色里挑一个塞给数字会让代码看起来"颜色怪怪的"，而原型是唯一可点验收依据。
public enum CodeTone: Sendable, Hashable, CaseIterable {

    /// 不着色 —— 普通文字，也是 `number` / `type` 两档的落点。
    case plain

    /// 关键字（原型 `.kw`）。
    case keyword

    /// 字符串字面量（原型 `.st`）。
    case string

    /// 注释（原型 `.cm`）。
    case comment

    /// 函数 / 方法名（原型 `.fn`）。
    case function
}

/// 一段**带档位的代码文字**。
///
/// `text` 拼接起来必须等于原行 —— 这条不变量由领域层的 `SyntaxToken` 保证
/// （那里有同样的说明：着色器吞掉一个字符，用户照着抄就会抄到不存在的源码）。
public struct CodeSpan: Sendable, Hashable {

    public let text: String

    public let tone: CodeTone

    public init(text: String, tone: CodeTone = .plain) {
        self.text = text
        self.tone = tone
    }
}

/// **代码面** —— 一块等宽、实色、可横向滚动的代码（原型 `styles/04-screens.css`）。
///
/// ```css
/// /* 2026-10-15 走查第 75 条：面板去掉之后，代码块垫**浅灰面**（白块在白底上没有形状） */
/// .markdown pre{background:var(--chip);border:none;
///               border-radius:9px;padding:11px 13px;overflow-x:auto}
/// .markdown pre code{background:none;padding:0;font-size:12px;line-height:1.55}
/// ```
///
/// ## ⚠️ 底色由调用方给，不能写死（2026-10-15 走查第 75 条）
///
/// 同一段代码块会坐在**两种不同的底**上，而它们要的形状信号是**相反**的：
///
/// | 坐在哪 | 底 | 代码块该垫 |
/// |---|---|---|
/// | 页面 / 弹层（正文档、文件页源码、弹层里的源码） | `background`（浅白 / 深 `0x0D1117`） | **面板色** `surfaceSunken`（浅 `0xEFF2F5` / 深 `0x161B22`） |
/// | 评论气泡（`.compact`） | `surfaceSunken` | `markdownPreSurface`（浅白 / 深 `0x0D1117` —— 比气泡亮 / 暗一档） |
///
/// ⚠️ 方案 D 那一批把它写死成"白块"（那时它只出现在灰面板里）⇒ **文件页的源码块与
/// 提交弹层的代码块坐在页面 / 弹层底上，白块等于没有形状**（浅色白贴白、深色与页面同色）。
/// 那两处不在面板里，是同一批"未目视"漏掉的 ⇒ 本条一并修回。
///
/// ## ⚠️ 横向滚动是**要点**，不是顺手加的
///
/// 代码行不能折行（折行会让缩进层次看不出来，而缩进是读代码的第一信息）。
/// 所以：外层 `ScrollView(.horizontal)` + 内层 `fixedSize(horizontal:)`
/// 让文字**保持一行**、由滚动去看右边。原型用 `overflow-x:auto` 表达同一件事。
///
/// ## ⚠️ 行距：一个 `Text` 装全部行，不是一行一个 `Text`
///
/// 两种写法的差别不只是性能：
/// - 一个 `Text` 装 `\n` 分隔的全部行 ⇒ 行距由 `.lineSpacing` 统一控制，
///   且**整块内容是一个文本对象**（未来若要支持"复制原始代码"就能一次拿走）；
/// - 一行一个 `Text` 摆进 `VStack` ⇒ 行距要靠 `VStack(spacing:)` 凑，
///   而那个值同时管着"行与行"和"最后一行与内边距"，调一处会动两处。
///
/// 原型 `line-height:1.55`：12pt 字下系统默认行高约 1.2（≈14.4pt），
/// 差额 ≈4pt ⇒ 取 4pt 阶里的 `Spacing.xs`（不写裸数字，避免"魔法值"）。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2 点名"代码块"）。
public struct CodeSurface: View {

    /// 每一行由若干 `CodeSpan` 组成（顺序即绘制顺序）。
    public let lines: [[CodeSpan]]

    /// 代码块的**底色**。默认 `surfaceSunken`（"面板"那一档 —— 坐在页面 / 弹层底上时成立）。
    ///
    /// ⚠️ 为什么它是参数而不是写死：见类型说明那张表 —— 评论气泡里那段要的是
    /// `markdownPreSurface`（白，垫在灰气泡上），方向正好相反。
    public let fill: Color

    public init(lines: [[CodeSpan]], fill: Color = Theme.Palette.surfaceSunken) {
        self.lines = lines
        self.fill = fill
    }

    /// 无着色的纯文本：按 `\n` 拆行，每行一段 `.plain`。
    ///
    /// 给"语言认不出来 ⇒ 降级为纯文本"（§11.3）与"还没着色就先显示内容"两处用。
    /// ⚠️ 尾部那个由"以换行结尾"产生的空串**会被去掉** ——
    /// 留着它会在代码块底多出一条空白行（同 `FileContent.lines` 的处理）。
    public init(text: String, fill: Color = Theme.Palette.surfaceSunken) {
        var raw = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if raw.last == "" { raw.removeLast() }
        self.lines = raw.map { [CodeSpan(text: $0)] }
        self.fill = fill
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(attributed)
                .font(Theme.Font.monospacedCode)
                .lineSpacing(Theme.Spacing.xs)
                // 11 / 13 是原型原值（`padding:11px 13px`）—— 4pt 阶里没有这两档，
                // 故写原值并注明出处（沿 `CardBox` 的 horizontal:14 同一做法）。
                .padding(.vertical, 11)
                .padding(.horizontal, 13)
                // 不折行（原型 `overflow-x:auto` 的对应物）：让每行保持一行、由滚动去看右边。
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // 走查第 75 条（2026-10-15）起：`fill` 由调用方给 —— 坐在页面 / 弹层底上垫
            // **面板色**（`surfaceSunken`），坐在评论气泡里才垫 `markdownPreSurface`。
            // 边框去掉（原型 `.markdown pre{border:none}`）：形状由底色表达，不画第二层。
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(fill)
        )
        // 读屏念**原文**（不着色的纯文字）。用 `attributed` 去念会把每个片段的
        // 颜色当成属性读出来（“红色 关键字 let”），那不是用户要听的东西。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.map { $0.map(\.text).joined() }.joined(separator: "\n"))
    }

    // MARK: - 拼装着色的文本

    private var attributed: AttributedString {
        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { result += AttributedString("\n") }
            for span in line {
                var piece = AttributedString(span.text)
                piece.foregroundColor = Self.color(span.tone)
                result += piece
            }
        }
        return result
    }

    // MARK: - 档位 → 颜色（纯函数，可单测）

    /// ⚠️ `number` / `type` 两档**没有**落到这里 —— 它们由调用方翻成 `.plain`。
    /// 见 `CodeTone` 与 `GitHubIcon` 同一个"规格未给"的说法。
    public nonisolated static func color(_ tone: CodeTone) -> Color {
        switch tone {
        case .plain: Theme.Palette.textPrimary
        case .keyword: Theme.Palette.syntaxKeyword
        case .string: Theme.Palette.syntaxString
        case .comment: Theme.Palette.syntaxComment
        case .function: Theme.Palette.syntaxFunction
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
        // 四档都能看见（关键字 / 函数名 / 字符串 / 注释）。
        CodeSurface(lines: [
            [CodeSpan(text: "import", tone: .keyword), CodeSpan(text: " Foundation")],
            [],
            [CodeSpan(text: "/// 块级 Markdown 渲染", tone: .comment)],
            [
                CodeSpan(text: "public func ", tone: .keyword),
                CodeSpan(text: "render", tone: .function),
                CodeSpan(text: "(_ md: "),
                CodeSpan(text: "String"),
                CodeSpan(text: ") -> "),
                CodeSpan(text: "AttributedString"),
                CodeSpan(text: " {"),
            ],
            [CodeSpan(text: "    "), CodeSpan(text: "\"一段很长的字符串字面量，用来试横向滚动会不会把整块内容压扁\"", tone: .string)],
            [CodeSpan(text: "}")],
        ])
        // 纯文本降级（语言认不出来）。
        CodeSurface(text: "some-unknown-lang line 1\n\u{0020}\u{0020}line 2")
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.surface)
}
