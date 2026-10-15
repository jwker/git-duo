import SwiftUI

/// **评论输入区** —— 原型 `styles/04-screens.css` 的 `.composer`。
///
/// ```css
/// .composer{background:var(--card);border:1px solid var(--border-soft);border-radius:13px;
///           padding:10px;display:flex;gap:8px;align-items:flex-end}
/// .composer textarea{flex:1;border:none;resize:none;font-family:inherit;font-size:14px;
///                    height:38px;background:transparent;outline:none;line-height:1.5}
/// ```
///
/// 原型两处用到它：提交详情页（`06-files.js:136`）与 PR 详情页（`08-pr.js:59`），
/// 切片 7 起还要加 Issue 详情与新建 Issue —— **四处的形状是同一个**。
///
/// ## 判据 #43：它进设计包
///
/// 只收 `Binding<String>` / `String` / `Bool` / 一个闭包，不认识任何领域模型
/// ⇒ 参数全是基础类型。**占位由宿主传**，因为四个调用点的占位本来就不一样
/// （Issue 是 `写评论… (Markdown 支持)`、PR 是 `写评论…` —— 原型逐字如此）。
///
/// ## ⚠️ 按钮**始终可点**（空内容不是"禁用"，是给一句提示）
///
/// PRD §4.11 的口径是「输入非空时把评论追加到列表；**空内容时提示先写内容**」——
/// 原型 `sendPrComment` 也是这么做的（`if(!v){ toast('先写点内容再发送'); return; }`）。
///
/// 所以本件**不接收 `canSend`**：一旦有这个参数，就会有人拿它去 `.disabled`，
/// 而图灰的按钮不会告诉用户"为什么点不动"。空内容那一步由宿主在 `onSend` 里
/// 判一下、给 `ConversationCopy.emptyCommentToast`。
///
/// ## ⚠️ 两处「规格未给」
///
/// 1. **在途态**：原型是同步完成的，没有"发送中"这一帧。而真实请求要等 ——
///    不给任何表示的话，用户会连点、发出多条。这里用 `ActionButton.isWorking`
///    （转圈 + 禁用防重复提交，§8.5「操作类」的通用做法）。
/// 2. **多行高度**：原型 `height:38px` 是**固定**的（多行会内部滚动）。
///    这里取 `lineLimit(1...4)`：输入框随内容长高、到 4 行封顶再滚。
///    固定高度在手机上"看不见自己写的第二行"，比长高更糟。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct CommentComposer: View {

    @Binding private var text: String

    /// 占位文案。**由宿主传**（四处调用点里有两处不同，见类型说明）。
    public let placeholder: String

    /// 按钮文案（`ConversationCopy.sendAction`）。
    public let sendTitle: String

    /// 在途（按钮转圈 + 禁用，防重复提交）。
    public let isSending: Bool

    private let onSend: () -> Void

    public init(
        text: Binding<String>,
        placeholder: String,
        sendTitle: String,
        isSending: Bool = false,
        onSend: @escaping () -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.sendTitle = sendTitle
        self.isSending = isSending
        self.onSend = onSend
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
            // 原型 `font-size:14px` ⇒ 与 `.markdown` 正文同为 14px ⇒ `markdownBody`(15pt)。
            // 用 `TextField(axis: .vertical)` 而不是 `TextEditor`：后者自带滚动与内边距，
            // 把它压进这个 38pt 高的壳里要违着它的默认外观拧好几处。
            TextField(placeholder, text: $text, axis: .vertical)
                .font(Theme.Font.markdownBody)
                .foregroundStyle(Theme.Palette.textPrimary)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .frame(maxWidth: .infinity, alignment: .leading)

            ActionButton(
                title: sendTitle,
                style: .primary,
                // 原型那两处的按钮都是 `padding:9px 14px`（`.btn` 默认纵向 9、横向覆写成 14）。
                verticalPadding: 9,
                horizontalPadding: 14,
                // 行内按钮：按内容宽、`fixedSize` 保证不被输入框压扁。
                fillsWidth: false,
                isWorking: isSending,
                action: onSend
            )
        }
        // 原型 `padding:10px` ⇒ 最近一档（8 与 12 各差 2）。取 12 是为了保住
        // "容器内边距 > 按钮纵向内边距(9)" 这个比例 —— 取 8 会让按钮比容器边距还厚。
        .padding(Theme.Spacing.m)
        .background(
            // 原型 `border-radius:13px` 在圆角阶里**没有对应档**（12 与 14 各差 1）。
            // 取 `container`(12)：它就在对话区（与 `Radius.bubble`(12) 同值），
            // 差 1pt 属有意偏差第 12 条那一类。
            // 方案 D（2026-10-15，走查第 73 条）：白卡 → 浅灰面，边框去掉
            //（原型 `.composer{background:var(--chip);border:none}`）。
            RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                .fill(Theme.Palette.surfaceSunken)
        )
    }
}

#Preview {
    @Previewable @State var text = ""
    @Previewable @State var sending = false

    VStack(spacing: Theme.Spacing.m) {
        CommentComposer(
            text: $text,
            placeholder: "写评论… (Markdown 支持)",
            sendTitle: "发送"
        ) {}

        CommentComposer(
            text: .constant("在途的样子：按钮转圈且不可重复点。"),
            placeholder: "写评论…",
            sendTitle: "发送",
            isSending: true
        ) {}
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
