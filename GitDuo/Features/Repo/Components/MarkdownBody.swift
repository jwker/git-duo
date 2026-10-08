import GitDuoDesign
import GitDuoKit
import SwiftUI

/// **块级 Markdown 视图** —— 渲染 `[MarkdownBlock]`（TECH_SPEC §11.1）。
///
/// 原型 `styles/04-screens.css` 的 `.markdown` 一族：
///
/// ```css
/// .markdown{background:var(--card);border:1px solid var(--border-soft);border-radius:12px;
///           padding:16px;font-size:14px;line-height:1.65}
/// .markdown h1{font-size:22px;font-weight:750;margin:4px 0 10px;padding-bottom:8px;
///              border-bottom:1px solid var(--border-soft)}
/// .markdown h2{font-size:17px;font-weight:700;margin:14px 0 8px;padding-bottom:6px;
///              border-bottom:1px solid var(--border-soft)}
/// .markdown p{margin-bottom:9px}
/// .markdown ul{margin:0 0 9px 18px}   .markdown li{margin-bottom:4px}
/// .markdown code{background:rgba(175,184,193,.35);border-radius:5px;padding:1.5px 5px;
///                font-size:12.5px;font-family:"SF Mono",Menlo,monospace}
/// .markdown pre{background:var(--code-bg);border:1px solid var(--border-soft);border-radius:9px;
///               padding:11px 13px;overflow-x:auto;margin-bottom:10px}
/// ```
///
/// ## ⚠️ 它收领域模型 ⇒ 留 Feature（判据 #43）
///
/// 入参是 `[MarkdownBlock]`（领域模型）⇒ 不进 `GitDuoDesign`。
/// 设计包里只有"与业务无关的视觉件"：本视图用到 `CodeSurface`（代码面）。
///
/// ## ⚠️ 原型**只给了** h1 / h2 / 段落 / 列表 / 行内代码 / 代码块的样式
///
/// `MarkdownBlock` 有七种块，其中三种在 `.markdown` 里**没有任何规则**：
/// **引用**、**分隔线**、**h3–h6**、以及**任务列表的勾选框**。
/// 这四处都是「规格未给」，逐条登记在各自的注释里 ——
/// 共同原则是：**能不用新数字就不用，能用既有令牌就不新造颜色**。
/// 原型是唯一可点验收依据，替它补一套它没写过的视觉，等于把验收对象换成了我的偏好。
///
/// ## 两档版式（切片 7.4 新增）
///
/// 原型有**两套** markdown 外观：
///
/// | 档 | 原型 | 卡片框 | 内边距 | 字号 |
/// |---|---|---|---|---|
/// | `.document` | `.markdown` | 有（白底 + 1pt 浅边） | 16 | 14px |
/// | `.compact` | `.comment .bbody` | **无** | **0**（容器给，见下） | 13.5px |
///
/// 差异全部收在 `Style` 上（见那个枚举），调用方只需选一档：
/// 评论正文传 `.compact`，其余全部用默认的 `.document`。
///
/// ## ⚠️ `.compact` 的内边距是 **0**，因为容器已经给过了
///
/// 原型 `.bbody{padding:11px 13px}` 那对内边距**归容器** ——
/// `CommentBubble` 的注入槽做的就是这件事（它的说明写着"本组件只给 `padding:11px 13px`"）。
///
/// 所以这里**不能再加一遍**：两处都按原型给 11/13 的话，评论正文四周会变成 22/26，
/// 而它看起来只是"这条评论的留白偏大"，不像一个 bug —— 这正是最容易漏掉的一类。
///
/// 换句话说：`.compact` 只负责**没有卡片框**与**那一档字号 / 行距**，
/// 剩下的它交给包住它的那个气泡。等真的出现第二个不经过气泡的调用点，
/// 再决定要不要把内边距做成参数（现在没有，不预留）。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2 点名"正文"）。
struct MarkdownBody: View {

    /// 版式。原型有**两套** markdown 外观，差别不只是字号：
    ///
    /// - `.document` —— `styles/04-screens.css` 的 `.markdown`：白底卡片 + 1pt 浅边
    ///   + `padding:16px` + `font-size:14px`。README / Issue 正文 / PR 正文用它。
    /// - `.compact` —— 同文件的 `.comment .bbody`：**没有卡片框**（评论气泡自己就是容器）
    ///   + `padding:11px 13px` + `font-size:13.5px`。评论正文用它。
    ///
    /// ⚠️ 为什么是一个枚举而不是两个开关（"画不画卡片" + 一个字号）：
    /// 这两档的每个差异都是**同一件事的两面**（"这是一段正文" / "这是评论里的一段"）。
    /// 拆成两个参数就会出现 `drawsCard: false` + 正文档字号 这种原型里**不存在**的组合，
    /// 而它看起来还挺合理 —— 那种组合一旦被写出来，就没人知道该不该修。
    enum Style: Sendable {
        case document
        case compact
    }

    let blocks: [MarkdownBlock]

    /// 点一个链接时的处置。`nil` = 全部交给系统（`openURL` 默认行为）。
    ///
    /// ## 为什么需要它（2026-10-07 目视发现的第 3 条）
    ///
    /// `AttributedString.link` 上的地址由系统直接打开，而 README 里**大多数**链接是
    /// 相对地址（`[中文](README_zh.md)`）—— 系统打不开一个没有 scheme 的地址，
    /// 表现是"点了没反应"。调用方要在这一刻把它解析成仓库内的路径（`RepoLinkResolver`），
    /// 再推入对应的页面。
    ///
    /// ⚠️ 用 `OpenURLAction` 而不是"把链接的地址换掉"：换地址要在**画之前**知道
    /// 当前仓库与分支，而那正是 `AttributedString` 造好之后才有的上下文，
    /// 等于把解析时机提前到渲染里，每重绘一次解析一遍。
    ///
    /// ⚠️ 返回 `.systemAction` 表示"我不处理，按默认来"——外部地址必须走它，
    /// 否则整个 README 里的外链会静默失效。
    let onOpenLink: ((URL) -> OpenURLAction.Result)?

    /// 版式（`.document` = 正文 / `.compact` = 评论正文）。
    let style: Style

    /// ⚠️ `onOpenLink` 留在**最后一个参数位**是有意的：既有调用点（`RepoTreeSection`）
    /// 用的是**尾随闭包**写法 ——
    ///
    /// ```swift
    /// MarkdownBody(blocks: readme.blocks) { url in … }
    /// ```
    ///
    /// 尾随闭包要匹配到它。把带默认值的 `style` 排在它后面**实测仍能编译**
    /// （Swift 会跳过末尾那个非闭包参数），但那条规则对读代码的人不显然 ——
    /// 让"行为参数（闭包）留在最后一位"是这族签名一直以来的形状
    /// （`CardBox` / `ActionButton` 也都是这么排的）。
    init(
        blocks: [MarkdownBlock],
        style: Style = .document,
        onOpenLink: ((URL) -> OpenURLAction.Result)? = nil
    ) {
        self.blocks = blocks
        self.style = style
        self.onOpenLink = onOpenLink
    }

    /// 本块正文的基准字号。行内片段（粗体 / 斜体 / 行内代码）全部由它派生 ——
    /// 见 `attributed(_:base:)` 的说明：`AttributedString` 的 `.font` 是整段替换，
    /// 不基于同一个 `base` 派生的话，同一行里的粗体会比正文大一档。
    private var baseFont: Font {
        switch style {
        // 原型 `.markdown{font-size:14px}` ⇒ `markdownBody`（`.subheadline`，15pt）。
        case .document: Theme.Font.markdownBody
        // 原型 `.comment .bbody{font-size:13.5px}` ⇒ `footnote`(13pt)。
        // ⚠️ 关键是它与上一档的**相对关系**（评论正文比正文矮一档）：
        //    原型差 0.5px，这里落到相邻的两档上，差 2pt —— 属有意偏差第 12 条那一类。
        case .compact: Theme.Font.footnote
        }
    }

    /// 行距（原型 `line-height` 换算成"减去系统行高之后要补多少"）。
    ///
    /// ⚠️ 两档都**不写裸小数**（6.75 / 5.3 这种）——"不许写魔法值"在行距上同样成立。
    private var lineSpacing: CGFloat {
        switch style {
        // 原型 `line-height:1.65`：正文 15pt 时约 24.75pt，系统行高约 18pt
        // ⇒ 差额约 7pt，取 4pt 阶里的 `s`(8，略宽松一档)。
        case .document: Theme.Spacing.s
        // 原型 `line-height:1.6`：正文 13pt 时约 20.8pt，系统行高约 15.5pt
        // ⇒ 差额约 5.3pt，取 4pt 阶里最近的一档 `xs`(4)。
        case .compact: Theme.Spacing.xs
        }
    }

    /// 整块的内边距。
    private var blockPadding: EdgeInsets {
        switch style {
        // 原型 `.markdown{padding:16px}` ⇒ `Spacing.page`（16）。
        case .document:
            EdgeInsets(
                top: Theme.Spacing.page, leading: Theme.Spacing.page,
                bottom: Theme.Spacing.page, trailing: Theme.Spacing.page
            )
        // ⚠️ **零**，不是漏写：原型 `.bbody{padding:11px 13px}` 那对值由 **容器**
        //    （`CommentBubble` 的注入槽）给 —— 这里再加一遍就是 22/26（见类型说明）。
        case .compact:
            EdgeInsets()
        }
    }

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                self.view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(blockPadding)
        // 链接的落点。⚠️ 挂在最外层：`Text` 里行内链接的点击走的是**环境**里的
        // `openURL`，而不是某个修饰符 —— 包住整块才拦得到它。
        .environment(\.openURL, OpenURLAction { url in
            onOpenLink?(url) ?? .systemAction
        })

        switch style {
        case .document:
            stack
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                        .fill(Theme.Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.container, style: .continuous)
                        .stroke(Theme.Palette.borderSoft, lineWidth: 1)
                )
        case .compact:
            // 评论气泡**自己就是容器**（`.comment .bubble` 有底、有边、有圆角）
            // ⇒ 紧凑档不再画卡片框：画了就是"气泡里还套一张卡"，
            //    两层边框相隔 11pt 平行排着，在真机上比"少画一层"明显得多。
            stack
        }
    }

    // MARK: - 分派

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, spans): heading(level: level, spans: spans)
        case let .paragraph(spans): paragraph(spans)
        case let .listItem(ordered, number, depth, checked, spans):
            listItem(ordered: ordered, number: number, depth: depth, checked: checked, spans: spans)
        case let .quote(spans): quote(spans)
        case let .codeBlock(language, lines): codeBlock(language: language, lines: lines)
        case .divider: divider
        }
    }

    // MARK: - 标题

    @ViewBuilder
    private func heading(level: Int, spans: [MarkdownSpan]) -> some View {
        // 一级 / 二级：原型各给了一档字号 + 一条下边线（`.markdown h1` / `h2`）。
        //
        // ⚠️ **紧凑档（评论正文）沿用这两档绝对字号** —— 这是「规格未给」：
        //    原型 `.comment .bbody` 只给了 `p{margin-bottom:7px}`，标题在评论里
        //    一次都没出现过。没跟着缩小的后果是"评论里出现 h1 会显得很大"，
        //    但那比"替原型发明一套它没写过的评论标题字号"要好解释，也好改（就这一处）。
        if level == 1 || level == 2 {
            let isTop = level == 1
            Text(attributed(spans, base: isTop ? Theme.Font.markdownH1 : Theme.Font.markdownH2))
                .font(isTop ? Theme.Font.markdownH1 : Theme.Font.markdownH2)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineSpacing(lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                // 下边线在**内边距之内**（CSS `padding-bottom` + `border-bottom` 的顺序），
                // 所以先补下内边距、再画线，最后才是外间距。
                .padding(.bottom, isTop ? 8 : 6)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.Palette.borderSoft)
                        .frame(height: 1)
                }
                // 原型 `margin:4px 0 10px`（h1）与 `14px 0 8px`（h2）。
                .padding(.top, isTop ? Theme.Spacing.xs : 14)
                .padding(.bottom, isTop ? 10 : Theme.Spacing.s)
        } else {
            // ⚠️ **h3–h6 是「规格未给，待评审」**：原型 `.markdown` 只写了 h1 / h2，
            //    浏览器的 h3 默认字号（1.17em）× 原型字号 = 16.4px，
            //    那是**用户代理样式表**的规定，不是原型作者的选择 —— 照抄它
            //    等于把浏览器默认值当成产品决策。
            //
            //    这里取：字号与正文同档 + 加粗；上下留白**不引入新数字**，
            //    沿用 h2 的 14（同级节奏）与列表项的 4（最小间隔）。
            //    不加下边线（原型只给了 h1 / h2）。
            Text(attributed(spans, base: baseFont.weight(.bold)))
                .font(baseFont.weight(.bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineSpacing(lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
                .padding(.bottom, Theme.Spacing.xs)
        }
    }

    // MARK: - 段落

    private func paragraph(_ spans: [MarkdownSpan]) -> some View {
        Text(attributed(spans, base: baseFont))
            .font(baseFont)
            .foregroundStyle(Theme.Palette.textPrimary)
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 原型 `p{margin-bottom:9px}` —— 4pt 阶里没有 9 这一档，写原值并注明出处
            // （沿 `CardBox` 的 horizontal:14、`CodeSurface` 的 11/13 同一做法）。
            .padding(.bottom, 9)
    }

    // MARK: - 列表项

    private func listItem(
        ordered: Bool,
        number: Int?,
        depth: Int,
        checked: Bool?,
        spans: [MarkdownSpan]
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            marker(ordered: ordered, number: number, checked: checked)

            Text(attributed(spans, base: baseFont))
                .font(baseFont)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineSpacing(lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 原型 `ul{margin-left:18px}`：顶层缩进 18。
        // ⚠️ **嵌套是「规格未给，待评审」**：原型没有嵌套列表的样式。
        //    这里用"顶层那 18pt × 层级"递进 —— 不引入第二个数值，
        //    也让"缩进越深、层级越深"这件事在任何层级都读得出来。
        .padding(.leading, 18 * CGFloat(depth + 1))
        // 原型 `li{margin-bottom:4px}`。
        .padding(.bottom, Theme.Spacing.xs)
    }

    /// 列表项前面的标记。
    ///
    /// ⚠️ 两处「规格未给」：
    /// - **标记色**：原型的 `li` 没给 `::marker` 颜色 ⇒ 与正文同色（不发明第二档）；
    /// - **任务列表的勾选框**：原型一次都没渲染过任务列表（`MarkdownParser` 支持，
    ///   但它的演示数据里没有）⇒ 取**最少的视觉发明**：只用图形本身表达勾选态，
    ///   不加颜色区分。颜色一旦选中某一档，就等于替原型定了一个它没定过的视觉。
    ///
    /// 勾选框必须给读屏标签（`MarkdownCopy.checkboxLabel`）——
    /// 抹掉它等于把"这是个可勾选的任务项"这条信息静默丢弃。
    @ViewBuilder
    private func marker(ordered: Bool, number: Int?, checked: Bool?) -> some View {
        if let checked {
            Image(systemName: checked ? "checkmark.square" : "square")
                .font(baseFont)
                .foregroundStyle(Theme.Palette.textPrimary)
                .accessibilityLabel(MarkdownCopy.checkboxLabel(checked: checked))
        } else if ordered {
            // ⚠️ 用服务端给的编号，不自己从 1 数（`3. / 4. / 5.` 是有意义的，
            //    见 `MarkdownBlock.listItem` 的说明）。`number` 为 `nil` 理论上
            //    不会出现（`ordered` 为真时解析器必给号），兜底成一个圆点。
            Text(number.map { "\($0)." } ?? "•")
                .font(baseFont)
                .foregroundStyle(Theme.Palette.textPrimary)
                .monospacedDigit()
                .accessibilityHidden(true)
        } else {
            Text("•")
                .font(baseFont)
                .foregroundStyle(Theme.Palette.textPrimary)
                .accessibilityHidden(true)
        }
    }

    // MARK: - 引用

    /// 引用块。
    ///
    /// ## ⚠️ 有意偏差（已登记）：加了一条 2pt 的左侧竖条
    ///
    /// 原型的 `.markdown` **没有任何 `blockquote` 规则**，所以严格照印的结果
    /// 是"缩进 + 次级文字色"——而那样它与一个普通段落**看起来一样**
    /// （§11.1 却把引用列为支持范围，也就是说它必须能被认出来）。
    ///
    /// 取"左侧竖条 + 缩进 + 次级文字色"这一 markdown 的通用语汇，代价与理由：
    /// - **不新造颜色**：竖条用既有的 `Palette.border`（中性灰）——
    ///   选强调色会让引用在页面里抢走标题的主次；
    /// - **不新造数字**：缩进沿用列表的 18，竖条宽 2 与 `PendingSection` 的
    ///   虚线边同档（1pt 太细、画在 Retina 上会虚）。
    ///
    /// 已登记待评审：若评审认为"引用就该和段落长得一样"，删掉竖条即可，
    /// 其余不动。
    private func quote(_ spans: [MarkdownSpan]) -> some View {
        Text(attributed(spans, base: baseFont))
            .font(baseFont)
            .foregroundStyle(Theme.Palette.textSecondary)
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 18 + Theme.Spacing.s)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Theme.Palette.border)
                    .frame(width: 2)
            }
            .padding(.bottom, Theme.Spacing.xs)
    }

    // MARK: - 代码块

    private func codeBlock(language: String?, lines: [String]) -> some View {
        // ⚠️ **紧凑档沿用同一份 `CodeSurface`** —— 也是「规格未给」（原型没给
        //    `.comment .bbody pre` 的规则）。它自成一块带底色的代码面，
        //    比正文大一点不算走形；真要改，改的是 `CodeSurface` 那一档令牌。
        // 语言认不出来 ⇒ `nil` ⇒ `CodeSurface` 走纯文本降级（不去猜语言）。
        CodeSurface(
            lines: CodeHighlighting.lines(lines, language: CodeHighlighting.language(language))
        )
        // 原型 `pre{margin-bottom:10px}`。
        .padding(.bottom, 10)
    }

    // MARK: - 分隔线

    /// ⚠️ **「规格未给，待评审」**：原型 `.markdown` 也没有 `hr` 规则。
    ///
    /// 取"1pt 的 `borderSoft` 细线 + 上下 `Spacing.m`"——
    /// 颜色与粗细都照**别处的分隔线**（卡片边、标题下边线）用同两个令牌，
    /// 不新造视觉；上下留白取 4pt 阶里的一档（12）。
    private var divider: some View {
        Rectangle()
            .fill(Theme.Palette.borderSoft)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.m)
    }

    // MARK: - 行内样式（领域层的 spans → `AttributedString`）

    /// 把一段行内片段拼成 `AttributedString`。
    ///
    /// ## 为什么必须显式给出 `base`
    ///
    /// `AttributedString` 的 `.font` 是**整段替换**而不是"叠一层"：
    /// 给粗体片段只设 `.bold` 会把它退回系统默认字号，于是同一行里
    /// "**粗体**"比旁边的正文大一档。所以每个片段都要基于**本块的基准字号**
    /// 派生（`base.weight(.bold)` / `base.italic()`），而不是直接给 `.bold`。
    ///
    /// ## 两处「规格未给」的行内样式
    ///
    /// - **行内代码的圆角与内边距**：原型是 `border-radius:5px; padding:1.5px 5px`，
    ///   而 `AttributedString` 的 `backgroundColor` 画出来的是**紧贴字形的矩形**
    ///   （既不能圆角、也不能加内边距）—— 这是文字排版层的固有限制，不是偷懒。
    ///   底色本身照原型（`Palette.codeInlineSurface`），只是形状是方的、没有留白。
    ///   ⚠️ 待目视确认：`Text` 会不会渲染 run 的背景色（若不渲染，行内代码只剩等宽字形）。
    /// - **链接的颜色**：原型的 `.markdown` 没有 `a` 规则，而它一次也没渲染过链接。
    ///   取本 App 既有的链接语汇（`accent` + 无下划线，与面包屑一致），
    ///   而不是浏览器的"蓝 + 下划线"默认值。
    private func attributed(_ spans: [MarkdownSpan], base: Font) -> AttributedString {
        var result = AttributedString()
        for span in spans {
            switch span.style {
            case .text:
                result += AttributedString(span.text)

            case .bold:
                var piece = AttributedString(span.text)
                piece.font = base.weight(.bold)
                result += piece

            case .italic:
                var piece = AttributedString(span.text)
                piece.font = base.italic()
                result += piece

            case .code:
                var piece = AttributedString(span.text)
                // 12.5px ⇒ 与代码块同档（`monospacedCode`，系统 `.caption` 12pt 等宽）。
                piece.font = Theme.Font.monospacedCode
                piece.foregroundColor = Theme.Palette.textPrimary
                piece.backgroundColor = Theme.Palette.codeInlineSurface
                result += piece

            case let .link(url):
                var piece = AttributedString(span.text)
                piece.link = url
                piece.foregroundColor = Theme.Palette.accent
                result += piece
            }
        }
        return result
    }
}

#Preview {
    ScrollView {
        MarkdownBody(blocks: MarkdownParser.blocks(from: """
        # GitDuo

        为 iPhone 打造的 **GitHub 客户端**，*SwiftUI* 原生实现。
        段落里的折行会并成一段 —— 这是 markdown 的规矩。

        ## 特性

        - 列表与详情 `ETag` 条件请求，零配额刷新
        - 仓库详情四分区导航
        - 嵌套：
          - 内层一项
            - 再深一层
        - [x] 已完成的任务项
        - [ ] 还没做的任务项
        3. 有序列表保留服务端给的编号
        4. 第二项

        ### 三级标题（原型没给样式）

        > 引用：原型没有 blockquote 规则，这里加了左侧竖条。
        > 相邻两行各自成块。

        ---

        ## 快速开始

        ```swift
        let client = GitHubClient(token: store.load())
        try await client.repos(owner: "my-git")  // 一段很长的注释，用来试横向滚动
        ```

        认不出语言的代码块走纯文本降级：

        ```
        不知道这是什么语言
        ```

        一个[链接](https://github.com/my-git)在这段文字里。
        """))
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}

/// 紧凑档（评论正文）。⚠️ 外面那圈白底气泡是**手动画的** ——
/// 真实宿主是 `CommentBubble`，这里画一个是为了让"紧凑档没有卡片框"这件事看得出来。
#Preview("评论正文（.compact）") {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("紧凑档：无卡片框 · 内边距 11/13 · 正文 13pt（正文档是 15pt）")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)

            MarkdownBody(
                blocks: MarkdownParser.blocks(from: """
                已确认，修复在 `feature/auth-fix` 分支，稍后提 PR。

                - 评论里的列表
                - 第二项

                > 评论里的引用
                """),
                style: .compact
            )
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.bubble, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.bubble, style: .continuous)
                    .stroke(Theme.Palette.borderSoft, lineWidth: 1)
            )
        }
        .padding(.horizontal, Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
