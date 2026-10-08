import SwiftUI

/// 一条**提示条** —— 原型 `scripts/06-files.js` 里的 `#sendErr`（发送失败那条）。
///
/// ```html
/// <div style="background:var(--del-bg);color:var(--del-tx);border-radius:9px;
///             padding:9px 12px;font-size:12.5px">⚠ 发送失败：网络不可用。草稿已保留，可重试。</div>
/// ```
///
/// ## 判据 #43：它进设计包
///
/// 只收一个 `String`，不认识任何领域模型。文案由领域层给
/// （发送失败那一句是 `ConversationCopy.sendFailureNotice`，里面已经带了 `⚠`）。
///
/// ## ⚠️ 颜色借的是 diff 那两对（已登记待评审）
///
/// 原型这两个变量的值与 `Palette.diffDeletedSurface`(`0xFFEBE9`) /
/// `diffDeletedText`(`0xCF222E`) **逐字相同**。
///
/// 但名字说的是 diff —— 语义并不完全重合。这里**先复用**，理由是"不新造令牌"优先于
/// "名字更好听"（新造一对 `dangerSurface`/`dangerText` 是一次设计决策，得有人拍板）。
/// **已登记待评审**：若将来要让失败提示与 diff 删除**能分开调色**，就把这一对换掉，
/// 本文件是唯一要改的地方之一（另一处是 `DiffCard`）。
///
/// ## 两档色调（切片 8.3 补口）
///
/// 原型里这种"圆角底 + 一行说明"的条**有两对颜色**，是同一个类的同一个用法：
///
/// | 出处 | 底色 / 字色 | 对应 |
/// |---|---|---|
/// | `06-files.js` 的 `#sendErr`（发送失败） | `--del-bg` / `--del-tx` | `.danger` |
/// | `15-sheets.js` 的 `#newBranchRow`（新分支 + PR 提示） | `--add-bg` / `--add-tx` | `.add` |
///
/// 两对在 `styles/01-base.css` 里就是并列声明的，值与
/// `Palette.diffAddedSurface`(`0xDAFBE1`) / `diffAddedText`(`0x116329`) 逐字相同。
///
/// ⚠️ **加参数而不是抄第二份**：本条的"圆角 / 内边距 / 字号 / 逐字不改写文案"
/// 四件事只有这一份实现，抄一份出来这三处会各自漂移，而漂移处看起来仍然像一条提示条。
/// 默认 `.danger` ⇒ 既有两个调用点（Issue / PR 详情的发送失败）**一个字都不用改**。
///
/// ⚠️ 判据 **#43**：`Tone` 是纯视觉枚举（两档色对），不认识任何领域模型 ——
/// 它**不叫** `.sendFailure` / `.newBranchPrompt`（那会把业务词收进设计包）。
///
/// ## ⚠️ 它**不自己计时**
///
/// 原型 `14-shell.js` 的 `fakeSend` 显示它之后 **2600ms 自动隐藏** —— 那是演示节奏。
/// PRD §4.9 只逐字给了文案，**没给停留时长**。
///
/// 所以本件是**纯展示**：显示与隐藏由宿主决定（`if let notice { NoticeBar(text: notice) }`）。
/// 把 2.6 秒写进设计包，等于把一个演示值升格成产品行为 ——
/// 而它最要紧的那句恰恰是"草稿已保留，**可重试**"，自动消失会让这句话连同重试的引导一起没了。
///
/// 原型外层还有 `margin-top:8px`，那是它与上方内容之间的距离 ⇒ **留在宿主**（由页面排布决定）。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2 —— 玻璃只给导航层）。
public struct NoticeBar: View {

    /// 两档色调 —— 原型里这两对颜色是**并列声明**的（`01-base.css` 第 8 行）。
    ///
    /// ⚠️ 名字是 `danger` / `add`（视觉词），不是 `sendFailure` / `newBranchPrompt`
    /// （业务词）—— 判据 #43，设计包里只有与业务无关的视觉件。
    public enum Tone: Sendable, Hashable {

        /// 危险 / 失败那一对（原型 `--del-bg` / `--del-tx`）。
        case danger

        /// 新增 / 进行中那一对（原型 `--add-bg` / `--add-tx`）。
        case add
    }

    public let text: String

    public let tone: Tone

    public init(text: String, tone: Tone = .danger) {
        self.text = text
        self.tone = tone
    }

    /// 字色。⚠️ 非 `private`：单测要能钉住"哪一档取的是哪一对令牌"。
    var foreground: Color {
        switch tone {
        case .danger: Theme.Palette.diffDeletedText
        case .add: Theme.Palette.diffAddedText
        }
    }

    /// 底色。
    var surface: Color {
        switch tone {
        case .danger: Theme.Palette.diffDeletedSurface
        case .add: Theme.Palette.diffAddedSurface
        }
    }

    public var body: some View {
        Text(text)
            // 原型 `font-size:12.5px`。最近的**语义**档是 `footnote`(13pt，"补充说明")。
            //
            // ⚠️ 12.5px 在本项目另有一个 T4 先例 —— `.crumb` 取的是 `.caption`(12pt)。
            //    这里没沿用：那个令牌的名字叫 `breadcrumb`，拿它画提示条，
            //    名字就不说真话了（将来调面包屑字号会顺手改掉提示条）。
            //    比原型大 0.5pt，属有意偏差第 12 条那一类（原型点数落到别档取最近一档）。
            .font(Theme.Font.footnote)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 原型 `padding:9px 12px` ⇒ 垂直最近一档 `s`(8)、水平正好 `m`(12)。
            .padding(.vertical, Theme.Spacing.s)
            .padding(.horizontal, Theme.Spacing.m)
            .background(
                // 原型 `border-radius:9px` ⇒ `Radius.control`（该档的第四处来源，已在令牌注释登记）。
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(surface)
            )
            // 整条合成一个元素：读屏一次读完，而不是"⚠"、"发送失败："、正文分三段。
            .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.m) {
        NoticeBar(text: "⚠ 发送失败：网络不可用。草稿已保留，可重试。")
        // 切片 8 那一档（§5.9 提交弹层选「新分支 + PR」时的提示条）。
        NoticeBar(
            text: "将创建新分支并自动打开 Pull Request，改动不直接进 main",
            tone: .add
        )
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
