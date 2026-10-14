import Foundation

/// 一段行内片段**渲染时的分行**（2026-10-12 新增，`REVIEW-CHECKLIST` 第 58 条；
/// 2026-10-14 改成"行"的粒度，第 **65** 条）。
///
/// ## 它解决什么
///
/// `MarkdownSpan` 是**行内**模型：文字、粗体、链接、图片平铺在一个数组里。
/// 而视图层能画的东西只有两种 —— 一个 `Text`（一串文字）、一张图或一个徽章
/// （`AttributedString` 只能带文字属性，`Text` 里插不进 `Image`）。
/// 于是要让 `看图 ![x](a.png) 这段` 里的图**真的画出来**，
/// 就必须先把片段数组切成"文字段 / 图 / 文字段"这样一串**各自能成型**的东西。
///
/// ## 切法
///
/// 连续的非图片片段合成一个 `.text`，图片与徽章各成一格（`.item`）：
///
/// | 输入 | 切出来 |
/// |---|---|
/// | `[图]` | `[.item(.image)]` |
/// | `[文字, 图, 文字]` | `[.text, .item(.image), .text]` |
/// | `[图, 图]`（两张都宽度已知） | `[.row([.image, .image])]` |
/// | `[图, 图]`（宽度未知） | `[.item(.image), .item(.image)]` |
///
/// ⚠️ **只由空白组成的文字段不单独成格**：`![a](1) ![b](2)` 里那一个空格若也切成
/// 一段，视图会画出一个空行（看起来像"图片之间莫名多了一段空白"）。
///
/// ## ⚠️ 2026-10-14：为什么多了"并排"这一档
///
/// 从前每一格**自成一行**（`VStack`）。那对**大截图**是对的，对 README 开头那排
/// "许可证 / 构建状态"徽章则是错的 —— 四张 20pt 高的徽章被排成四行、吃掉 216pt，
/// 正文被挤得很长（用户 2026-10-14 报回「四张徽章排成四行」）。
/// GitHub 网页上它们是**横着排在一行**的。
///
/// ### 判据：连续 ≥2 个「**宽度已知**」的项 ⇒ 并排
///
/// ⚠️ **刻意不用"尺寸阈值"**（"小于 32pt 就算小图"那类）。那会引入一个
/// 解释不清来源的魔法数，而且判错的样子是"某张图莫名掉到下一行"。
/// 换成这条之后，判据完全落在**作者自己写的东西**上：
///
/// - **把几张图连着写在一段里**，本来就是"我要它们并排"的意思
///   （大截图作者会各给一段）；
/// - 而"宽度已知"排掉的是**写不出宽度的图** —— 那种图在视图层**必须占满一行**
///   （它的宽度得等字节到手才知道），把它塞进并排行只会把版面算崩。
///
/// | 真实数据 | 宽度 | 判成 |
/// |---|---|---|
/// | shields.io 徽章（`<img>` 一个尺寸都没写） | 徽章自算 | 并排 ✓ |
/// | `docs/images/*.png` 大截图（各占一段） | 未知 | 不并排（本来就该独占一行）✓ |
/// | 应用图标 `<img width="32" height="32">` | 32 | 并排（若连着写）✓ |
/// | `![](a.png) ![](b.png)`（markdown 语法，无尺寸位） | 未知 | 不并排 ⚠️ 有意的降级 |
///
/// ⚠️ 最后一行如实说：**markdown 图片语法里没有尺寸位** ⇒ 手写的
/// `![](a.png) ![](b.png)` 拿不到宽度、仍旧各占一行。要并排就写成
/// `<img width=…>`（GitHub 上也只有这么写才控制得住尺寸）。
///
/// ## ⚠️ 为什么这一层在领域层
///
/// `make test` **不编译 App target** ⇒ 切分规则写在视图里就**跑不进单测**
/// （同 `RepoCopy.clipboardPath` / `EditorCopy.defaultNewFilePath` 的处置）。
/// 而它错了的样子是"图掉到下一行""图与图之间多一截空白"这种很容易被当成
/// 排版问题放过去的东西 —— 正好是最该钉住的那一类。
public enum MarkdownRun: Equatable, Hashable, Sendable {

    /// 一串**不含图片**的行内片段（粗体 / 斜体 / 代码 / 链接 / 文字混在一起）。
    ///
    /// ⚠️ 它至少含一个**非空白**片段（见 `MarkdownInline.rows(of:)`）——
    /// 于是视图层拿到一个 `.text` 就一定能画出一行有内容的文字。
    case text([MarkdownSpan])

    /// **单独占一行**的一格（一张图或一个徽章）。
    case item(Item)

    /// **并排的一行** —— 至少两格（`MarkdownInline.rows(of:)` 保证）。
    ///
    /// ⚠️ 宽度由各格自己的内容决定，超出可用宽度时**整体换行**（视图层的 flow 布局）。
    case row([Item])

    /// 一格"不是文字"的内容。
    public enum Item: Equatable, Hashable, Sendable {

        /// 一张图。`alt` 可能为空串（`![](a.png)` 就是这样写的）。
        ///
        /// `size` 是 HTML `<img>` 声明的尺寸（2026-10-14 新增）；markdown 语法写的图是 `nil`。
        /// ⚠️ 它必须**穿过这一层**：视图靠它决定占位块多高、小图要不要限宽、
        /// **以及这一格能不能与旁边的并排**（见上面那张表）。
        case image(url: URL, alt: String, size: MarkdownImageSize?)

        /// 一个 shields.io 徽章（2026-10-14 新增）。**不取字节**，解地址就能画。
        case badge(MarkdownBadge)
    }
}

extension MarkdownRun {

    /// 这一行是不是文字 —— 视图层据此决定"用一个 `Text`"还是"画图 / 徽章"。
    public var isText: Bool {
        if case .text = self { return true }
        return false
    }

    /// 这一行里有几格"不是文字"的东西（`.text` 恒为 0，`.row` 是它的格数）。
    public var itemCount: Int {
        switch self {
        case .text: 0
        case .item: 1
        case let .row(items): items.count
        }
    }
}

extension MarkdownInline {

    /// 把一段行内片段切成**可以看到的一行行**东西（判据见 `MarkdownRun`）。
    ///
    /// ⚠️ 它**不改变**任何片段的文字与样式：切出来的东西拼回去与输入逐字相等，
    /// 只是多了"哪几格在同一行"这条信息。所以它不归解析器管（`MarkdownSpan`
    /// 该怎么解析还怎么解析），只有一个职责：**分组**。
    public static func rows(of spans: [MarkdownSpan]) -> [MarkdownRun] {
        group(items(of: spans))
    }

    /// 第一遍：按"文字段 / 视觉格"切开，**不管并排**。
    private static func items(of spans: [MarkdownSpan]) -> [MarkdownRun] {
        var runs: [MarkdownRun] = []
        var pending: [MarkdownSpan] = []

        func flush() {
            // ⚠️ 只由空白组成的段**丢掉**，不单独成格：图与图之间那个空格
            //    若也成一格，视图会画出一行空行（见 `MarkdownRun` 的说明）。
            if pending.contains(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) {
                runs.append(.text(pending))
            }
            pending = []
        }

        for span in spans {
            switch span.style {
            case let .image(url, size):
                flush()
                runs.append(.item(item(url: url, alt: span.text, size: size)))
            default:
                pending.append(span)
            }
        }
        flush()

        return runs
    }

    /// 一个图片片段该画成什么 —— **徽章优先**。
    ///
    /// ⚠️ 这里就是"徽章"这一档进来的**唯一入口**：`MarkdownBadge.parse` 判得出
    /// 就画成徽章，判不出仍旧是一张普通的图（它自带一整套取字节与占位块）。
    static func item(url: URL, alt: String, size: MarkdownImageSize?) -> MarkdownRun.Item {
        if let badge = MarkdownBadge.parse(url: url, alt: alt) { return .badge(badge) }
        return .image(url: url, alt: alt, size: size)
    }

    /// 第二遍：把**连续 ≥2 个宽度已知的格**并成一行（判据见 `MarkdownRun`）。
    private static func group(_ runs: [MarkdownRun]) -> [MarkdownRun] {
        var result: [MarkdownRun] = []
        var pending: [MarkdownRun.Item] = []

        func flush() {
            switch pending.count {
            case 0: break
            case 1: result.append(.item(pending[0]))
            default: result.append(.row(pending))
            }
            pending = []
        }

        for run in runs {
            guard case let .item(item) = run, isPairable(item) else {
                // ⚠️ 撞上一个**不能并排**的东西就断开 —— 一行里混进"得占满整行"的图，
                //    那一行的宽度就没法算了（见 `MarkdownRun` 那张表最后一行）。
                flush()
                result.append(run)
                continue
            }
            pending.append(item)
        }
        flush()

        return result
    }

    /// 这一格能不能与旁边的并排 —— 见 `MarkdownRun` 那张表。
    private static func isPairable(_ item: MarkdownRun.Item) -> Bool {
        switch item {
        case .badge:
            // 徽章的宽度由它自己的文字算出来，不依赖任何取数 ⇒ 恒可并排。
            true
        case let .image(_, _, size):
            // 图只有**作者写了宽度**时才排得进去（`width="32"` 那种）。
            // `width="100%"` 会在解析时化成 `nil`（百分比不是长度）⇒ 自然落进"不并排"。
            size?.width != nil
        }
    }
}
