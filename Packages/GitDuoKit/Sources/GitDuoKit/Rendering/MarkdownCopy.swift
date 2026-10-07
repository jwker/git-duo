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
}
