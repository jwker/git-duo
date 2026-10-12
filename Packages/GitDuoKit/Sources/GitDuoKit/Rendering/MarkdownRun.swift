import Foundation

/// 一段行内片段**渲染时的切分**（2026-10-12 新增，`REVIEW-CHECKLIST` 第 58 条）。
///
/// ## 它解决什么
///
/// `MarkdownSpan` 是**行内**模型：文字、粗体、链接、图片平铺在一个数组里。
/// 而视图层能画的东西只有两种 —— 一个 `Text`（一串文字）、一张图
/// （`AttributedString` 只能带文字属性，`Text` 里插不进 `Image`）。
/// 于是要让 `看图 ![x](a.png) 这段` 里的图**真的画出来**，
/// 就必须先把片段数组切成"文字段 / 图 / 文字段"这样一串**各自能成型**的东西。
///
/// ## 切法
///
/// 连续的非图片片段合成一个 `.text`，每个图片片段**自己**成一个 `.image`：
///
/// | 输入 | 切出来 |
/// |---|---|
/// | `[图]` | `[.image]` |
/// | `[文字, 图, 文字]` | `[.text, .image, .text]` |
/// | `[图, 图]` | `[.image, .image]` |
///
/// ⚠️ **只由空白组成的文字段不单独成格**：`![a](1) ![b](2)` 里那一个空格若也切成
/// 一段，视图会画出一个空行（看起来像"图片之间莫名多了一段空白"）。
/// 反过来，`[图, 空白, 图]` 切出来是**两张图**、不是"图 + 空段 + 图"。
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
    /// ⚠️ 它至少含一个**非空白**片段（见 `MarkdownInline.runs(of:)`）——
    /// 于是视图层拿到一个 `.text` 就一定能画出一行有内容的文字。
    case text([MarkdownSpan])

    /// 一张图。`alt` 可能为空串（`![](a.png)` 就是这样写的）。
    case image(url: URL, alt: String)

    /// 这一格是不是图 —— 视图层据此决定"整段用一个 `Text`"还是"拆成竖排"。
    public var isImage: Bool {
        if case .image = self { return true }
        return false
    }
}

extension MarkdownInline {

    /// 把一段行内片段按"文字段 / 图"切开（判据见 `MarkdownRun`）。
    ///
    /// ⚠️ 它**不改变**任何片段的文字与样式：切出来的东西拼回去与输入逐字相等，
    /// 只是多了"哪几段是一格"这条信息。所以它不归解析器管（`MarkdownSpan`
    /// 该怎么解析还怎么解析），只有一个职责：**分组**。
    public static func runs(of spans: [MarkdownSpan]) -> [MarkdownRun] {
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
            case let .image(url):
                flush()
                runs.append(.image(url: url, alt: span.text))
            default:
                pending.append(span)
            }
        }
        flush()

        return runs
    }
}
