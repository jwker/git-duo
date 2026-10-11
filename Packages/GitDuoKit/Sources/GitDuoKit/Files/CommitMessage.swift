import Foundation

/// 提交信息的**拆分规则** —— 首行是标题、其余是正文（git 的约定）。
///
/// ## 为什么单独提出来
///
/// 同一条规则在两个地方要用：提交详情页的标题与正文（`CommitDetail.headline` / `.body`）、
/// 以及提交列表行的标题（`RepoCommitMapper` 喂给 `CommitSummary.message` 的那一段）。
/// （2026-10-11 之前还有第三个用处 —— 文件树每行的副标题，那条链路已删。）
///
/// 两处各写一遍的后果不是"多几行代码"，而是**它们会分叉**：
/// 某一处改了 `trimmingCharacters`、另一处没改，于是同一个提交在列表里与在详情页里
/// 显示成两个不同的标题 —— 而两处单看都正常。
///
/// ⚠️ 判据里有两条容易被"简化"掉的东西，都保留在这一个实现里：
/// - **只吃行尾的空白**（`trimmingCharacters(in: .whitespaces)`）：
///   `"feat: x\r"`（CRLF 检出的仓库）不加处理会把 `\r` 带进标题，
///   于是它在界面上表现为标题末尾一个看不见的空位；
/// - **空白首行要回落到调用方给的值**（`fallback`）：空标题与"还没加载出来"
///   在界面上是同一种样子，会让用户以为这一条一直没加载完。
///
/// ⚠️ **换行必须先归一（CRLF 事故，2026-10-07）**：
/// **Swift 把 `\r`、`\n`、`\r\n` 当作三个互不相同的 `Character`**
/// ⇒ 直接 `split(separator: "\n")` **在 CRLF 上永远匹配不上**，
/// 于是 `"fix: x\r\n\r\n正文"` 会被当成**一整段没有换行的信息**：
/// 文件树每行的副标题（该处已于 2026-10-11 删除）显示成"标题 + 正文"挤在一起，
/// 详情页正文变成 `nil`（整块不渲染）。
/// 而**单看任何一处都不报错** —— 这正是它难被发现的原因。
/// GitHub 上确有用 Windows 编辑器提交的仓库，这不是假想：`\r\n` 是**真实输入**。
/// 归一的做法与 `FileContent.lines(of:)` / `UnifiedDiffParser` 保持同一套规矩
/// （那两处一直是先 `replacingOccurrences(of: "\r\n", with: "\n")` 再处理）。
public enum CommitMessage {

    /// 把 CRLF 归一成 LF —— 包内所有"按行拆"的地方共用这一条。
    ///
    /// 单独留一个函数而不是内联：**另有一处漏了它就是一条看不见的缺陷**，
    /// 集中在一处至少让 `grep "\\r\\n"` 查得出来。
    static func normalized(_ message: String) -> String {
        message.replacingOccurrences(of: "\r\n", with: "\n")
    }

    /// 信息**首行**（标题）。空白 ⇒ 返回 `fallback`。
    ///
    /// - Parameter fallback: 信息为空时显示什么。调用点给的是短 SHA——
    ///   它至少能告诉用户"这一条确实存在、只是没写信息"。
    public static func firstLine(_ message: String, fallback: String) -> String {
        let first = normalized(message)
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? fallback : first
    }

    /// 首行之后的**正文**；没有正文（或只有空白）时为 `nil`。
    ///
    /// ⚠️ 返回 `nil` 而不是空串：详情页据此**整块不渲染**（不画一片空白）。
    public static func body(_ message: String) -> String? {
        let parts = normalized(message)
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let rest = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }
}
