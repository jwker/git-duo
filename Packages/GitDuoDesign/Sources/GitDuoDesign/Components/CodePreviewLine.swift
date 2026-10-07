import SwiftUI

/// 代码预览行 —— 搜索结果「代码」范围那一行等宽小字（原型 `.sr-code`，PRD §4.2）。
///
/// ```css
/// .sr-code{font-family:"SF Mono",Menlo,monospace;font-size:11.5px;color:var(--text2);
///          background:var(--code-bg);border-radius:6px;padding:5px 8px;margin-top:5px;
///          white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
/// ```
///
/// ## 为什么它必须是"一行"且截尾
///
/// 预览行的作用是"让你瞄一眼这段代码像不像你要找的"，不是读代码 ——
/// 真读代码要点进去（PRD §4.2 的去向是只读文件页）。所以 `white-space:nowrap` +
/// `text-overflow:ellipsis` 是**有意的**：折行会让一行结果变成三行，
/// 一屏就只能放下两三条结果，搜索页也就不成其为列表了。
///
/// ## ⚠️ 它不认识"文件路径 / 仓库 / 语言"
///
/// 只收一段 `text`。路径、`仓库 · 语言` 那些是结果行的事，由调用方按领域模型渲染
/// （决策 #43：参数用领域模型的卡片留 Feature）。这一件只回答"一小块代码长什么样"。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct CodePreviewLine: View {

    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(Theme.Font.monospacedPreview)
            .foregroundStyle(Theme.Palette.textSecondary)
            // 5 / 8 是原型原值（`padding:5px 8px`）。
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Theme.Palette.codeSurface)
            )
            // 单行 + 截尾（原型 `white-space:nowrap; text-overflow:ellipsis`）。
            .lineLimit(1)
            .truncationMode(.tail)
            // 这一行是纯代码片段，读屏只需原样念出来 —— 它的上下文（路径、仓库、语言）
            // 在结果行的另外两行里，不该被这里重复一遍。
            .accessibilityLabel(text)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
        CodePreviewLine(text: "let client = GitHubClient(token: store.load())")
        CodePreviewLine(text: "import SwiftUI")
        // 长行必须截尾而不是折行 —— 这一条就是拿来看这件事的。
        CodePreviewLine(
            text: "public func search(query: String, sort: String, order: String = \"desc\", perPage: Int = 30, cursor: URL?) async throws -> SearchResult<SearchRepositoryDTO>"
        )
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.surface)
}
