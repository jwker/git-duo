import Foundation

/// 一段行内文本的样式（TECH_SPEC §11.1「支持范围」）。
///
/// ## ⚠️ 有意**不嵌套**
///
/// `**粗体里有 `代码`**` 这种嵌套，本解析器**不会**把内层也解析出来 ——
/// 它会得到一段 `.bold`，文字是 `粗体里有 `代码``（含反引号）。
/// 完整递归解析要引入一棵行内树，而 §11.1 列出的支持范围（标题、段落、列表、
/// 引用、行内代码、代码块、链接、粗斜体、分隔线、任务列表）**没有要求嵌套**。
/// 少做一层递归换来的是"解析结果是一维数组"，视图一个 `Text` 拼接就能渲染。
/// ## ⚠️ `Hashable` 是给**评论**要的（切片 7.4）
///
/// `IssueComment` / `PullTimelineItem` 是 `Hashable`，而它们从 7.4 起各自带着
/// 一份解析好的 `[MarkdownBlock]`（见那两个类型的说明）。合成 `Hashable` 会把
/// 每个存储属性都算进去 ⇒ 这里必须是 `Hashable`，否则那两个类型编译不过。
///
/// 让它 `Hashable` 是**纯扩张**：`Hashable` 是 `Equatable` 的子集关系里的超集，
/// 既有代码一句都不用改（只是多了一个能力）。
public struct MarkdownSpan: Equatable, Hashable, Sendable {

    /// 可见文字（已去掉标记符号）。
    public let text: String

    public let style: Style

    public init(text: String, style: Style = .text) {
        self.text = text
        self.style = style
    }

    public enum Style: Equatable, Hashable, Sendable {

        /// 普通文字（**兜底**，解析不出任何标记时的默认值）。
        case text

        /// 行内代码 `` `x` `` —— 等宽 + 底色的那一小段。
        case code

        case bold

        case italic

        /// 链接。⚠️ 带 `URL` 而不是 `String`：无效地址在**解析阶段**就被丢掉
        /// （退回普通文本），视图拿到的永远是一个能打开的地址。
        case link(URL)

        /// 图片（**行内**的那一档，2026-10-12 新增 —— 走查第 58 条）。
        ///
        /// ⚠️ **独立成段的图片不走这里** —— 那一种在 `MarkdownParser` 里被提成
        /// `MarkdownBlock.image`（块级、间距按代码块那一档）。留下这一档是给
        /// **混在文字里**的图片（`看图 ![x](a.png) 这里`），而它在视图层由
        /// `MarkdownInline.rows(of:)` 切成独立的一格、**同样真的画出来**
        /// （`MarkdownBody.spanContent`）—— 只是"图与文字同一行"会排成
        /// "文字 / 图 / 文字"的竖排，不做横排混流。
        ///
        /// ⚠️ `text` 是 `alt`（替代文字），**允许为空** —— 这与 HTML 那条降级的
        /// 老规矩（alt 为空则整张丢掉）有意不同：那时候丢掉是对的（纯文字里没有落点），
        /// 现在图是真的要画出来的，一张没有 alt 的图不该因此消失。
        /// 地址同样带 `URL`，无效地址在解析阶段就被退回普通文本。
        ///
        /// ## `size`（2026-10-14 新增）
        ///
        /// 来自 HTML `<img width= height=>` 那对属性 —— markdown 语法**没有**尺寸位，
        /// 所以只有 HTML 来源的图才可能带它（`MarkdownHTML.blocks(from:)` 回填，
        /// 见 `MarkdownBlock.applyingImageSizes`）。`nil` = 没声明过。
        case image(URL, size: MarkdownImageSize?)

        /// 解析样式时用的**标记符号**，供 `plainText` 与调试。
        ///
        /// 它不进界面 —— 存在只是为了在断言里区分"这段是粗体"与"这段是纯文本"时
        /// 能读出原因，以及在拼 `plainText` 时判断要不要补回符号。
        public var isEmphasized: Bool {
            switch self {
            case .bold, .italic: true
            case .text, .code, .link, .image: false
            }
        }
    }

    /// 读屏与"复制原文"用的纯文字（丢掉全部样式）。
    public static func plainText(of spans: [MarkdownSpan]) -> String {
        spans.map(\.text).joined()
    }
}

/// 表格列的对齐方式（GFM 分隔行里的 `:` 决定）。
public enum MarkdownTableAlignment: Equatable, Hashable, Sendable {
    /// 左对齐（`:---`，或没写 `:` 的默认值）。
    case left
    /// 居中（`:---:`）。
    case center
    /// 右对齐（`---:`）。
    case right
}

/// 一个 GFM 表格块（表头 + 对齐 + 数据行）。
///
/// 单元格内容是行内片段（走 `MarkdownInline.spans`），所以表格里的 `**粗体**` /
/// `` `代码` `` / `[链接]()` 照常渲染。
public struct MarkdownTable: Equatable, Hashable, Sendable {

    /// 每列对齐；列数与表头一致，没写 `:` 的列回落为 `.left`。
    public let alignments: [MarkdownTableAlignment]

    /// 表头：一行单元格，每个单元格是行内片段。
    public let header: [[MarkdownSpan]]

    /// 数据行：多行，每行是与表头等列的单元格数组。
    public let rows: [[[MarkdownSpan]]]

    public init(
        alignments: [MarkdownTableAlignment],
        header: [[MarkdownSpan]],
        rows: [[[MarkdownSpan]]]
    ) {
        self.alignments = alignments
        self.header = header
        self.rows = rows
    }
}

/// 一张图**声明的尺寸**（HTML `<img width= height=>`，2026-10-14 新增）。
///
/// ## 为什么需要它（两个病一起治）
///
/// 1. **占位块的高度**：不知道尺寸时占位块恒为 `Spacing.page × 8`（128pt）——
///    而 README 开头那排"构建状态 / 许可证"徽章真实高度只有 20pt 上下，
///    于是四张徽章占掉半屏，正文被挤得很长（用户 2026-10-14 的截图正是这样）。
/// 2. **小图被放大**：`MarkdownImage` 用 `resizable` 画图，不给上限时一张 16×16
///    的徽章会**撑满整屏宽** —— 上限本来只从"已解码的 `UIImage`"上取，
///    而仓库外的绝对地址（`AsyncImage` 那条路）拿不到它。
///
/// ## ⚠️ 单位：CSS 像素，这里**当 pt 用**
///
/// GitHub 页面上的 `width="200"` 是 200 个 CSS px；iOS 的 pt 与它**语义相同**
/// （都是"与设备无关的逻辑长度"）⇒ 直接当 pt 用，观感与网页一致。
/// 不乘任何缩放系数 —— 乘了反而会在大屏 / 小屏上偏离网页。
///
/// ## ⚠️ 它是"声明"，不是"事实"
///
/// 作者写的 `width` 可能不准（也可能只写了 `height`）。所以它**只用两处**：
/// 占位块的高度、以及渲染时的宽度上限。真实尺寸到位后，宽度上限取两者中**更小**的
/// （见 `MarkdownImage.imageWidthLimit`）—— 声明值再离谱也不会把小图拉大。
public struct MarkdownImageSize: Equatable, Hashable, Sendable {

    /// `width` 属性；没写、或不是合法整数（`width="100%"`）时为 `nil`。
    public let width: Int?

    /// `height` 属性；同上。
    public let height: Int?

    public init(width: Int? = nil, height: Int? = nil) {
        self.width = width
        self.height = height
    }

    /// 两个都没解析出来 ⇒ 等于没声明过（调用方据此不必造一个空对象）。
    public var isEmpty: Bool { width == nil && height == nil }
}

/// 一个块级元素（TECH_SPEC §11.1）。
///
/// ## ⚠️ 关于「输出 `AttributedString`」的一处**实现偏离**（已登记）
///
/// §11.1 的方案栏写的是"输出 `AttributedString` + 自定义 `AttributedStringKey`"。
/// 这里改为**纯结构模型**，理由是三条，且都不是偏好问题：
///
/// 1. **本包是领域层，不得 import SwiftUI / UIKit**（`AGENTS.md` 的铁律）。
///    `AttributedString` 本身在 Foundation 里，但它的**自定义 key**、
///    以及"代码块要单独用等宽视图"这件事，都只能由视图层决定 ——
///    于是必然出现"领域层造了一半的排版信息、视图层再拆开"的往返。
/// 2. **可测性**：`[MarkdownBlock]` 能用 `==` 逐块断言
///    （"这个 `#` 变成了 `heading(level: 1)`"）；
///    `AttributedString` 的断言要读 runs、逐段比 attribute，写成测试后极难维护。
/// 3. **视图本来就要分开画**：§11.1 自己写着"代码块单独用等宽视图 + 横向滚动" ——
///    也就是说输出从一开始就是**异构**的，硬塞进一个 `AttributedString`
///    反而要在视图层按 range 反查块边界、再拆开。
///
/// 所以领域层出结构，视图层出样式。这不是"少做"，是把职责放回各自该在的地方。
/// ## ⚠️ `Hashable`：理由与 `MarkdownSpan` 同一个（切片 7.4 的评论要用）
public enum MarkdownBlock: Equatable, Hashable, Sendable {

    /// 标题，`level` 为 1–6（`#` 的个数）。
    case heading(level: Int, spans: [MarkdownSpan])

    /// 段落。
    case paragraph([MarkdownSpan])

    /// 列表项。
    ///
    /// - `ordered`: 有序（`1.`）还是无序（`-` / `*` / `+`）。
    /// - `number`: 有序列表项的编号（`1.` → `1`）；无序为 `nil`。
    ///   ⚠️ 保留服务端给的编号，不自己从 1 数 —— 一段 `3. / 4. / 5.` 是有意义的。
    /// - `depth`: 嵌套层级，**从 0 开始**（0 = 顶层）。
    /// - `checked`: 任务列表的勾选态（`- [x]`）；非任务列表为 `nil`。
    case listItem(ordered: Bool, number: Int?, depth: Int, checked: Bool?, spans: [MarkdownSpan])

    /// 引用（`> `）。⚠️ **每一行各自成块**（相邻的引用块在渲染上没有间距，看起来是一段）。
    case quote([MarkdownSpan])

    /// 代码块。
    ///
    /// - `language`: fence 后面那个词（```` ```swift ```` ⇒ `"swift"`）；没写为 `nil`。
    /// - `lines`: **已按行拆好**（尾部那个由"文件以换行结尾"产生的空串已去掉）。
    case codeBlock(language: String?, lines: [String])

    /// 分隔线（`---` / `***` / `___`）。
    case divider

    /// GFM 表格（`MarkdownTable`）。
    case table(MarkdownTable)

    /// 图片（**独占一段**的那一档，2026-10-12 新增 —— 走查第 58 条）。
    ///
    /// ## 为什么是块、不是又一个 `MarkdownSpan.Style`
    ///
    /// 图片在 markdown 语法里是**行内**元素（`MarkdownSpan.Style.image` 就是它），
    /// 但真画出来时它占满一整行、要限宽、要有加载占位 —— 这些都不是"文字的一段"
    /// 能表达的东西。所以**独占一段的图片被提成块**（`MarkdownParser` 里那一步）。
    ///
    /// ⚠️ **提到块上只是"间距"的差别，不是"画不画"的差别**：混在文字里的图由
    /// `MarkdownInline.rows(of:)` 切成独立的一格、照样画得出来
    /// （`MarkdownBody.spanContent`）；这一档额外拿到的是**块与块之间**那档间距
    /// （原型 `.markdown pre{margin-bottom:10px}`），以及"这一段只有它"的排版自由。
    ///
    /// ⚠️ **为什么不把混排也做成"文字 图 文字"横着排**：`Text` 里插不进一张图，
    /// 真做混流就得自己实现换行 / 行距 / 首行缩进 —— 这三件事现在全部由 `Text`
    /// 统一处理，拆开等于把正文的排版规则重做一遍。代价是"图与文字同行"时图会
    /// 掉到自己那一行 —— 登记在 `TECH_SPEC §11.1`。
    ///
    /// - `alt`: 替代文字，**可以为空**（读屏标签与加载失败时的说明都用它）。
    /// - `size`: HTML `<img>` 声明的尺寸；markdown 语法写的图是 `nil`。
    case image(url: URL, alt: String, size: MarkdownImageSize?)

    /// 这段块是不是空的（**不渲染任何东西**）。
    ///
    /// 空白块要能被识别出来：列表之间、代码块之后常常夹着空行，
    /// 若把它们也当成 `.paragraph([])`，视图会画出一个个空段落，
    /// 页面上的垂直间距会莫名其妙地大。
    public var isEmpty: Bool {
        switch self {
        case let .heading(_, spans), let .paragraph(spans), let .quote(spans):
            !Self.hasContent(spans)
        case let .listItem(_, _, _, _, spans):
            !Self.hasContent(spans)
        case let .codeBlock(_, lines):
            lines.allSatisfy { $0.isEmpty }
        case let .table(table):
            table.rows.isEmpty
              && !Self.hasContent(table.header.flatMap { $0 })
        case let .image(url, _, _):
            // ⚠️ **地址为空才算空**，`alt` 空不算 —— 一张没有替代文字的图仍然要画。
            url.absoluteString.isEmpty
        case .divider:
            false
        }
    }

    /// 一组行内片段里有没有**能显示出来的东西**。
    ///
    /// ## ⚠️ 为什么不能只看 `text` 空不空（2026-10-12 修）
    ///
    /// 图片片段**可以有空的 `text`**（`![](a.png)` 的替代文字就是空的），
    /// 而它**仍然是一张要画出来的图**（视图层给它兜底文字，见
    /// `MarkdownSpan.Style.image`）。
    ///
    /// 按"文字非空"判的后果很隐蔽：`> ![](a.png)` 与 `- ![](a.png)`
    /// 会被上面 `isEmpty` 判成空块、被 `MarkdownParser` 的
    /// `filter { !$0.isEmpty }` **静默丢掉** —— 屏幕上表现为"引用里 / 列表项里
    /// 那张图不见了"，而没有任何一处会报错。
    private static func hasContent(_ spans: [MarkdownSpan]) -> Bool {
        spans.contains { span in
            if case .image = span.style { return true }
            return !span.text.isEmpty
        }
    }
}

// MARK: - 按 HTML 声明的尺寸补全（2026-10-14）

extension MarkdownBlock {

    /// 把 `<img width= height=>` 声明的尺寸补到块里的那些图片上。
    ///
    /// ## 为什么是"补"而不是"解析时带上"
    ///
    /// `MarkdownHTML` 走的是**改写成 markdown 源**再解析那条路（本件抬头的论证：
    /// 一切复用块判定 / 行内解析 / 实体 / 列表栈），而 **markdown 图片语法里没有尺寸位**
    /// —— 改写出来的 `![alt](src)` 无处安放 `width` / `height`。
    ///
    /// 三条路可选：① 造一条非标准的扩展语法（`![alt](src){width=96}`），
    /// ② 绕过字符串、让 HTML 那一支直接产块，③ **解析完再回填**。
    /// 选 ③ 的理由：①② 都要动**公共的解析路径**（手写的 markdown 也会吃到新语法 /
    /// HTML 那一支要抄一遍块判定），而尺寸是 **HTML 特有的东西**
    /// ⇒ 它就该留在 HTML 特有的入口里（`MarkdownHTML.blocks(from:)` 调它）。
    ///
    /// ## 键为什么是 `absoluteString` 而不是 `src` 原文
    ///
    /// 两边（造表那一侧与这里）都过一遍 `URL(string:)?.absoluteString` ——
    /// 这样 `src` 里含空格之类需要编码的字符时**两边算出来的是同一串**。
    /// 只拿原文对原文、或原文对 `URL`，都会在那些边角上静默 miss（图照样画，
    /// 只是尺寸没了 —— 而那看起来像"作者没写尺寸"）。
    func applyingImageSizes(_ sizes: [String: MarkdownImageSize]) -> MarkdownBlock {
        guard !sizes.isEmpty else { return self }

        func fixed(_ spans: [MarkdownSpan]) -> [MarkdownSpan] {
            spans.map { span in
                guard case let .image(url, size) = span.style, size == nil,
                      let declared = sizes[url.absoluteString]
                else { return span }
                return MarkdownSpan(text: span.text, style: .image(url, size: declared))
            }
        }

        switch self {
        case let .heading(level, spans):
            return .heading(level: level, spans: fixed(spans))
        case let .paragraph(spans):
            return .paragraph(fixed(spans))
        case let .listItem(ordered, number, depth, checked, spans):
            return .listItem(
                ordered: ordered, number: number, depth: depth, checked: checked, spans: fixed(spans)
            )
        case let .quote(spans):
            return .quote(fixed(spans))
        case let .table(table):
            return .table(table.applyingImageSizes(sizes))
        case let .image(url, alt, size):
            guard size == nil, let declared = sizes[url.absoluteString] else { return self }
            return .image(url: url, alt: alt, size: declared)
        case .codeBlock, .divider:
            return self
        }
    }
}

extension MarkdownTable {

    /// 表格单元格里的图片同样要补 —— 与 `MarkdownBlock.applyingImageSizes` 同一件事
    /// （HTML 表格里放徽章是常见写法，漏了这一支的症状正是"表格里的图占位块还是 128pt"）。
    func applyingImageSizes(_ sizes: [String: MarkdownImageSize]) -> MarkdownTable {
        guard !sizes.isEmpty else { return self }

        func fixed(_ row: [[MarkdownSpan]]) -> [[MarkdownSpan]] {
            row.map { cell in
                cell.map { span in
                    guard case let .image(url, size) = span.style, size == nil,
                          let declared = sizes[url.absoluteString]
                    else { return span }
                    return MarkdownSpan(text: span.text, style: .image(url, size: declared))
                }
            }
        }

        return MarkdownTable(
            alignments: alignments,
            header: fixed(header),
            rows: rows.map(fixed)
        )
    }
}
