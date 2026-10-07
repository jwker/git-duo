import Foundation

/// 一份已经解析好的 Markdown 文档。
///
/// ## 为什么把"原文 + 块"一起带着，而不是只带块
///
/// 两者都有用处，且**只留其中之一都会强迫某一层重做一遍**：
/// - `blocks` 是渲染用的（`MarkdownBody` 吃它）；
/// - `source` 是"复制原文"用的（README 目前没有这个入口，但切片 8 的
///   「复制文件内容」会需要它）。
///
/// ## ⚠️ 解析在这里做一次，不在视图的 `body` 里
///
/// `MarkdownParser.blocks(from:)` 是纯函数，**每次调用都会重新扫一遍全文**。
/// 放进 `body` 意味着每次重绘（滚动、状态变化、字体变化）都重扫一次 ——
/// 对一份 8KB 的 README 是几千次字符串操作，而它每次都算出**同一个结果**。
///
/// 这也不是"过早优化"：把解析点放在取数那一层是**结构上更正确**的位置
/// （数据到手 → 归一化成可渲染的形状 → 视图只负责画），
/// 而顺带就没有了重复计算的问题。
public struct MarkdownDocument: Sendable {

    /// 原始 Markdown。
    public let source: String

    /// 解析出来的块（§11.1）。
    public let blocks: [MarkdownBlock]

    public init(source: String, blocks: [MarkdownBlock]) {
        self.source = source
        self.blocks = blocks
    }

    /// 从原文解析一份 —— 唯一该用的构造入口（保证 `source` 与 `blocks` 同源）。
    public init(_ source: String) {
        self.init(source: source, blocks: MarkdownParser.blocks(from: source))
    }

    /// 有没有可渲染的内容 —— 空白 README（只有换行）不该画出一个空区块。
    public var isEmpty: Bool { blocks.isEmpty }
}
