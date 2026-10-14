import Foundation

/// 块级 Markdown 视图（§11.1）里**唯一**几句不是来自文档本身的文本。
///
/// ## 为什么几乎不需要它
///
/// Markdown 视图显示的每一个字都来自 README / 正文本身 ——
/// 没有标题、没有按钮、没有空态。所以这里只收**给读屏用**的那一句：
/// 任务列表的勾选框是一个图标，图标不说明"勾了没有"，读屏用户就丢了信息。
///
/// 与 `CommitCopy.diffToggleAccessibilityLabel(file:isExpanded:)` 同一条纪律：
/// **无障碍文本也是产品文案**，同样不许散在视图里（它能被单测钉住，散在视图里不能）。
public enum MarkdownCopy {

    /// 任务列表勾选框（`- [x] 标题`）的读屏标签。
    ///
    /// ⚠️ **规格未给，待评审**：原型没有渲染过任务列表（`MarkdownParser` 支持它，
    /// 但原型的 README 演示数据里一个都没有），PRD §4.4 也未提。
    /// 这里取"勾选态"的最直白说法，待评审时若定下别的措辞改这一处即可。
    ///
    /// 之所以必须有这么一句：`Image(systemName: "checkmark.square")` 若不给标签，
    /// 要么念出英文符号名、要么被 `accessibilityHidden` 抹掉 —— 后者会让
    /// 读屏用户完全不知道这是个可勾选的任务项（**信息被静默丢弃**）。
    public static func checkboxLabel(checked: Bool) -> String {
        checked ? "已完成" : "未完成"
    }

    // MARK: - 图片（2026-10-12 新增，走查第 58 条）

    /// 图片**加载中**那行说明。
    ///
    /// ⚠️ **「规格未给，待评审」**：原型一次都没画过 markdown 里的图
    /// （`.markdown` 里连一条 `img` 规则都没有），所以"加载中长什么样"没有任何依据。
    /// 取"一块浅底 + 一个图标 + 这一句"：纯空白的占位块看起来像**坏了**，
    /// 而一句话能让"这里马上会有一张图"这件事成立。
    public static let imageLoadingText = "图片加载中"

    /// 图片**加载失败**那行说明。
    ///
    /// ⚠️ 有 `alt` 就点出是哪一张 —— 一屏里两张图都失败时，
    /// 「图片加载失败」×2 分不出是哪一张没出来。
    public static func imageFailureText(alt: String) -> String {
        alt.isEmpty ? "图片加载失败" : "图片加载失败：\(alt)"
    }

    /// 图片**是 SVG、本版不渲染**那行说明（2026-10-14 新增）。
    ///
    /// ## ⚠️ 为什么要与上面那一句分开
    ///
    /// 2026-10-14 用户报回"README 里一部分图没出来"，而**那些图全都是 SVG**
    /// （`image/svg+xml`）。在此之前两种情况都显示「图片加载失败」——
    /// 那句话**把排查方向指错了**：它听起来像网络问题，而实际上字节早就取回来了，
    /// 只是 `UIImage` 画不了矢量图。
    ///
    /// 分开之后用户至少知道"这不是我网络的问题、也不是仓库的问题"，
    /// 也知道**这一版就是看不到它**（不是等一下就好）。
    ///
    /// ⚠️ 措辞取「SVG 图片：」而不是「图片加载失败」：这是**有意裁剪**
    /// （同第 58 条"图片这一期不画"那条口径），不是能力上的缺陷 ——
    /// 真要画出来得引 `WKWebView` 逐张截图，代价与收益不成比例
    /// （登记在 `REVIEW-CHECKLIST` 第 **64** 条那一段补记里）。
    /// 2026-10-14 当晚用户要求把「暂不渲染」四字去掉，遂收成「SVG 图片：xxx」。
    public static func imageUnsupportedFormatText(alt: String) -> String {
        alt.isEmpty ? "SVG 图片" : "SVG 图片：\(alt)"
    }

    /// 图片的读屏标签。
    ///
    /// ⚠️ 有 `alt` 就用 `alt` 本身（写它的人已经描述过这张图了，不必再套一层
    /// 「图片：」）；没有说明这张图**没有替代文字** —— 读屏用户至少知道
    /// 这里有一张图、而不是一段被吞掉的内容。
    public static func imageAccessibilityLabel(alt: String) -> String {
        alt.isEmpty ? "无替代文字的图片" : alt
    }

    /// **行内**图片在拼 `AttributedString` 时用的兜底文字。
    ///
    /// ⚠️ **2026-10-12 当天收窄过**：它原先服务"所有混在文字里的图"（那一档整体
    /// 降级成一个可点的链接），用户报回"图还是没出来"之后，段落 / 列表项 / 引用 /
    /// 表格单元格改走 `MarkdownBody.spanContent`（图**真的画出来**）
    /// ⇒ 这一句现在**只剩标题**还用得上（`heading` 仍是一个 `Text`：
    /// 标题必须一行，在里面塞一张图连原型都没有依据）。
    ///
    /// `alt` 有就用 `alt`，没有就用这一句 —— 一个**看不见但能点**的空白是最坏的结果。
    public static let inlineImageFallbackText = "图片"

    /// 一个 shields.io 徽章的读屏标签（2026-10-14，走查第 **65** 条）。
    ///
    /// ⚠️ **不能只念文字**：徽章是一张图，读屏用户看到的是"这里有个东西"，
    /// 而它的全部内容就是那两句话 ⇒ 念出来即可，但要**先说明这是个徽章** ——
    /// 否则一句 `license MIT OR Apache-2.0` 混在正文里像作者随手写的一行字。
    ///
    /// ⚠️ `label` 为空（Discord 那种单段徽章）时不补一个空位，只念 message。
    public static func badgeAccessibilityLabel(label: String?, message: String) -> String {
        guard let label, !label.isEmpty else { return "徽章：\(message)" }
        return "徽章：\(label) \(message)"
    }
}
