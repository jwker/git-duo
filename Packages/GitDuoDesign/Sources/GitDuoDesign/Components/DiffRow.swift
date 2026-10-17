import SwiftUI

/// diff 里的**一行** —— 原型 `styles/04-screens.css` 的 `.dline` / `.hunk`。
///
/// ```css
/// .dline{display:flex;font-family:"SF Mono",Menlo,monospace;font-size:11px;
///        line-height:1.9;white-space:pre}
/// .dline .ln{width:34px;text-align:right;padding-right:8px;color:var(--text3);
///            flex-shrink:0;user-select:none}
/// .dline.add{background:var(--add-bg)}.dline.add .code{color:var(--add-tx)}
/// .dline.del{background:var(--del-bg)}.dline.del .code{color:var(--del-tx)}
/// .dline .code{padding:0 10px;overflow:hidden;text-overflow:ellipsis}
/// .hunk{background:#ddf4ff;color:#0969da;font-family:Menlo,monospace;
///       font-size:11px;padding:3px 10px}
/// ```
///
/// ⚠️ **2026-10-17：那一对蓝搬进了 `hunkSurface` / `hunkText` 两个专属令牌**
/// （此前借的是 `accentSubtle` / `accent`）。主色统一为橙后，diff 的记号**不该跟着变橙** ——
/// hunk 头是 diff 自己的行文记号，与 `diffAddedText` / `syntaxKeyword` 同类，不是品牌色。
///
/// ## ⚠️ 它只收基础类型（判据 #43）
///
/// 收 `number` / `text` / `tone` 三个基础类型，**不认识** `DiffLine` / `DiffHunk`。
/// 「哪一行该画哪个号」「`\ No newline` 算不算一行」都是领域层的事
/// （`DiffLine.displayNumber`、`UnifiedDiffParser`）；设计包只回答"红底那一行长什么样"。
/// 收领域模型的 `DiffCard` 因此留在 Feature（`GitDuo/Features/Repo/Components/`）。
///
/// ## ⚠️ 六档，其中两档是原型里没有的
///
/// 原型只演示了四种（hunk 头 / 上下文 / 删除 / 新增）。另外两档来自领域层的
/// `DiffLine.Kind`，**必须有地方落**，否则那两种行会整行消失（"少一行而没有任何迹象"）：
/// - `.note` = `\ No newline at end of file` —— 一条**关于上一行**的说明，
///   不是文件里的一行（所以不画行号、不吃行号）；
/// - `.content` = 认不出来的非标准行 —— **照原文显示、不上色**（照原文是重点：
///   丢掉它会让用户看到的 diff 与真实改动不一致）。
///
/// 两档都用中性色，**不发明新视觉**：原型没给它们配色，就不该由这里挑一个。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2 点名"diff 卡片"）。
public struct DiffRow: View {

    /// 一行在 diff 里的角色。
    public enum Tone: Sendable, Hashable, CaseIterable {

        /// 上下文行（未改动）。原型 `.dline`（无 add / del 后缀）。
        case context

        /// 新增行。原型 `.dline.add`。
        case added

        /// 删除行。原型 `.dline.del`。
        case removed

        /// hunk 头（`@@ -40,7 +40,9 @@`）。原型 `.hunk` —— **独占一行、无行号**。
        case hunk

        /// `\ No newline at end of file`（原型没有这一档，见类型说明）。
        case note

        /// 认不出来的非标准行（原型没有这一档，见类型说明）。
        case content
    }

    /// 行号。`nil` ⇒ **不画行号列**（hunk 头 / note / content 三种都没有）。
    ///
    /// ⚠️ 画哪一侧的号由调用方决定（领域层的 `DiffLine.displayNumber`），
    /// 这里**不做回落** —— 两处都回落就等于两套规则。
    public let number: Int?

    public let text: String

    public let tone: Tone

    public init(number: Int? = nil, text: String, tone: Tone) {
        self.number = number
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if let number {
                Text(String(number))
                    .font(Theme.Font.monospacedPreview)
                    // 行号列宽 34（原型原值）。⚠️ 34 里含右侧那 8pt 内边距
                    // （原型 `*{box-sizing:border-box}`），所以两个修饰符的顺序不能反：
                    // 先右对齐撑满、再补 8pt 内边距、最后把整列钉回 34。
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, Theme.Spacing.s)
                    .frame(width: 34)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    // 行号是**参照物不是内容**：可选中的话，
                    // 用户拖选一段 diff 会连带把行号一起复制出去。
                    .textSelection(.disabled)
                    .accessibilityHidden(true)
            }

            Text(text)
                .font(Theme.Font.monospacedPreview)
                .foregroundStyle(Self.textColor(tone))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                // ⚠️ 原型 `.dline .code{overflow:hidden;text-overflow:ellipsis}` ⇒
                // **截尾而不是折行**（与 `CodeSurface` 的横向滚动是两种做法，都有意。
                // 长行会被切掉，这一点已登记待评审）。
                // hunk 头是唯一例外：原型 `.hunk` 没有 nowrap，它会折行（长表头带函数上下文时会占两行）。
                .lineLimit(tone == .hunk ? nil : 1)
                .truncationMode(.tail)
        }
        // 原型 `line-height:1.9`（11px ⇒ 约 21pt 一行），系统行高约 13pt
        // ⇒ 上下各补 4pt（4pt 阶里的 `xs`）。
        .padding(.vertical, tone == .hunk ? 3 : Theme.Spacing.xs)
        .background(Self.surface(tone))
        // 读屏：把 `+` / `−` 补回去。⚠️ 这两个符号不是新文案 ——
        // 它们就是 diff 格式本身的记号（领域层的 `DiffLine.text` 有意去掉了它们，
        // 因为视觉上底色已经表达；但读屏没有底色，不补就分不出增与删）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityPrefix(tone) + text)
    }

    // MARK: - 档位 → 配色 / 前缀（纯函数，可单测）

    /// 行底色。`.clear` 表示**用容器的底**（原型的上下文行没有 background）。
    public nonisolated static func surface(_ tone: Tone) -> Color {
        switch tone {
        case .context: .clear
        case .added: Theme.Palette.diffAddedSurface
        case .removed: Theme.Palette.diffDeletedSurface
        case .hunk: Theme.Palette.hunkSurface
        // 两档中性：不发明新视觉（原型没给它们配色）。
        case .note, .content: .clear
        }
    }

    /// 行文字色。
    public nonisolated static func textColor(_ tone: Tone) -> Color {
        switch tone {
        case .context: Theme.Palette.textPrimary
        case .added: Theme.Palette.diffAddedText
        case .removed: Theme.Palette.diffDeletedText
        case .hunk: Theme.Palette.hunkText
        // `\ No newline` 是**注解**（比代码轻一档）；未知行是**原文**（与上下文同重）。
        case .note: Theme.Palette.textTertiary
        case .content: Theme.Palette.textPrimary
        }
    }

    /// 读屏前缀（diff 格式自身的记号，不是产品文案）。
    public nonisolated static func accessibilityPrefix(_ tone: Tone) -> String {
        switch tone {
        case .added: "+ "
        case .removed: "− "
        case .context, .hunk, .note, .content: ""
        }
    }

    /// 这一档有没有行号列。给测试用（视图里靠 `number == nil` 判断）。
    public nonisolated static func showsNumberColumn(_ tone: Tone) -> Bool {
        switch tone {
        case .context, .added, .removed: true
        case .hunk, .note, .content: false
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        DiffRow(text: "@@ -40,7 +40,9 @@ func body() -> some View {", tone: .hunk)
        DiffRow(number: 40, text: "        PaginatedList(items: store.repos) {", tone: .context)
        DiffRow(number: 41, text: "            Button { selection = repo } label: {", tone: .removed)
        DiffRow(number: 41, text: "            NavigationLink(value: repo) {", tone: .added)
        DiffRow(text: "\\ No newline at end of file", tone: .note)
        DiffRow(text: "某些工具插的非标准行", tone: .content)
    }
    .background(Theme.Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous))
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
