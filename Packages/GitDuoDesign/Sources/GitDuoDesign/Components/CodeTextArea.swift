import SwiftUI

/// **等宽多行输入框** —— 原型 `styles/05-overlays.css` 第 18 行的 `.code-editor`
/// （PRD §4.10 的正文输入；切片 8 的编辑器是同一个类）。
///
/// ```css
/// .code-editor{width:100%;min-height:280px;border:1px solid var(--border);
///              border-radius:12px;background:var(--card);
///              font-family:Menlo,monospace;font-size:12.5px;line-height:1.65;
///              padding:12px;resize:vertical;color:var(--text)}
/// ```
///
/// ## 它与 `SheetField` 是**两个**输入框，不是一个的两种样式
///
/// | | `SheetField` | `CodeTextArea`（本件） |
/// |---|---|---|
/// | 原型 | `.sheet-input` | `.code-editor` |
/// | 字体 | 正文（`rowTitle` 15） | **等宽**（`monospaced` 13） |
/// | 底色 | `--bg`（比容器浅一层） | `--card`（与卡片同色） |
/// | 行数 | 单行 | 多行（保底若干行） |
///
/// ## 判据 #43：它进设计包
///
/// 只收 `Binding<String>` / `String` / `Int`，不认识任何领域模型。
///
/// ## ⚠️ 为什么用 `TextField(axis: .vertical)` 而不是 `TextEditor`
///
/// 因为**原型那个框有占位文案**（`描述（支持 Markdown）…`，`07-issues.js:22`），
/// 而 `TextEditor` 在 SwiftUI 里**没有** `placeholder` 这个能力 ——
/// 要用它就得在背后叠一个 `Text` 并自己管"什么时候隐藏"，那是把一件系统已有的事
/// 重新实现一遍，而且光标位置、动态字体、VoiceOver 都得自己照顾。
///
/// 代价是两处与原型不同（都已登记）：
///
/// 1. **高度由行数决定**（`.lineLimit(minLines...)`），不是 `min-height` 那个像素值。
///    原型的 `min-height:150px` 配上"没有 `height`"意味着元素随内容长高 ——
///    那与"保底 6 行、上面不封顶"是同一个行为，只是度量单位不同。
/// 2. `line-height:1.65` 落到 `.lineSpacing(Spacing.xs)`（13pt 正文的差额约 6pt，
///    取 4pt 阶里最近的一档 —— 与 `MarkdownBody.compact` 同一算法）。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct CodeTextArea: View {

    private let placeholder: String

    @Binding private var text: String

    /// 保底显示多少行。
    ///
    /// - `6` ≈ 148pt — PRD §4.10 的正文输入（原型 `style="min-height:150px"`）。
    /// - `13` ≈ 280pt — 原型 `.code-editor` 的默认值，**切片 8 的编辑器**用的是它。
    ///
    /// 默认给 6（当前唯一的调用点），切片 8 接入时显式传 13。
    private let minLines: Int

    public init(
        _ placeholder: String,
        text: Binding<String>,
        minLines: Int = 6
    ) {
        self.placeholder = placeholder
        self._text = text
        self.minLines = minLines
    }

    public var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            // 原型 `font-family:Menlo,monospace;font-size:12.5px` ⇒ `monospaced`（13pt）。
            .font(Theme.Font.monospaced)
            .foregroundStyle(Theme.Palette.textPrimary)
            .textFieldStyle(.plain)
            // 原型 `line-height:1.65`。
            .lineSpacing(Theme.Spacing.xs)
            // 至少 `minLines` 行、上面不封顶（原型那个 `min-height` + 无 `height`
            // 就是"随内容长高"）。
            .lineLimit(minLines...)
            // 原型 `padding:12px`。
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                // 原型 `border-radius:12px` ⇒ `Radius.container`。
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    // 原型 `background:var(--card)` —— 与卡片同色，**不是** `--bg`
                    //（那是 `SheetField` 的底，两者有意不同）。
                    .fill(Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                    .stroke(Theme.Palette.border, lineWidth: 1)
            )
    }
}

#Preview {
    @Previewable @State var markdown = ""
    @Previewable @State var code = "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View { EmptyView() }\n}"

    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
        // §4.10 的正文输入（保底 6 行、有占位）。
        CodeTextArea("描述（支持 Markdown）…", text: $markdown)

        // 切片 8 的编辑器那一档（保底 13 行、无占位）。
        CodeTextArea("", text: $code, minLines: 13)
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
