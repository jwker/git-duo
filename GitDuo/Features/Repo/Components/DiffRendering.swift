import GitDuoDesign
import GitDuoKit

/// `DiffLine` → `DiffRow` 的**翻译**。
///
/// ## 为什么必须有这一层（同 `CodeHighlighting` 的理由）
///
/// 两侧互不认识：`GitDuoDesign` 不得 import 领域层、领域层不得 import SwiftUI。
/// 所以"领域的行档位怎么画"这件事**只能**落在 App 层 —— 而 App target 没有测试 target。
/// 唯一的守卫是**穷尽 `switch`**：领域层给 `DiffLine.Kind` 加一档时，这里**编译不过**。
///
/// 因此下面的 `switch` **一个 `default` 都不能有** —— 加了 `default` 看着更宽容，
/// 实际是把"少画一档"从编译错误降级成了静默的行为差异
/// （症状是 diff 少了几行，而屏幕上没有任何迹象）。
extension DiffLine {

    /// 行底色 / 文字色 / 读屏前缀由 `DiffRow.Tone` 决定。
    var rowTone: DiffRow.Tone {
        switch kind {
        case .context: .context
        case .addition: .added
        case .deletion: .removed
        // `\ No newline at end of file` —— 它是**注解**，不是文件里的一行。
        case .noNewline: .note
        // 认不出来的行：照原文显示、不上色（丢掉它会让 diff 少一行）。
        case .unknown: .content
        }
    }

    /// 行号列上的那个数。
    ///
    /// ⚠️ 取法与 `DiffRow.showsNumberColumn` **必须一致**：那边规定
    /// `.note` / `.content` 两档没有行号列，这边就得给 `nil` ——
    /// 给了数而列不画，是白白算一次；画了列而给 `nil`，那一列会是空的。
    ///
    /// ⚠️ 上下文行/删除行/新增行取哪个号有讲究，见 `DiffLine.displayNumber`
    /// （新号优先，登记为「规格未给，待评审」）。
    var rowNumber: Int? {
        switch kind {
        case .context, .addition, .deletion: displayNumber
        case .noNewline, .unknown: nil
        }
    }
}
