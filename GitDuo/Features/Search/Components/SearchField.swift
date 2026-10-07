import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 搜索输入框（PRD §4.2 结构一行；原型 `styles/03-components.css` 的 `.searchfield`）。
///
/// ```css
/// .searchfield{display:flex;align-items:center;gap:8px;background:var(--card);
///              border:1px solid var(--border);border-radius:11px;padding:8px 10px;margin-bottom:10px}
/// .searchfield input{flex:1;min-width:0;border:none;outline:none;background:none;
///                    font-size:14.5px;font-family:inherit;color:var(--text)}
/// .search-clr{width:19px;height:19px;border-radius:50%;border:none;background:var(--border);
///             color:#fff;display:flex;align-items:center;justify-content:center}
/// .search-clr svg{width:11px;height:11px;stroke:#fff;stroke-width:3}
/// ```
///
/// ## ⚠️ 它为什么是**独立的一件**，而不是写进 `SearchView`
///
/// 因为焦点这件事必须收在一处。PRD §4.2 明写"**刷新结果区时保持输入焦点与光标**"——
/// 结果区每敲一个字就整块重绘，而输入框若与它在同一个 `body` 表达式里被重新构造，
/// 只要身份（identity）有一点点变化，键盘就会收起、光标跳到末尾。
/// 把它抽成一个带 `@FocusState.Binding` 的独立视图，输入框的**位置与身份就固定了**：
/// 结果区怎么换，它都不参与。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。它是一个贴在页面顶部的输入条，不是导航控件。
struct SearchField: View {

    /// 输入原文。**由调用方写回模型**（`SearchView` 那边是一个显式 `Binding`）——
    /// 本视图不给它加任何加工（trim / 小写都不做）：GitHub 搜索本身不区分大小写，
    /// 而任何归一化都有把用户粘进来的整串改坏的风险，改坏的表现是
    /// "输入框里明明是这样，结果却不是"。
    @Binding var text: String

    /// 焦点。由调用方持有 —— 因为"进入页面自动聚焦"与"点清除后重新聚焦"
    /// 都发生在调用方（本视图只管画）。
    @FocusState.Binding var isFocused: Bool

    /// 回车。
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(Theme.Palette.textTertiary)
                .accessibilityHidden(true)

            TextField(SearchCopy.fieldPlaceholder, text: $text)
                // 原型 `font-size:14.5px` ⇒ 本仓最近的一档是 `rowTitle`（`.subheadline`），
                // 它自己的说明里就写着"14.5px 落在 `.subheadline`(15) 与 `.callout`(16) 之间，取前者"。
                .font(Theme.Font.rowTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .focused($isFocused)
                // 搜索词里出现大写与自动纠错都是碍事的（GitHub 的搜索语法区分大小写地
                // 记不住，但用户输入 `is:issue` 这种限定符时被纠错成 `is issue` 就白打了）。
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)

            if !text.isEmpty {
                clearButton
            }
        }
        // 8 / 10 是原型原值（`padding:8px 10px`）。
        .padding(.vertical, Theme.Spacing.s)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                .fill(Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                .stroke(Theme.Palette.border, lineWidth: 1)
        )
    }

    /// 清除 —— 清空输入并**重新聚焦**（PRD §4.2）。
    ///
    /// 重新聚焦不是顺手加的：点这个按钮的那一刻，第一响应者已经从输入框转走，
    /// 而不还回去的话光标就没了，用户得再点一次输入框才能继续打字。
    private var clearButton: some View {
        Button {
            text = ""
            isFocused = true
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Palette.surface)
                .frame(width: 19, height: 19)
                .background(Circle().fill(Theme.Palette.border))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("清除输入")
    }
}

#Preview {
    @Previewable @State var empty = ""
    @Previewable @State var filled = "swiftui"
    @Previewable @FocusState var focused: Bool

    VStack(spacing: Theme.Spacing.l) {
        SearchField(text: $empty, isFocused: $focused) {}
        SearchField(text: $filled, isFocused: $focused) {}
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
